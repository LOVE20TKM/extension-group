// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "../utils/BaseGroupTest.sol";
import {GroupTokenJoinSnapshotManualScoreDistrust} from "../../src/base/GroupTokenJoinSnapshotManualScoreDistrust.sol";
import {GroupTokenJoinSnapshotManualScore} from "../../src/base/GroupTokenJoinSnapshotManualScore.sol";
import {GroupTokenJoinSnapshot} from "../../src/base/GroupTokenJoinSnapshot.sol";
import {GroupTokenJoin} from "../../src/base/GroupTokenJoin.sol";
import {GroupCore} from "../../src/base/GroupCore.sol";
import {IGroupDistrust} from "../../src/interface/base/IGroupDistrust.sol";
import {ExtensionAccounts} from "@extension/src/base/ExtensionAccounts.sol";

/**
 * @title MockGroupDistrust
 * @notice Concrete implementation for testing
 */
contract MockGroupDistrust is GroupTokenJoinSnapshotManualScoreDistrust, ExtensionAccounts {
    constructor(
        address factory_,
        address tokenAddress_,
        address groupAddress_,
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
            groupAddress_,
            stakeTokenAddress_,
            minGovVoteRatioBps_,
            capacityMultiplier_,
            stakingMultiplier_,
            maxJoinAmountMultiplier_,
            minJoinAmount_
        )
        GroupTokenJoin(tokenAddress_)
    {}

    function _addAccount(address account) internal override(ExtensionAccounts, GroupTokenJoin) {
        ExtensionAccounts._addAccount(account);
    }

    function _removeAccount(address account) internal override(ExtensionAccounts, GroupTokenJoin) {
        ExtensionAccounts._removeAccount(account);
    }

    function isJoinedValueCalculated() external pure returns (bool) {
        return false;
    }

    function joinedValue() external view returns (uint256) {
        return totalJoinedAmount();
    }

    function joinedValueByAccount(address account) external view returns (uint256) {
        return _joinInfo[account].amount;
    }

    function _calculateReward(uint256, address) internal pure override returns (uint256) {
        return 0;
    }

    // Expose for testing
    function triggerSnapshot(uint256 groupId) external {
        _snapshotIfNeeded(groupId);
    }
}

/**
 * @title GroupTokenJoinSnapshotManualScoreDistrustTest
 * @notice Test suite for GroupTokenJoinSnapshotManualScoreDistrust
 */
