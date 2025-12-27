// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "../utils/BaseGroupTest.sol";
import {
    GroupTokenJoinManualScore
} from "../../src/base/GroupTokenJoinManualScore.sol";
import {GroupTokenJoin} from "../../src/base/GroupTokenJoin.sol";
import {GroupCore} from "../../src/base/GroupCore.sol";
import {
    IGroupScore,
    MAX_ORIGIN_SCORE
} from "../../src/interface/base/IGroupScore.sol";
import {ILOVE20GroupManager} from "../../src/interface/ILOVE20GroupManager.sol";

/**
 * @title MockGroupManualScore
 * @notice Concrete implementation for testing
 */
contract MockGroupManualScore is GroupTokenJoinManualScore {
    constructor(
        address factory_,
        address tokenAddress_,
        address groupManagerAddress_,
        address stakeTokenAddress_,
        uint256 groupActivationStakeAmount_,
        uint256 maxJoinAmountMultiplier_,
        uint256 verifyCapacityMultiplier_
    )
        GroupCore(
            factory_,
            tokenAddress_,
            groupManagerAddress_,
            stakeTokenAddress_,
            groupActivationStakeAmount_,
            maxJoinAmountMultiplier_,
            verifyCapacityMultiplier_
        )
        GroupTokenJoin(tokenAddress_)
    {}

    function isJoinedValueCalculated() external pure returns (bool) {
        return false;
    }

    function joinedValue() external view returns (uint256) {
        return totalJoinedAmount();
    }

    function joinedValueByAccount(
        address account
    ) external view returns (uint256) {
        (, uint256 amount, ) = this.joinInfo(account);
        return amount;
    }

    function _calculateReward(
        uint256,
        address
    ) internal pure override returns (uint256) {
        return 0;
    }
}

/**
 * @title GroupTokenJoinManualScoreTest
 * @notice Test suite for GroupTokenJoinManualScore
 */
