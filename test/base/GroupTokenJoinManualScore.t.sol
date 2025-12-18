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
        uint256 capacityFactor_
    )
        GroupCore(
            factory_,
            tokenAddress_,
            groupManagerAddress_,
            stakeTokenAddress_,
            groupActivationStakeAmount_,
            maxJoinAmountMultiplier_,
            capacityFactor_
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
    event ScoreSubmit(
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

    // ============ submitOriginScore Tests ============

    function test_SubmitOriginScore_ByOwner() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        uint256 round = verify.currentRound();

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80; // 80%

        vm.prank(groupOwner1);
        scoreContract.submitOriginScore(groupId1, 0, scores);

        assertEq(scoreContract.originScoreByAccount(round, user1), 80);
    }

    function test_SubmitOriginScore_ByDelegatedVerifier() public {
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
        scoreContract.submitOriginScore(groupId1, 0, scores);

        assertEq(scoreContract.originScoreByAccount(round, user1), 90);
    }

    function test_SubmitOriginScore_RevertNotVerifier() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.prank(user2);
        vm.expectRevert(IGroupScore.NotVerifier.selector);
        scoreContract.submitOriginScore(groupId1, 0, scores);
    }

    function test_SubmitOriginScore_RevertAlreadySubmitted() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.startPrank(groupOwner1);
        scoreContract.submitOriginScore(groupId1, 0, scores);

        vm.expectRevert(IGroupScore.VerificationAlreadySubmitted.selector);
        scoreContract.submitOriginScore(groupId1, 0, scores);
        vm.stopPrank();
    }

    function test_SubmitOriginScore_RevertNoData() public {
        // No one joined this group, so there's no data
        uint256[] memory scores = new uint256[](0);

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupScore.NoDataForRound.selector);
        scoreContract.submitOriginScore(groupId1, 0, scores);
    }

    function test_SubmitOriginScore_RevertTooManyScores() public {
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
        scoreContract.submitOriginScore(groupId1, 0, scores);
    }

    function test_SubmitOriginScore_RevertScoreExceedsMax() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        uint256[] memory scores = new uint256[](1);
        scores[0] = MAX_ORIGIN_SCORE + 1; // Exceeds max

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupScore.ScoreExceedsMax.selector);
        scoreContract.submitOriginScore(groupId1, 0, scores);
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
        scoreContract.submitOriginScore(groupId1, 0, scores);

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
        scoreContract.submitOriginScore(groupId1, 0, scores);

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
        scoreContract.submitOriginScore(groupId1, 0, scores1);

        vm.prank(groupOwner2);
        scoreContract.submitOriginScore(groupId2, 0, scores2);

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
        scoreContract.submitOriginScore(groupId1, 0, scores);

        // New owner can submit
        vm.prank(groupOwner2);
        scoreContract.submitOriginScore(groupId1, 0, scores);

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
        scoreContract.submitOriginScore(groupId1, 0, scores);

        vm.prank(groupOwner2);
        scoreContract.submitOriginScore(groupId2, 0, scores);

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
        scoreContract.submitOriginScore(groupId1, 0, scores);

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
        scoreContract.submitOriginScore(groupId1, 0, scores);
        scoreContract.submitOriginScore(groupId3, 0, scores);
        vm.stopPrank();

        uint256[] memory groupIds = scoreContract.groupIdsByVerifier(
            round,
            groupOwner1
        );
        assertEq(groupIds.length, 2);
        assertEq(scoreContract.groupIdsByVerifierCount(round, groupOwner1), 2);
    }

    // ============ Event Tests ============

    function test_SubmitOriginScore_EmitsEvent() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        // Setup actionIds for this round
        uint256 round = verify.currentRound();
        vote.setVotedActionIds(address(token), round, ACTION_ID);

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.expectEmit(true, true, true, true);
        emit ScoreSubmit(
            address(token),
            round,
            ACTION_ID,
            groupId1,
            0,
            1,
            true
        );

        vm.prank(groupOwner1);
        scoreContract.submitOriginScore(groupId1, 0, scores);
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

    function test_SubmitOriginScore_BatchSubmission() public {
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
        scoreContract.submitOriginScore(groupId1, 0, scores1);
        assertEq(scoreContract.submittedCount(round, groupId1), 1);

        // Second batch
        scoreContract.submitOriginScore(groupId1, 1, scores2);
        assertEq(scoreContract.submittedCount(round, groupId1), 2);

        // Third batch - should auto-finalize
        scoreContract.submitOriginScore(groupId1, 2, scores3);
        assertEq(scoreContract.submittedCount(round, groupId1), 3);

        vm.stopPrank();

        // Verify scores
        assertEq(scoreContract.originScoreByAccount(round, user1), 80);
        assertEq(scoreContract.originScoreByAccount(round, user2), 90);
        assertEq(scoreContract.originScoreByAccount(round, user3), 100);

        // Verify finalization happened
        assertEq(scoreContract.verifierByGroupId(round, groupId1), groupOwner1);
        assertEq(scoreContract.scoreByGroupId(round, groupId1), joinAmount * 3);
    }

    function test_SubmitOriginScore_RevertInvalidStartIndex() public {
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
        scoreContract.submitOriginScore(groupId1, 1, scores); // Should start at 0
    }

    function test_SubmitOriginScore_RevertScoresExceedAccountCount() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        uint256[] memory scores = new uint256[](2);
        scores[0] = 80;
        scores[1] = 90;

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupScore.ScoresExceedAccountCount.selector);
        scoreContract.submitOriginScore(groupId1, 0, scores);
    }

    function test_SubmitOriginScore_RevertAfterComplete() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.startPrank(groupOwner1);
        scoreContract.submitOriginScore(groupId1, 0, scores);

        // After complete submission, _scoreSubmitted is true
        vm.expectRevert(IGroupScore.VerificationAlreadySubmitted.selector);
        scoreContract.submitOriginScore(groupId1, 0, scores);
        vm.stopPrank();
    }

    function test_SubmitOriginScore_RevertFullAfterBatchStarted() public {
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
        scoreContract.submitOriginScore(groupId1, 0, scores1);

        // Trying to submit all from start fails (startIndex mismatch)
        vm.expectRevert(IGroupScore.InvalidStartIndex.selector);
        scoreContract.submitOriginScore(groupId1, 0, scoresAll);
        vm.stopPrank();
    }

    function test_SubmitOriginScore_EmitsEventWithDetails() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        uint256 round = verify.currentRound();
        vote.setVotedActionIds(address(token), round, ACTION_ID);

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.expectEmit(true, true, true, true);
        emit ScoreSubmit(
            address(token),
            round,
            ACTION_ID,
            groupId1,
            0,
            1,
            true
        );

        vm.prank(groupOwner1);
        scoreContract.submitOriginScore(groupId1, 0, scores);
    }
}