contract GroupTokenJoinSnapshotManualScoreDistrustTest is BaseGroupTest {
    MockGroupDistrust public distrustContract;

    uint256 public groupId1;
    uint256 public groupId2;

    address public governor1 = address(0x30);
    address public governor2 = address(0x40);

    // Re-declare event for testing (must match interface definition exactly)
    event DistrustVote(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        address groupOwner,
        address voter,
        uint256 amount,
        string reason
    );

    function setUp() public {
        setUpBase();

        distrustContract = new MockGroupDistrust(
            address(mockFactory),
            address(token),
            address(group),
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
        mockFactory.registerExtension(address(distrustContract), address(token));

        groupId1 = setupGroupOwner(groupOwner1, 10000e18, "TestGroup1");
        groupId2 = setupGroupOwner(groupOwner2, 10000e18, "TestGroup2");

        prepareExtensionInit(address(distrustContract), address(token), ACTION_ID);

        uint256 stakeAmount = 10000e18;
        setupUser(groupOwner1, stakeAmount, address(distrustContract));
        setupUser(groupOwner2, stakeAmount, address(distrustContract));

        vm.prank(groupOwner1);
        distrustContract.activateGroup(groupId1, "Group1", stakeAmount, MIN_JOIN_AMOUNT, 0);

        vm.prank(groupOwner2);
        distrustContract.activateGroup(groupId2, "Group2", stakeAmount, MIN_JOIN_AMOUNT, 0);
    }

    /**
     * @notice Setup governor with verify votes
     */
    function setupGovernor(address governor, uint256 voteAmount) internal {
        setupVerifyVotes(governor, ACTION_ID, address(distrustContract), voteAmount);
    }

    /**
     * @notice Helper to submit scores for a group
     * @dev Advances round and triggers fresh snapshot to capture current members
     */
    function submitScores(uint256 groupId, address owner, uint256 numAccounts) internal {
        // Advance round to get fresh snapshot that captures current members
        advanceRound();
        // Setup actionIds for new round
        vote.setVotedActionIds(address(token), verify.currentRound(), ACTION_ID);
        distrustContract.triggerSnapshot(groupId);

        uint256[] memory scores = new uint256[](numAccounts);
        for (uint256 i = 0; i < numAccounts; i++) {
            scores[i] = 80;
        }

        vm.prank(owner);
        distrustContract.submitOriginScore(groupId, scores);
    }

    // ============ distrustVote Tests ============

    function test_DistrustVote_Success() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(distrustContract));

        vm.prank(user1);
        distrustContract.join(groupId1, joinAmount);

        // Submit scores first
        submitScores(groupId1, groupOwner1, 1);

        // Setup governor
        uint256 voteAmount = 100e18;
        setupGovernor(governor1, voteAmount);

        uint256 distrustAmount = 50e18;
        uint256 round = verify.currentRound();

        vm.prank(governor1);
        distrustContract.distrustVote(groupOwner1, distrustAmount, "Bad behavior");

        assertEq(distrustContract.distrustVotesByGroupOwner(round, groupOwner1), distrustAmount);
        assertEq(distrustContract.distrustVotesByVoterByGroupOwner(round, governor1, groupOwner1), distrustAmount);
        assertEq(distrustContract.distrustReason(round, governor1, groupOwner1), "Bad behavior");
    }

    function test_DistrustVote_AccumulateVotes() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(distrustContract));

        vm.prank(user1);
        distrustContract.join(groupId1, joinAmount);

        submitScores(groupId1, groupOwner1, 1);

        uint256 voteAmount = 100e18;
        setupGovernor(governor1, voteAmount);

        uint256 round = verify.currentRound();

        vm.startPrank(governor1);
        distrustContract.distrustVote(groupOwner1, 30e18, "First reason");
        distrustContract.distrustVote(groupOwner1, 20e18, "Second reason");
        vm.stopPrank();

        assertEq(distrustContract.distrustVotesByGroupOwner(round, groupOwner1), 50e18);
        assertEq(distrustContract.distrustVotesByVoterByGroupOwner(round, governor1, groupOwner1), 50e18);
    }

    function test_DistrustVote_MultipleGovernors() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(distrustContract));

        vm.prank(user1);
        distrustContract.join(groupId1, joinAmount);

        submitScores(groupId1, groupOwner1, 1);

        setupGovernor(governor1, 100e18);
        setupGovernor(governor2, 100e18);

        uint256 round = verify.currentRound();

        vm.prank(governor1);
        distrustContract.distrustVote(groupOwner1, 30e18, "Reason 1");

        vm.prank(governor2);
        distrustContract.distrustVote(groupOwner1, 40e18, "Reason 2");

        assertEq(distrustContract.distrustVotesByGroupOwner(round, groupOwner1), 70e18);
    }

    function test_DistrustVote_RevertNotGovernor() public {
        vm.prank(user1);
        vm.expectRevert(IGroupDistrust.NotGovernor.selector);
        distrustContract.distrustVote(groupOwner1, 10e18, "Reason");
    }

    function test_DistrustVote_RevertExceedsLimit() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(distrustContract));

        vm.prank(user1);
        distrustContract.join(groupId1, joinAmount);

        submitScores(groupId1, groupOwner1, 1);

        uint256 voteAmount = 100e18;
        setupGovernor(governor1, voteAmount);

        vm.prank(governor1);
        vm.expectRevert(IGroupDistrust.DistrustVoteExceedsLimit.selector);
        distrustContract.distrustVote(groupOwner1, voteAmount + 1, "Reason");
    }

    function test_DistrustVote_RevertInvalidReason() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(distrustContract));

        vm.prank(user1);
        distrustContract.join(groupId1, joinAmount);

        submitScores(groupId1, groupOwner1, 1);

        setupGovernor(governor1, 100e18);

        vm.prank(governor1);
        vm.expectRevert(IGroupDistrust.InvalidReason.selector);
        distrustContract.distrustVote(groupOwner1, 10e18, "");
    }

    // ============ Score Adjustment Tests ============

    function test_DistrustVote_AdjustsGroupScore() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(distrustContract));

        vm.prank(user1);
        distrustContract.join(groupId1, joinAmount);

        submitScores(groupId1, groupOwner1, 1);

        uint256 round = verify.currentRound();

        // Initial group score = joinAmount
        uint256 initialScore = distrustContract.scoreByGroupId(round, groupId1);
        assertEq(initialScore, joinAmount);

        // Setup governor and cast distrust vote
        uint256 totalVerifyVotes = 100e18;
        setupGovernor(governor1, totalVerifyVotes);

        uint256 distrustAmount = 50e18; // 50% distrust

        vm.prank(governor1);
        distrustContract.distrustVote(groupOwner1, distrustAmount, "Bad");

        // New score = groupAmount * (total - distrust) / total
        // = joinAmount * (100e18 - 50e18) / 100e18 = joinAmount * 0.5
        uint256 newScore = distrustContract.scoreByGroupId(round, groupId1);
        uint256 expectedScore = (joinAmount * (totalVerifyVotes - distrustAmount)) / totalVerifyVotes;
        assertEq(newScore, expectedScore);
    }

    function test_DistrustVote_AdjustsTotalScore() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(distrustContract));

        vm.prank(user1);
        distrustContract.join(groupId1, joinAmount);

        submitScores(groupId1, groupOwner1, 1);

        uint256 round = verify.currentRound();
        uint256 initialTotalScore = distrustContract.score(round);

        uint256 totalVerifyVotes = 100e18;
        setupGovernor(governor1, totalVerifyVotes);

        vm.prank(governor1);
        distrustContract.distrustVote(groupOwner1, 50e18, "Bad");

        uint256 newTotalScore = distrustContract.score(round);
        assertTrue(newTotalScore < initialTotalScore);
    }

    function test_DistrustVote_AffectsAllOwnerGroups() public {
        // Create another group for owner1
        uint256 groupId3 = group.mint(groupOwner1, "TestGroup3");

        // Increase governance votes to allow multiple groups
        stake.setValidGovVotes(address(token), groupOwner1, 30000e18);

        uint256 stakeAmount = 5000e18;
        setupUser(groupOwner1, stakeAmount, address(distrustContract));

        vm.prank(groupOwner1);
        distrustContract.activateGroup(groupId3, "Group3", stakeAmount, MIN_JOIN_AMOUNT, 0);

        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(distrustContract));
        setupUser(user2, joinAmount, address(distrustContract));

        vm.prank(user1);
        distrustContract.join(groupId1, joinAmount);

        vm.prank(user2);
        distrustContract.join(groupId3, joinAmount);

        // Submit scores for both groups
        submitScores(groupId1, groupOwner1, 1);

        distrustContract.triggerSnapshot(groupId3);
        uint256[] memory scores3 = new uint256[](1);
        scores3[0] = 80;
        vm.prank(groupOwner1);
        distrustContract.submitOriginScore(groupId3, scores3);

        uint256 round = verify.currentRound();

        uint256 initialScore1 = distrustContract.scoreByGroupId(round, groupId1);
        uint256 initialScore3 = distrustContract.scoreByGroupId(round, groupId3);

        uint256 totalVerifyVotes = 100e18;
        setupGovernor(governor1, totalVerifyVotes);

        vm.prank(governor1);
        distrustContract.distrustVote(groupOwner1, 50e18, "Bad");

        // Both groups should be affected
        uint256 newScore1 = distrustContract.scoreByGroupId(round, groupId1);
        uint256 newScore3 = distrustContract.scoreByGroupId(round, groupId3);

        assertTrue(newScore1 < initialScore1);
        assertTrue(newScore3 < initialScore3);
    }

    // ============ View Functions Tests ============

    function test_DistrustVotesByGroupId() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(distrustContract));

        vm.prank(user1);
        distrustContract.join(groupId1, joinAmount);

        submitScores(groupId1, groupOwner1, 1);

        setupGovernor(governor1, 100e18);

        vm.prank(governor1);
        distrustContract.distrustVote(groupOwner1, 30e18, "Bad");

        uint256 round = verify.currentRound();
        assertEq(distrustContract.distrustVotesByGroupId(round, groupId1), 30e18);
    }

    function test_TotalVerifyVotes() public {
        // First, need to initialize the contract by having someone join
        // This triggers _autoInitialize which sets actionId
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(distrustContract));

        vm.prank(user1);
        distrustContract.join(groupId1, joinAmount);

        setupGovernor(governor1, 100e18);
        setupGovernor(governor2, 50e18);

        uint256 round = verify.currentRound();
        assertEq(distrustContract.totalVerifyVotes(round), 150e18);
    }

    // ============ Event Tests ============

    function test_DistrustVote_EmitsEvent() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(distrustContract));

        vm.prank(user1);
        distrustContract.join(groupId1, joinAmount);

        submitScores(groupId1, groupOwner1, 1);

        setupGovernor(governor1, 100e18);

        uint256 round = verify.currentRound();
        uint256 distrustAmount = 30e18;
        string memory reason = "Bad behavior";

        vm.expectEmit(true, true, true, true);
        emit DistrustVote(
            address(token),
            round,
            ACTION_ID,
            groupOwner1,
            governor1,
            distrustAmount,
            reason
        );

        vm.prank(governor1);
        distrustContract.distrustVote(groupOwner1, distrustAmount, reason);
    }

    // ============ Edge Cases ============

    function test_DistrustVote_ZeroTotalVerifyVotes() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(distrustContract));

        vm.prank(user1);
        distrustContract.join(groupId1, joinAmount);

        submitScores(groupId1, groupOwner1, 1);

        uint256 round = verify.currentRound();

        // Without any verify votes, group score should be groupAmount
        uint256 score = distrustContract.scoreByGroupId(round, groupId1);
        assertEq(score, joinAmount);
    }

    function test_DistrustVote_FullDistrust() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(distrustContract));

        vm.prank(user1);
        distrustContract.join(groupId1, joinAmount);

        submitScores(groupId1, groupOwner1, 1);

        uint256 totalVerifyVotes = 100e18;
        setupGovernor(governor1, totalVerifyVotes);

        // 100% distrust
        vm.prank(governor1);
        distrustContract.distrustVote(groupOwner1, totalVerifyVotes, "Total distrust");

        uint256 round = verify.currentRound();
        uint256 newScore = distrustContract.scoreByGroupId(round, groupId1);
        assertEq(newScore, 0);
    }
}