contract GroupTokenJoinManualScoreTest is BaseGroupTest {
    MockGroupManualScore public scoreContract;

    uint256 public groupId1;
    uint256 public groupId2;

    // Re-declare events for testing (must match interface definition exactly)
    event VerifyWithOriginScores(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        uint256 groupId,
        uint256 startIndex,
        uint256 count,
        bool isComplete
    );

    event GroupDelegatedVerifierSet(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        uint256 indexed groupId,
        address delegatedVerifier
    );

    function setUp() public {
        setUpBase();

        scoreContract = new MockGroupManualScore(
            address(mockFactory),
            address(token),
            address(groupManager),
            address(token),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            CAPACITY_FACTOR
        );

        token.mint(address(this), 1e18);
        token.approve(address(mockFactory), type(uint256).max);
        mockFactory.registerExtension(address(scoreContract), address(token));

        groupId1 = setupGroupOwner(groupOwner1, 10000e18, "TestGroup1");
        groupId2 = setupGroupOwner(groupOwner2, 10000e18, "TestGroup2");

        prepareExtensionInit(address(scoreContract), address(token), ACTION_ID);

        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );
        setupUser(
            groupOwner2,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID,
            groupId1,
            "Group1",
            0, // maxCapacity
            1e18, // minJoinAmount
            0,
            0
        );

        vm.prank(groupOwner2, groupOwner2);
        groupManager.activateGroup(
            address(token),
            ACTION_ID,
            groupId2,
            "Group2",
            0, // maxCapacity
            1e18, // minJoinAmount
            0,
            0
        );
    }

    // ============ setGroupDelegatedVerifier Tests ============

    function test_SetGroupDelegatedVerifier_Success() public {
        address delegatedVerifier = address(0x123);

        vm.prank(groupOwner1);
        scoreContract.setGroupDelegatedVerifier(groupId1, delegatedVerifier);

        assertEq(
            scoreContract.delegatedVerifierByGroupId(groupId1),
            delegatedVerifier
        );
    }

    function test_SetGroupDelegatedVerifier_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        scoreContract.setGroupDelegatedVerifier(groupId1, address(0x123));
    }

    function test_SetGroupDelegatedVerifier_SuccessWhenNotActive() public {
        advanceRound();

        vm.prank(groupOwner1, groupOwner1);
        groupManager.deactivateGroup(address(token), ACTION_ID, groupId1);

        address delegatedVerifier = address(0x123);
        vm.prank(groupOwner1);
        scoreContract.setGroupDelegatedVerifier(groupId1, delegatedVerifier);

        assertEq(
            scoreContract.delegatedVerifierByGroupId(groupId1),
            delegatedVerifier
        );
    }

    // ============ verifyWithOriginScores Tests ============

    function test_verifyWithOriginScores_ByOwner() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        uint256 round = verify.currentRound();

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80; // 80%

        vm.prank(groupOwner1);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);

        assertEq(scoreContract.originScoreByAccount(round, user1), 80);
    }

    function test_verifyWithOriginScores_ByDelegatedVerifier() public {
        address delegatedVerifier = address(0x123);

        vm.prank(groupOwner1);
        scoreContract.setGroupDelegatedVerifier(groupId1, delegatedVerifier);

        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        uint256 round = verify.currentRound();

        uint256[] memory scores = new uint256[](1);
        scores[0] = 90;

        vm.prank(delegatedVerifier);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);

        assertEq(scoreContract.originScoreByAccount(round, user1), 90);
    }

    function test_verifyWithOriginScores_RevertNotVerifier() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.prank(user2);
        vm.expectRevert(IGroupScore.NotVerifier.selector);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);
    }

    function test_verifyWithOriginScores_RevertAlreadySubmitted() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.startPrank(groupOwner1);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);

        vm.expectRevert(IGroupScore.AlreadyVerified.selector);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);
        vm.stopPrank();
    }

    function test_verifyWithOriginScores_RevertNoData() public {
        // No one joined this group, so there's no data
        uint256[] memory scores = new uint256[](0);

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupScore.NoDataForRound.selector);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);
    }

    function test_verifyWithOriginScores_RevertTooManyScores() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        // 2 scores for 1 account
        uint256[] memory scores = new uint256[](2);
        scores[0] = 80;
        scores[1] = 90;

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupScore.ScoresExceedAccountCount.selector);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);
    }

    function test_verifyWithOriginScores_RevertScoreExceedsMax() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        uint256[] memory scores = new uint256[](1);
        scores[0] = MAX_ORIGIN_SCORE + 1; // Exceeds max

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupScore.ScoreExceedsMax.selector);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);
    }

    // ============ Score Calculation Tests ============

    function test_ScoreByAccount() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        uint256 round = verify.currentRound();

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.prank(groupOwner1);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);

        // score = originScore * amount = 80 * 10e18 = 800e18
        uint256 expectedScore = 80 * joinAmount;
        assertEq(scoreContract.scoreByAccount(round, user1), expectedScore);
    }

    function test_ScoreByGroupId() public {
        uint256 joinAmount1 = 10e18;
        uint256 joinAmount2 = 20e18;
        setupUser(user1, joinAmount1, address(scoreContract));
        setupUser(user2, joinAmount2, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount1, new string[](0));

        vm.prank(user2);
        scoreContract.join(groupId1, joinAmount2, new string[](0));

        uint256 round = verify.currentRound();

        uint256[] memory scores = new uint256[](2);
        scores[0] = 80;
        scores[1] = 90;

        vm.prank(groupOwner1);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);

        // Group score = total amount (without distrust applied)
        assertEq(
            scoreContract.scoreByGroupId(round, groupId1),
            joinAmount1 + joinAmount2
        );
    }

    function test_TotalScore() public {
        uint256 joinAmount1 = 10e18;
        uint256 joinAmount2 = 20e18;
        setupUser(user1, joinAmount1, address(scoreContract));
        setupUser(user2, joinAmount2, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount1, new string[](0));

        vm.prank(user2);
        scoreContract.join(groupId2, joinAmount2, new string[](0));

        uint256 round = verify.currentRound();

        uint256[] memory scores1 = new uint256[](1);
        scores1[0] = 80;

        uint256[] memory scores2 = new uint256[](1);
        scores2[0] = 90;

        vm.prank(groupOwner1);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores1);

        vm.prank(groupOwner2);
        scoreContract.verifyWithOriginScores(groupId2, 0, scores2);

        assertEq(scoreContract.score(round), joinAmount1 + joinAmount2);
    }

    // ============ canVerify Tests ============

    function test_CanVerify_Owner() public view {
        assertTrue(scoreContract.canVerify(groupOwner1, groupId1));
        assertFalse(scoreContract.canVerify(groupOwner2, groupId1));
    }

    function test_CanVerify_DelegatedVerifier() public {
        address delegatedVerifier = address(0x123);

        vm.prank(groupOwner1);
        scoreContract.setGroupDelegatedVerifier(groupId1, delegatedVerifier);

        assertTrue(scoreContract.canVerify(delegatedVerifier, groupId1));
        assertTrue(scoreContract.canVerify(groupOwner1, groupId1));
        assertFalse(scoreContract.canVerify(user1, groupId1));
    }

    function test_DelegatedVerifier_InvalidAfterNFTTransfer() public {
        address delegatedVerifier = address(0x123);

        vm.prank(groupOwner1);
        scoreContract.setGroupDelegatedVerifier(groupId1, delegatedVerifier);

        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        uint256 round = verify.currentRound();

        // Transfer group NFT to a new owner with governance votes
        group.transferFrom(groupOwner1, groupOwner2, groupId1);

        // Delegation should be invalid after owner change
        assertFalse(scoreContract.canVerify(delegatedVerifier, groupId1));
        assertEq(
            scoreContract.delegatedVerifierByGroupId(groupId1),
            address(0)
        );

        uint256[] memory scores = new uint256[](1);
        scores[0] = 90;

        vm.prank(delegatedVerifier);
        vm.expectRevert(IGroupScore.NotVerifier.selector);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);

        // New owner can submit
        vm.prank(groupOwner2);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);

        assertEq(scoreContract.originScoreByAccount(round, user1), 90);
    }

    // ============ Verifier Tracking Tests ============

    function test_Verifiers() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));
        setupUser(user2, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        vm.prank(user2);
        scoreContract.join(groupId2, joinAmount, new string[](0));

        uint256 round = verify.currentRound();

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.prank(groupOwner1);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);

        vm.prank(groupOwner2);
        scoreContract.verifyWithOriginScores(groupId2, 0, scores);

        address[] memory verifiers = scoreContract.verifiers(round);
        assertEq(verifiers.length, 2);
        assertEq(scoreContract.verifiersCount(round), 2);
    }

    function test_VerifierByGroupId() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        uint256 round = verify.currentRound();

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.prank(groupOwner1);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);

        assertEq(scoreContract.verifierByGroupId(round, groupId1), groupOwner1);
    }

    function test_GroupIdsByVerifier() public {
        // Mint another group for owner1 - need more govVotes for multiple groups
        stake.setValidGovVotes(address(token), groupOwner1, 30000e18);
        uint256 groupId3 = group.mint(groupOwner1, "TestGroup3");

        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID,
            groupId3,
            "Group3",
            0, // maxCapacity
            1e18, // minJoinAmount
            0,
            0
        );

        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));
        setupUser(user2, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        vm.prank(user2);
        scoreContract.join(groupId3, joinAmount, new string[](0));

        uint256 round = verify.currentRound();

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.startPrank(groupOwner1);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);
        scoreContract.verifyWithOriginScores(groupId3, 0, scores);
        vm.stopPrank();

        uint256[] memory groupIds = scoreContract.groupIdsByVerifier(
            round,
            groupOwner1
        );
        assertEq(groupIds.length, 2);
        assertEq(scoreContract.groupIdsByVerifierCount(round, groupOwner1), 2);
    }

    // ============ Event Tests ============

    function test_verifyWithOriginScores_EmitsEvent() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        // Setup actionIds for this round
        uint256 round = verify.currentRound();
        vote.setVotedActionIds(address(token), round, ACTION_ID);
        // Set votes for this round
        vote.setVotesNum(address(token), round, 10000e18);
        vote.setVotesNumByActionId(address(token), round, ACTION_ID, 10000e18);

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.expectEmit(true, true, true, true);
        emit VerifyWithOriginScores(
            address(token),
            round,
            ACTION_ID,
            groupId1,
            0,
            1,
            true
        );

        vm.prank(groupOwner1);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);
    }

    function test_SetGroupDelegatedVerifier_EmitsEvent() public {
        // First initialize the contract by having someone join
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        address delegatedVerifier = address(0x123);
        uint256 round = verify.currentRound();

        vm.expectEmit(true, true, true, true);
        emit GroupDelegatedVerifierSet(
            address(token),
            round,
            ACTION_ID,
            groupId1,
            delegatedVerifier
        );

        vm.prank(groupOwner1);
        scoreContract.setGroupDelegatedVerifier(groupId1, delegatedVerifier);
    }

    // ============ Batch Submission Tests ============

    function test_verifyWithOriginScores_BatchSubmission() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));
        setupUser(user2, joinAmount, address(scoreContract));
        setupUser(user3, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));
        vm.prank(user2);
        scoreContract.join(groupId1, joinAmount, new string[](0));
        vm.prank(user3);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        uint256 round = verify.currentRound();

        // Submit in 3 batches using the same function
        uint256[] memory scores1 = new uint256[](1);
        scores1[0] = 80;

        uint256[] memory scores2 = new uint256[](1);
        scores2[0] = 90;

        uint256[] memory scores3 = new uint256[](1);
        scores3[0] = 100;

        vm.startPrank(groupOwner1);

        // First batch
        scoreContract.verifyWithOriginScores(groupId1, 0, scores1);
        assertEq(scoreContract.verifiedAccountCount(round, groupId1), 1);

        // Second batch
        scoreContract.verifyWithOriginScores(groupId1, 1, scores2);
        assertEq(scoreContract.verifiedAccountCount(round, groupId1), 2);

        // Third batch - should auto-finalize
        scoreContract.verifyWithOriginScores(groupId1, 2, scores3);
        assertEq(scoreContract.verifiedAccountCount(round, groupId1), 3);

        vm.stopPrank();

        // Verify scores
        assertEq(scoreContract.originScoreByAccount(round, user1), 80);
        assertEq(scoreContract.originScoreByAccount(round, user2), 90);
        assertEq(scoreContract.originScoreByAccount(round, user3), 100);

        // Verify finalization happened
        assertEq(scoreContract.verifierByGroupId(round, groupId1), groupOwner1);
        assertEq(scoreContract.scoreByGroupId(round, groupId1), joinAmount * 3);
    }

    // ============ isVerified Tests ============

    function test_IsVerified_ReturnsFalseBeforeVerification() public view {
        uint256 round = verify.currentRound();
        assertFalse(scoreContract.isVerified(round, groupId1));
        assertFalse(scoreContract.isVerified(round, groupId2));
    }

    function test_IsVerified_ReturnsTrueAfterVerification() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        uint256 round = verify.currentRound();

        // Before verification
        assertFalse(scoreContract.isVerified(round, groupId1));

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.prank(groupOwner1);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);

        // After verification
        assertTrue(scoreContract.isVerified(round, groupId1));
    }

    function test_IsVerified_BatchSubmission_ReturnsFalseUntilComplete() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));
        setupUser(user2, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));
        vm.prank(user2);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        uint256 round = verify.currentRound();

        uint256[] memory scores1 = new uint256[](1);
        scores1[0] = 80;

        uint256[] memory scores2 = new uint256[](1);
        scores2[0] = 90;

        vm.startPrank(groupOwner1);

        // First batch - not complete yet
        scoreContract.verifyWithOriginScores(groupId1, 0, scores1);
        assertFalse(scoreContract.isVerified(round, groupId1));

        // Second batch - now complete
        scoreContract.verifyWithOriginScores(groupId1, 1, scores2);
        assertTrue(scoreContract.isVerified(round, groupId1));

        vm.stopPrank();
    }

    function test_IsVerified_DifferentRounds() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        uint256 round1 = verify.currentRound();

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.prank(groupOwner1);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);

        assertTrue(scoreContract.isVerified(round1, groupId1));

        // Advance to next round
        advanceRound();
        uint256 round2 = verify.currentRound();

        // Round2 should not be verified
        assertFalse(scoreContract.isVerified(round2, groupId1));
        // Round1 should still be verified
        assertTrue(scoreContract.isVerified(round1, groupId1));
    }

    function test_IsVerified_DifferentGroups() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));
        setupUser(user2, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));
        vm.prank(user2);
        scoreContract.join(groupId2, joinAmount, new string[](0));

        uint256 round = verify.currentRound();

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        // Verify only groupId1
        vm.prank(groupOwner1);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);

        assertTrue(scoreContract.isVerified(round, groupId1));
        assertFalse(scoreContract.isVerified(round, groupId2));

        // Verify groupId2
        vm.prank(groupOwner2);
        scoreContract.verifyWithOriginScores(groupId2, 0, scores);

        assertTrue(scoreContract.isVerified(round, groupId1));
        assertTrue(scoreContract.isVerified(round, groupId2));
    }

    function test_verifyWithOriginScores_RevertInvalidStartIndex() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));
        setupUser(user2, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));
        vm.prank(user2);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupScore.InvalidStartIndex.selector);
        scoreContract.verifyWithOriginScores(groupId1, 1, scores); // Should start at 0
    }

    function test_verifyWithOriginScores_RevertScoresExceedAccountCount()
        public
    {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        uint256[] memory scores = new uint256[](2);
        scores[0] = 80;
        scores[1] = 90;

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupScore.ScoresExceedAccountCount.selector);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);
    }

    function test_verifyWithOriginScores_RevertAfterComplete() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.startPrank(groupOwner1);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);

        // After complete submission, _scoreSubmitted is true
        vm.expectRevert(IGroupScore.AlreadyVerified.selector);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);
        vm.stopPrank();
    }

    function test_verifyWithOriginScores_RevertFullAfterBatchStarted() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));
        setupUser(user2, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));
        vm.prank(user2);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        uint256[] memory scores1 = new uint256[](1);
        scores1[0] = 80;

        uint256[] memory scoresAll = new uint256[](2);
        scoresAll[0] = 80;
        scoresAll[1] = 90;

        vm.startPrank(groupOwner1);
        // First batch
        scoreContract.verifyWithOriginScores(groupId1, 0, scores1);

        // Trying to submit all from start fails (startIndex mismatch)
        vm.expectRevert(IGroupScore.InvalidStartIndex.selector);
        scoreContract.verifyWithOriginScores(groupId1, 0, scoresAll);
        vm.stopPrank();
    }

    function test_verifyWithOriginScores_EmitsEventWithDetails() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        uint256 round = verify.currentRound();
        vote.setVotedActionIds(address(token), round, ACTION_ID);

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.expectEmit(true, true, true, true);
        emit VerifyWithOriginScores(
            address(token),
            round,
            ACTION_ID,
            groupId1,
            0,
            1,
            true
        );

        vm.prank(groupOwner1);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);
    }
}

