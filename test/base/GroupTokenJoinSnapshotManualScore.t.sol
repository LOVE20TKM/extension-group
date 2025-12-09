// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "../utils/BaseGroupTest.sol";
import {
    GroupTokenJoinSnapshotManualScore
} from "../../src/base/GroupTokenJoinSnapshotManualScore.sol";
import {
    GroupTokenJoinSnapshot
} from "../../src/base/GroupTokenJoinSnapshot.sol";
import {GroupTokenJoin} from "../../src/base/GroupTokenJoin.sol";
import {GroupCore} from "../../src/base/GroupCore.sol";
import {
    IGroupScore,
    MAX_ORIGIN_SCORE
} from "../../src/interface/base/IGroupScore.sol";
import {ILOVE20GroupManager} from "../../src/interface/ILOVE20GroupManager.sol";
import {ExtensionAccounts} from "@extension/src/base/ExtensionAccounts.sol";

/**
 * @title MockGroupManualScore
 * @notice Concrete implementation for testing
 */
contract MockGroupManualScore is
    GroupTokenJoinSnapshotManualScore,
    ExtensionAccounts
{
    constructor(
        address factory_,
        address tokenAddress_,
        address groupManagerAddress_,
        address stakeTokenAddress_,
        uint256 minGovVoteRatioBps_,
        uint256 capacityMultiplier_,
        uint256 stakingMultiplier_,
        uint256 maxJoinAmountMultiplier_,
        uint256 minJoinAmount_
    )
        GroupCore(
            factory_,
            tokenAddress_,
            groupManagerAddress_,
            stakeTokenAddress_,
            minGovVoteRatioBps_,
            capacityMultiplier_,
            stakingMultiplier_,
            maxJoinAmountMultiplier_,
            minJoinAmount_
        )
        GroupTokenJoin(tokenAddress_)
    {}

    function _addAccount(
        address account
    ) internal override(ExtensionAccounts, GroupTokenJoin) {
        ExtensionAccounts._addAccount(account);
    }

    function _removeAccount(
        address account
    ) internal override(ExtensionAccounts, GroupTokenJoin) {
        ExtensionAccounts._removeAccount(account);
    }

    function isJoinedValueCalculated() external pure returns (bool) {
        return false;
    }

    function joinedValue() external view returns (uint256) {
        return totalJoinedAmount();
    }

    function joinedValueByAccount(
        address account
    ) external view returns (uint256) {
        return _joinInfo[account].amount;
    }

    function _calculateReward(
        uint256,
        address
    ) internal pure override returns (uint256) {
        return 0;
    }

    // Expose for testing
    function triggerSnapshot(uint256 groupId) external {
        _snapshotIfNeeded(groupId);
    }
}

/**
 * @title GroupTokenJoinSnapshotManualScoreTest
 * @notice Test suite for GroupTokenJoinSnapshotManualScore
 */
contract GroupTokenJoinSnapshotManualScoreTest is BaseGroupTest {
    MockGroupManualScore public scoreContract;

    uint256 public groupId1;
    uint256 public groupId2;

    // Re-declare events for testing (must match interface definition exactly)
    event ScoreSubmit(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        uint256 groupId
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
            MIN_GOV_VOTE_RATIO_BPS,
            CAPACITY_MULTIPLIER,
            STAKING_MULTIPLIER,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            MIN_JOIN_AMOUNT
        );

        registerFactory(address(token), address(mockFactory));
        token.mint(address(this), 1e18);
        token.approve(address(mockFactory), type(uint256).max);
        mockFactory.registerExtension(address(scoreContract), address(token));

        groupId1 = setupGroupOwner(groupOwner1, 10000e18, "TestGroup1");
        groupId2 = setupGroupOwner(groupOwner2, 10000e18, "TestGroup2");

        prepareExtensionInit(address(scoreContract), address(token), ACTION_ID);

        uint256 stakeAmount = 10000e18;
        setupUser(groupOwner1, stakeAmount, address(groupManager));
        setupUser(groupOwner2, stakeAmount, address(groupManager));

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID,
            groupId1,
            "Group1",
            stakeAmount,
            MIN_JOIN_AMOUNT,
            0
        );

        vm.prank(groupOwner2, groupOwner2);
        groupManager.activateGroup(
            address(token),
            ACTION_ID,
            groupId2,
            "Group2",
            stakeAmount,
            MIN_JOIN_AMOUNT,
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

    function test_SetGroupDelegatedVerifier_RevertNotActive() public {
        advanceRound();

        vm.prank(groupOwner1, groupOwner1);
        groupManager.deactivateGroup(address(token), ACTION_ID, groupId1);

        vm.prank(groupOwner1);
        vm.expectRevert();
        scoreContract.setGroupDelegatedVerifier(groupId1, address(0x123));
    }

    // ============ submitOriginScore Tests ============

    function test_SubmitOriginScore_ByOwner() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        // Advance round and trigger fresh snapshot that captures user1
        advanceRound();
        uint256 round = verify.currentRound();
        scoreContract.triggerSnapshot(groupId1);

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80; // 80%

        vm.prank(groupOwner1);
        scoreContract.submitOriginScore(groupId1, scores);

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

        // Advance round and trigger fresh snapshot
        advanceRound();
        uint256 round = verify.currentRound();
        scoreContract.triggerSnapshot(groupId1);

        uint256[] memory scores = new uint256[](1);
        scores[0] = 90;

        vm.prank(delegatedVerifier);
        scoreContract.submitOriginScore(groupId1, scores);

        assertEq(scoreContract.originScoreByAccount(round, user1), 90);
    }

    function test_SubmitOriginScore_RevertNotVerifier() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        // Advance round and trigger fresh snapshot
        advanceRound();
        scoreContract.triggerSnapshot(groupId1);

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.prank(user2);
        vm.expectRevert(IGroupScore.NotVerifier.selector);
        scoreContract.submitOriginScore(groupId1, scores);
    }

    function test_SubmitOriginScore_RevertAlreadySubmitted() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        // Advance round and trigger fresh snapshot
        advanceRound();
        scoreContract.triggerSnapshot(groupId1);

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.startPrank(groupOwner1);
        scoreContract.submitOriginScore(groupId1, scores);

        vm.expectRevert(IGroupScore.VerificationAlreadySubmitted.selector);
        scoreContract.submitOriginScore(groupId1, scores);
        vm.stopPrank();
    }

    function test_SubmitOriginScore_RevertNoSnapshot() public {
        // Advance round to allow deactivation
        advanceRound();

        // Deactivate group so _snapshotIfNeeded won't create snapshot
        vm.prank(groupOwner1, groupOwner1);
        groupManager.deactivateGroup(address(token), ACTION_ID, groupId1);

        // Advance again so we're in a fresh round where group was never active
        advanceRound();

        uint256[] memory scores = new uint256[](0);

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupScore.NoSnapshotForRound.selector);
        scoreContract.submitOriginScore(groupId1, scores);
    }

    function test_SubmitOriginScore_RevertScoresCountMismatch() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        // Advance round and trigger fresh snapshot
        advanceRound();

        scoreContract.triggerSnapshot(groupId1);

        // 2 scores for 1 account
        uint256[] memory scores = new uint256[](2);
        scores[0] = 80;
        scores[1] = 90;

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupScore.ScoresCountMismatch.selector);
        scoreContract.submitOriginScore(groupId1, scores);
    }

    function test_SubmitOriginScore_RevertScoreExceedsMax() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        // Advance round and trigger fresh snapshot
        advanceRound();
        scoreContract.triggerSnapshot(groupId1);

        uint256[] memory scores = new uint256[](1);
        scores[0] = MAX_ORIGIN_SCORE + 1; // Exceeds max

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupScore.ScoreExceedsMax.selector);
        scoreContract.submitOriginScore(groupId1, scores);
    }

    // ============ Score Calculation Tests ============

    function test_ScoreByAccount() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        // Advance round and trigger fresh snapshot
        advanceRound();
        uint256 round = verify.currentRound();
        scoreContract.triggerSnapshot(groupId1);

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.prank(groupOwner1);
        scoreContract.submitOriginScore(groupId1, scores);

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

        // Advance round and trigger fresh snapshot
        advanceRound();
        uint256 round = verify.currentRound();
        scoreContract.triggerSnapshot(groupId1);

        uint256[] memory scores = new uint256[](2);
        scores[0] = 80;
        scores[1] = 90;

        vm.prank(groupOwner1);
        scoreContract.submitOriginScore(groupId1, scores);

        // Group score = snapshot amount (without distrust applied)
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

        // Advance round and trigger fresh snapshots
        advanceRound();
        uint256 round = verify.currentRound();
        scoreContract.triggerSnapshot(groupId1);
        scoreContract.triggerSnapshot(groupId2);

        uint256[] memory scores1 = new uint256[](1);
        scores1[0] = 80;

        uint256[] memory scores2 = new uint256[](1);
        scores2[0] = 90;

        vm.prank(groupOwner1);
        scoreContract.submitOriginScore(groupId1, scores1);

        vm.prank(groupOwner2);
        scoreContract.submitOriginScore(groupId2, scores2);

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

    // ============ Verifier Tracking Tests ============

    function test_Verifiers() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));
        setupUser(user2, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        vm.prank(user2);
        scoreContract.join(groupId2, joinAmount, new string[](0));

        // Advance round and trigger fresh snapshots
        advanceRound();
        scoreContract.triggerSnapshot(groupId1);
        scoreContract.triggerSnapshot(groupId2);

        uint256 round = verify.currentRound();

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.prank(groupOwner1);
        scoreContract.submitOriginScore(groupId1, scores);

        vm.prank(groupOwner2);
        scoreContract.submitOriginScore(groupId2, scores);

        address[] memory verifiers = scoreContract.verifiers(round);
        assertEq(verifiers.length, 2);
        assertEq(scoreContract.verifiersCount(round), 2);
    }

    function test_VerifierByGroupId() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        // Advance round and trigger fresh snapshot
        advanceRound();
        scoreContract.triggerSnapshot(groupId1);

        uint256 round = verify.currentRound();

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.prank(groupOwner1);
        scoreContract.submitOriginScore(groupId1, scores);

        assertEq(scoreContract.verifierByGroupId(round, groupId1), groupOwner1);
    }

    function test_GroupIdsByVerifier() public {
        // Mint another group for owner1 - need more govVotes for multiple groups
        stake.setValidGovVotes(address(token), groupOwner1, 30000e18);
        uint256 groupId3 = group.mint(groupOwner1, "TestGroup3");

        uint256 stakeAmount = 10000e18;
        setupUser(groupOwner1, stakeAmount, address(groupManager));

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID,
            groupId3,
            "Group3",
            stakeAmount,
            MIN_JOIN_AMOUNT,
            0
        );

        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(scoreContract));
        setupUser(user2, joinAmount, address(scoreContract));

        vm.prank(user1);
        scoreContract.join(groupId1, joinAmount, new string[](0));

        vm.prank(user2);
        scoreContract.join(groupId3, joinAmount, new string[](0));

        // Advance round and trigger fresh snapshots
        advanceRound();
        scoreContract.triggerSnapshot(groupId1);
        scoreContract.triggerSnapshot(groupId3);

        uint256 round = verify.currentRound();

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.startPrank(groupOwner1);
        scoreContract.submitOriginScore(groupId1, scores);
        scoreContract.submitOriginScore(groupId3, scores);
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

        // Advance round and setup actionIds for new round
        advanceRound();
        vote.setVotedActionIds(
            address(token),
            verify.currentRound(),
            ACTION_ID
        );
        uint256 round = verify.currentRound();
        scoreContract.triggerSnapshot(groupId1);

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.expectEmit(true, true, true, true);
        emit ScoreSubmit(address(token), round, ACTION_ID, groupId1);

        vm.prank(groupOwner1);
        scoreContract.submitOriginScore(groupId1, scores);
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
}