/**
 * @title CapacityReductionTest
 * @notice Test suite for capacity reduction coefficient calculation
 * @dev Key insight: maxVerifyCapacity is dynamic (depends on govVotes).
 *      By reducing govVotes after join but before verify, we can trigger reduction.
 */
contract CapacityReductionTest is BaseGroupTest {
    MockGroupManualScore public scoreContract;

    uint256 public groupId1;
    uint256 public groupId2;
    uint256 public groupId3;

    // Use verifyCapacityMultiplier = 1 to make maxVerifyCapacity = baseCapacity
    uint256 constant SMALL_CAPACITY_MULTIPLIER = 1;

    function setUp() public {
        setUpBase();

        // Create contract with small capacity multiplier
        scoreContract = new MockGroupManualScore(
            address(mockFactory),
            address(token),
            address(groupManager),
            address(token),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            SMALL_CAPACITY_MULTIPLIER
        );

        token.mint(address(this), 1e18);
        token.approve(address(mockFactory), type(uint256).max);
        mockFactory.registerExtension(address(scoreContract), address(token));

        // Setup single owner with 3 groups for capacity testing
        // Initial: govVotes = 10,000e18, totalGovVotes = 100,000e18
        // baseCapacity = 1_000_000e18 * 10,000e18 / 100,000e18 = 100,000e18
        stake.setValidGovVotes(address(token), groupOwner1, 10000e18);
        groupId1 = group.mint(groupOwner1, "TestGroup1");
        groupId2 = group.mint(groupOwner1, "TestGroup2");
        groupId3 = group.mint(groupOwner1, "TestGroup3");

        prepareExtensionInit(address(scoreContract), address(token), ACTION_ID);

        // Setup groupOwner1 with enough stake for 3 groups
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT * 3,
            address(groupManager)
        );

        // Activate all 3 groups
        vm.startPrank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID,
            groupId1,
            "Group1",
            0,
            1e18,
            0,
            0
        );
        groupManager.activateGroup(
            address(token),
            ACTION_ID,
            groupId2,
            "Group2",
            0,
            1e18,
            0,
            0
        );
        groupManager.activateGroup(
            address(token),
            ACTION_ID,
            groupId3,
            "Group3",
            0,
            1e18,
            0,
            0
        );
        vm.stopPrank();
    }

    /// @dev Helper to get max join amount per account
    function getMaxJoinAmount() internal view returns (uint256) {
        return groupManager.calculateJoinMaxAmount(address(token), ACTION_ID);
    }

    // ============ Capacity Reduction Tests ============

    /// @notice Test single group verification with sufficient capacity - no reduction
    function test_CapacityReduction_NoReduction() public {
        uint256 maxPerAccount = getMaxJoinAmount();
        uint256 joinAmount = maxPerAccount;

        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        uint256 round = verify.currentRound();

        uint256[] memory scores = new uint256[](1);
        scores[0] = 100;

        vm.prank(groupOwner1);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);

        // Capacity reduction should be 1e18 (no reduction)
        uint256 reduction = scoreContract.capacityReductionByGroupId(
            round,
            groupId1
        );
        assertEq(
            reduction,
            1e18,
            "Should have no reduction when within capacity"
        );

        // Group score should equal joined amount
        uint256 groupScore = scoreContract.scoreByGroupId(round, groupId1);
        assertEq(
            groupScore,
            joinAmount,
            "Group score should equal joined amount"
        );
    }

    /// @notice Test multi-group verification, both within capacity - no reduction
    function test_CapacityReduction_MultiGroup_NoReduction() public {
        uint256 maxPerAccount = getMaxJoinAmount();

        setupUser(user1, maxPerAccount, address(scoreContract));
        setupUser(user2, maxPerAccount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, maxPerAccount, new string[](0));

        vm.prank(user2);
        scoreContract.join(groupId2, maxPerAccount, new string[](0));

        uint256 round = verify.currentRound();

        uint256[] memory scores = new uint256[](1);
        scores[0] = 100;

        vm.startPrank(groupOwner1);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);
        scoreContract.verifyWithOriginScores(groupId2, 0, scores);
        vm.stopPrank();

        // Both groups should have no reduction
        assertEq(
            scoreContract.capacityReductionByGroupId(round, groupId1),
            1e18,
            "Group1 should have no reduction"
        );
        assertEq(
            scoreContract.capacityReductionByGroupId(round, groupId2),
            1e18,
            "Group2 should have no reduction"
        );
    }

    /// @notice Test partial capacity reduction by reducing govVotes after join
    function test_CapacityReduction_PartialReduction() public {
        // Join with maxPerAccount for both groups
        uint256 maxPerAccount = getMaxJoinAmount();
        uint256 joinAmount1 = maxPerAccount;
        uint256 joinAmount2 = maxPerAccount;

        setupUser(user1, joinAmount1, address(scoreContract));
        setupUser(user2, joinAmount2, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount1, new string[](0));

        vm.prank(user2);
        scoreContract.join(groupId2, joinAmount2, new string[](0));

        // CRITICAL: Reduce govVotes to trigger capacity reduction
        // Original capacity = 100,000e18, reduce to make it smaller than group1 + group2
        // New govVotes = 1,500e18 -> newCapacity = 1,000,000e18 * 1,500e18 / 100,000e18 = 15,000e18
        // joinAmount1 + joinAmount2 ≈ 20,000e18 > 15,000e18
        stake.setValidGovVotes(address(token), groupOwner1, 1500e18);

        uint256 newMaxCapacity = groupManager.maxVerifyCapacityByOwner(
            address(token),
            ACTION_ID,
            groupOwner1
        );

        uint256 round = verify.currentRound();

        uint256[] memory scores = new uint256[](1);
        scores[0] = 100;

        vm.startPrank(groupOwner1);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);
        scoreContract.verifyWithOriginScores(groupId2, 0, scores);
        vm.stopPrank();

        // Group1 should have no reduction (first group)
        assertEq(
            scoreContract.capacityReductionByGroupId(round, groupId1),
            1e18,
            "Group1 should have no reduction"
        );

        // Group2 should have partial reduction
        uint256 remainingCapacity = newMaxCapacity > joinAmount1
            ? newMaxCapacity - joinAmount1
            : 0;

        if (remainingCapacity > 0 && remainingCapacity < joinAmount2) {
            uint256 expectedReduction = (remainingCapacity * 1e18) /
                joinAmount2;
            assertEq(
                scoreContract.capacityReductionByGroupId(round, groupId2),
                expectedReduction,
                "Group2 should have partial reduction"
            );

            // Verify score calculation
            uint256 expectedScore2 = (joinAmount2 * expectedReduction) / 1e18;
            assertEq(
                scoreContract.scoreByGroupId(round, groupId2),
                expectedScore2,
                "Group2 score should be reduced"
            );
        }
    }

    /// @notice Test revert when remaining capacity is zero
    function test_CapacityReduction_RevertNoCapacity() public {
        // Join group1
        uint256 maxPerAccount = getMaxJoinAmount();
        setupUser(user1, maxPerAccount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, maxPerAccount, new string[](0));

        // Join group2
        setupUser(user2, 1e18, address(scoreContract));
        vm.prank(user2);
        scoreContract.join(groupId2, 1e18, new string[](0));

        // Reduce govVotes to make capacity = group1 joined amount
        // This leaves 0 remaining for group2
        // Set govVotes so that maxCapacity ≈ maxPerAccount
        // maxCapacity = totalSupply * govVotes / totalGovVotes * multiplier
        // We need: maxCapacity = maxPerAccount
        // govVotes = maxPerAccount * totalGovVotes / totalSupply
        uint256 totalSupply = token.totalSupply();
        uint256 totalGovVotes = 100000e18;
        uint256 targetCapacity = maxPerAccount; // exactly equal to group1
        uint256 newGovVotes = (targetCapacity * totalGovVotes) / totalSupply;
        stake.setValidGovVotes(address(token), groupOwner1, newGovVotes);

        uint256[] memory scores1 = new uint256[](1);
        scores1[0] = 100;
        uint256[] memory scores2 = new uint256[](1);
        scores2[0] = 100;

        vm.startPrank(groupOwner1);
        // First verification succeeds
        scoreContract.verifyWithOriginScores(groupId1, 0, scores1);

        // Second verification should revert (no remaining capacity)
        vm.expectRevert(IGroupScore.NoRemainingVerifyCapacity.selector);
        scoreContract.verifyWithOriginScores(groupId2, 0, scores2);
        vm.stopPrank();
    }

    /// @notice Test capacity reduction affects scoreByGroupId correctly
    function test_CapacityReduction_AffectsGroupScore() public {
        uint256 maxPerAccount = getMaxJoinAmount();
        uint256 joinAmount1 = maxPerAccount;
        uint256 joinAmount2 = maxPerAccount;

        setupUser(user1, joinAmount1, address(scoreContract));
        setupUser(user2, joinAmount2, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount1, new string[](0));

        vm.prank(user2);
        scoreContract.join(groupId2, joinAmount2, new string[](0));

        // Reduce govVotes to 1,200e18
        // newCapacity = 1,000,000e18 * 1,200e18 / 100,000e18 = 12,000e18
        // After verifying group1 (~10,000e18), remaining ≈ 2,000e18
        // reduction for group2 = 2,000 / 10,000 = 0.2
        stake.setValidGovVotes(address(token), groupOwner1, 1200e18);

        uint256 newMaxCapacity = groupManager.maxVerifyCapacityByOwner(
            address(token),
            ACTION_ID,
            groupOwner1
        );

        uint256 round = verify.currentRound();

        uint256[] memory scores = new uint256[](1);
        scores[0] = 100;

        vm.startPrank(groupOwner1);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);
        scoreContract.verifyWithOriginScores(groupId2, 0, scores);
        vm.stopPrank();

        // Verify reduction calculation
        uint256 remainingCapacity = newMaxCapacity > joinAmount1
            ? newMaxCapacity - joinAmount1
            : 0;
        uint256 expectedReduction = (remainingCapacity * 1e18) / joinAmount2;

        assertEq(
            scoreContract.capacityReductionByGroupId(round, groupId2),
            expectedReduction,
            "Reduction coefficient mismatch"
        );

        // Verify score calculation: score = joinedAmount * reduction / 1e18
        uint256 expectedScore = (joinAmount2 * expectedReduction) / 1e18;
        assertEq(
            scoreContract.scoreByGroupId(round, groupId2),
            expectedScore,
            "Group score should equal joinedAmount * reduction"
        );

        // Verify total score
        uint256 totalScore = scoreContract.score(round);
        assertEq(
            totalScore,
            joinAmount1 + expectedScore,
            "Total score mismatch"
        );
    }

    /// @notice Test three groups with progressive capacity reduction
    function test_CapacityReduction_ThreeGroups_Progressive() public {
        uint256 maxPerAccount = getMaxJoinAmount();

        setupUser(user1, maxPerAccount, address(scoreContract));
        setupUser(user2, maxPerAccount, address(scoreContract));
        setupUser(user3, maxPerAccount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, maxPerAccount, new string[](0));

        vm.prank(user2);
        scoreContract.join(groupId2, maxPerAccount, new string[](0));

        vm.prank(user3);
        scoreContract.join(groupId3, maxPerAccount, new string[](0));

        // Reduce govVotes to create progressive reduction
        // newCapacity = 20,000e18 (approx 2x maxPerAccount)
        // group1 = maxPerAccount -> remaining = 10,000e18 (no reduction)
        // group2 = maxPerAccount -> remaining = 0 or negative (reduction or revert)
        uint256 totalSupply = token.totalSupply();
        uint256 totalGovVotes = 100000e18;
        uint256 targetCapacity = maxPerAccount * 2; // 2x group capacity
        uint256 newGovVotes = (targetCapacity * totalGovVotes) / totalSupply;
        stake.setValidGovVotes(address(token), groupOwner1, newGovVotes);

        uint256 newMaxCapacity = groupManager.maxVerifyCapacityByOwner(
            address(token),
            ACTION_ID,
            groupOwner1
        );

        uint256 round = verify.currentRound();

        uint256[] memory scores = new uint256[](1);
        scores[0] = 100;

        vm.startPrank(groupOwner1);
        scoreContract.verifyWithOriginScores(groupId1, 0, scores);
        scoreContract.verifyWithOriginScores(groupId2, 0, scores);

        // Group3 should revert or have severe reduction
        uint256 remainingAfterG2 = newMaxCapacity > maxPerAccount * 2
            ? newMaxCapacity - maxPerAccount * 2
            : 0;

        if (remainingAfterG2 == 0) {
            vm.expectRevert(IGroupScore.NoRemainingVerifyCapacity.selector);
            scoreContract.verifyWithOriginScores(groupId3, 0, scores);
        } else {
            scoreContract.verifyWithOriginScores(groupId3, 0, scores);
        }
        vm.stopPrank();

        // Group1: no reduction
        assertEq(
            scoreContract.capacityReductionByGroupId(round, groupId1),
            1e18,
            "Group1 no reduction"
        );

        // Group2: check reduction
        uint256 remainingAfterG1 = newMaxCapacity > maxPerAccount
            ? newMaxCapacity - maxPerAccount
            : 0;
        if (remainingAfterG1 >= maxPerAccount) {
            assertEq(
                scoreContract.capacityReductionByGroupId(round, groupId2),
                1e18,
                "Group2 no reduction when remaining >= capacity"
            );
        } else if (remainingAfterG1 > 0) {
            uint256 expectedReduction = (remainingAfterG1 * 1e18) /
                maxPerAccount;
            assertEq(
                scoreContract.capacityReductionByGroupId(round, groupId2),
                expectedReduction,
                "Group2 should have reduction"
            );
        }
    }
}
