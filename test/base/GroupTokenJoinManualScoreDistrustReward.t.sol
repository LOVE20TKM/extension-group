// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "../utils/BaseGroupTest.sol";
import {
    GroupTokenJoinManualScoreDistrustReward
} from "../../src/base/GroupTokenJoinManualScoreDistrustReward.sol";
import {
    GroupTokenJoinManualScoreDistrust
} from "../../src/base/GroupTokenJoinManualScoreDistrust.sol";
import {
    GroupTokenJoinManualScore
} from "../../src/base/GroupTokenJoinManualScore.sol";
import {GroupTokenJoin} from "../../src/base/GroupTokenJoin.sol";
import {GroupCore} from "../../src/base/GroupCore.sol";
import {LOVE20GroupDistrust} from "../../src/LOVE20GroupDistrust.sol";
import {IGroupReward} from "../../src/interface/base/IGroupReward.sol";
import {
    IExtensionReward
} from "@extension/src/interface/base/IExtensionReward.sol";
import {ILOVE20GroupManager} from "../../src/interface/ILOVE20GroupManager.sol";

/**
 * @title MockGroupReward
 * @notice Concrete implementation for testing
 */
contract MockGroupReward is GroupTokenJoinManualScoreDistrustReward {
    constructor(
        address factory_,
        address tokenAddress_,
        address groupManagerAddress_,
        address groupDistrustAddress_,
        address stakeTokenAddress_,
        uint256 groupActivationStakeAmount_,
        uint256 maxJoinAmountMultiplier_,
        uint256 verifyCapacityMultiplier_
    )
        GroupTokenJoinManualScoreDistrustReward(groupDistrustAddress_)
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

    // Set reward for testing
    function setReward(uint256 round, uint256 amount) external {
        _reward[round] = amount;
    }

    // Expose for testing
    function calculateRewardByAccount(
        uint256 round,
        address account
    ) external view returns (uint256) {
        return _calculateReward(round, account);
    }
}

/**
 * @title GroupTokenJoinManualScoreDistrustRewardTest
 * @notice Test suite for GroupTokenJoinManualScoreDistrustReward
 */
contract GroupTokenJoinManualScoreDistrustRewardTest is BaseGroupTest {
    MockGroupReward public rewardContract;
    LOVE20GroupDistrust public groupDistrust;

    uint256 public groupId1;
    uint256 public groupId2;

    // Re-declare event for testing
    event UnclaimedRewardBurn(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        uint256 amount
    );

    function setUp() public {
        setUpBase();

        // Deploy GroupDistrust singleton
        groupDistrust = new LOVE20GroupDistrust(
            address(center),
            address(verify),
            address(group)
        );

        rewardContract = new MockGroupReward(
            address(mockFactory),
            address(token),
            address(groupManager),
            address(groupDistrust),
            address(token),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            CAPACITY_FACTOR
        );

        token.mint(address(this), 1e18);
        token.approve(address(mockFactory), type(uint256).max);
        mockFactory.registerExtension(address(rewardContract), address(token));

        groupId1 = setupGroupOwner(groupOwner1, 10000e18, "TestGroup1");
        groupId2 = setupGroupOwner(groupOwner2, 10000e18, "TestGroup2");

        prepareExtensionInit(
            address(rewardContract),
            address(token),
            ACTION_ID
        );

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

    /**
     * @notice Helper to setup group with members and scores
     */
    function setupGroupWithScores(
        uint256 groupId,
        address owner,
        address[] memory members,
        uint256[] memory amounts,
        uint256[] memory scores
    ) internal {
        for (uint256 i = 0; i < members.length; i++) {
            setupUser(members[i], amounts[i], address(rewardContract));
            vm.prank(members[i]);
            rewardContract.join(groupId, amounts[i], new string[](0));
        }

        vm.prank(owner);
        rewardContract.submitOriginScore(groupId, 0, scores);
    }

    // ============ generatedRewardByGroupId Tests ============

    function test_RewardByGroupId_SingleGroup() public {
        address[] memory members = new address[](1);
        members[0] = user1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10e18;
        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        setupGroupWithScores(groupId1, groupOwner1, members, amounts, scores);

        uint256 round = verify.currentRound();
        uint256 totalReward = 1000e18;
        rewardContract.setReward(round, totalReward);

        // Only one group, so it gets all reward
        uint256 groupReward = rewardContract.generatedRewardByGroupId(
            round,
            groupId1
        );
        assertEq(groupReward, totalReward);
    }

    function test_RewardByGroupId_MultipleGroups() public {
        // Setup both groups with members first
        uint256 amount1 = 10e18;
        uint256 amount2 = 20e18;
        setupUser(user1, amount1, address(rewardContract));
        setupUser(user2, amount2, address(rewardContract));

        vm.prank(user1);
        rewardContract.join(groupId1, amount1, new string[](0));

        vm.prank(user2);
        rewardContract.join(groupId2, amount2, new string[](0));

        uint256[] memory scores1 = new uint256[](1);
        scores1[0] = 80;
        vm.prank(groupOwner1);
        rewardContract.submitOriginScore(groupId1, 0, scores1);

        uint256[] memory scores2 = new uint256[](1);
        scores2[0] = 80;
        vm.prank(groupOwner2);
        rewardContract.submitOriginScore(groupId2, 0, scores2);

        uint256 round = verify.currentRound();
        uint256 totalReward = 1000e18;
        rewardContract.setReward(round, totalReward);

        // Group1 gets 10/30 = 1/3 of reward
        uint256 group1Reward = rewardContract.generatedRewardByGroupId(
            round,
            groupId1
        );
        // Group2 gets 20/30 = 2/3 of reward
        uint256 group2Reward = rewardContract.generatedRewardByGroupId(
            round,
            groupId2
        );

        // Allow for rounding errors (within 1 wei)
        assertApproxEqAbs(group1Reward + group2Reward, totalReward, 1);
        assertApproxEqAbs(group2Reward, group1Reward * 2, 1);
    }

    function test_RewardByGroupId_ZeroReward() public {
        address[] memory members = new address[](1);
        members[0] = user1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10e18;
        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        setupGroupWithScores(groupId1, groupOwner1, members, amounts, scores);

        uint256 round = verify.currentRound();
        // No reward set

        assertEq(rewardContract.generatedRewardByGroupId(round, groupId1), 0);
    }

    // ============ generatedRewardByVerifier Tests ============

    function test_RewardByVerifier_SingleGroup() public {
        address[] memory members = new address[](1);
        members[0] = user1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10e18;
        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        setupGroupWithScores(groupId1, groupOwner1, members, amounts, scores);

        uint256 round = verify.currentRound();
        uint256 totalReward = 1000e18;
        rewardContract.setReward(round, totalReward);

        uint256 verifierReward = rewardContract.generatedRewardByVerifier(
            round,
            groupOwner1
        );
        assertEq(verifierReward, totalReward);
    }

    function test_RewardByVerifier_MultipleGroups() public {
        // Create another group for owner1
        uint256 groupId3 = group.mint(groupOwner1, "TestGroup3");

        // Increase governance votes to allow multiple groups
        stake.setValidGovVotes(address(token), groupOwner1, 30000e18);

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

        // Setup group1
        address[] memory members1 = new address[](1);
        members1[0] = user1;
        uint256[] memory amounts1 = new uint256[](1);
        amounts1[0] = 10e18;
        uint256[] memory scores1 = new uint256[](1);
        scores1[0] = 80;

        setupGroupWithScores(
            groupId1,
            groupOwner1,
            members1,
            amounts1,
            scores1
        );

        // Setup group3
        address[] memory members3 = new address[](1);
        members3[0] = user2;
        uint256[] memory amounts3 = new uint256[](1);
        amounts3[0] = 10e18;
        uint256[] memory scores3 = new uint256[](1);
        scores3[0] = 80;

        setupGroupWithScores(
            groupId3,
            groupOwner1,
            members3,
            amounts3,
            scores3
        );

        uint256 round = verify.currentRound();
        uint256 totalReward = 1000e18;
        rewardContract.setReward(round, totalReward);

        // Owner1 verified both groups
        uint256 verifierReward = rewardContract.generatedRewardByVerifier(
            round,
            groupOwner1
        );
        assertEq(verifierReward, totalReward);
    }

    // ============ Account Reward Calculation Tests ============

    function test_CalculateRewardByAccount() public {
        // Setup group with 2 members
        setupUser(user1, 10e18, address(rewardContract));
        setupUser(user2, 30e18, address(rewardContract));

        vm.prank(user1);
        rewardContract.join(groupId1, 10e18, new string[](0));

        vm.prank(user2);
        rewardContract.join(groupId1, 30e18, new string[](0));

        uint256[] memory scores = new uint256[](2);
        scores[0] = 100; // user1: score = 100 * 10e18 = 1000e18
        scores[1] = 50; // user2: score = 50 * 30e18 = 1500e18
        // Total score: 2500e18

        vm.prank(groupOwner1);
        rewardContract.submitOriginScore(groupId1, 0, scores);

        uint256 round = verify.currentRound();
        uint256 totalReward = 1000e18;
        rewardContract.setReward(round, totalReward);

        // user1 reward = totalReward * (1000e18 / 2500e18) = 400e18
        uint256 user1Reward = rewardContract.calculateRewardByAccount(
            round,
            user1
        );
        assertEq(user1Reward, 400e18);

        // user2 reward = totalReward * (1500e18 / 2500e18) = 600e18
        uint256 user2Reward = rewardContract.calculateRewardByAccount(
            round,
            user2
        );
        assertEq(user2Reward, 600e18);
    }

    function test_CalculateRewardByAccount_ZeroScore() public {
        setupUser(user1, 10e18, address(rewardContract));

        vm.prank(user1);
        rewardContract.join(groupId1, 10e18, new string[](0));

        uint256[] memory scores = new uint256[](1);
        scores[0] = 0; // Zero score

        vm.prank(groupOwner1);
        rewardContract.submitOriginScore(groupId1, 0, scores);

        uint256 round = verify.currentRound();
        uint256 totalReward = 1000e18;
        rewardContract.setReward(round, totalReward);

        assertEq(rewardContract.calculateRewardByAccount(round, user1), 0);
    }

    // ============ burnUnclaimedReward Tests ============

    function test_BurnUnclaimedReward_Success() public {
        uint256 round = verify.currentRound();
        uint256 rewardAmount = 1000e18;

        // Set reward and mint tokens to contract
        rewardContract.setReward(round, rewardAmount);
        token.mint(address(rewardContract), rewardAmount);

        // Advance round
        advanceRound();

        // Burn unclaimed reward (no verified groups in that round)
        uint256 supplyBefore = token.totalSupply();
        rewardContract.burnUnclaimedReward(round);
        uint256 supplyAfter = token.totalSupply();

        assertEq(supplyBefore - supplyAfter, rewardAmount);
    }

    function test_BurnUnclaimedReward_RevertRoundNotFinished() public {
        uint256 round = verify.currentRound();
        rewardContract.setReward(round, 1000e18);

        vm.expectRevert(IExtensionReward.RoundNotFinished.selector);
        rewardContract.burnUnclaimedReward(round);
    }

    function test_BurnUnclaimedReward_RevertHasVerifiedGroups() public {
        address[] memory members = new address[](1);
        members[0] = user1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10e18;
        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        setupGroupWithScores(groupId1, groupOwner1, members, amounts, scores);

        uint256 round = verify.currentRound();
        rewardContract.setReward(round, 1000e18);

        advanceRound();

        vm.expectRevert(IGroupReward.RoundHasVerifiedGroups.selector);
        rewardContract.burnUnclaimedReward(round);
    }

    function test_BurnUnclaimedReward_NoBurnIfAlreadyBurned() public {
        uint256 round = verify.currentRound();
        uint256 rewardAmount = 1000e18;

        rewardContract.setReward(round, rewardAmount);
        token.mint(address(rewardContract), rewardAmount);

        advanceRound();

        // First burn
        rewardContract.burnUnclaimedReward(round);

        uint256 supplyAfterFirst = token.totalSupply();

        // Second burn should not burn again
        rewardContract.burnUnclaimedReward(round);

        assertEq(token.totalSupply(), supplyAfterFirst);
    }

    // ============ Event Tests ============

    function test_BurnUnclaimedReward_EmitsEvent() public {
        // First initialize the contract by having someone join
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(rewardContract));

        vm.prank(user1);
        rewardContract.join(groupId1, joinAmount, new string[](0));

        // Now user exits to reset state
        vm.prank(user1);
        rewardContract.exit();

        uint256 round = verify.currentRound();
        uint256 rewardAmount = 1000e18;

        rewardContract.setReward(round, rewardAmount);
        token.mint(address(rewardContract), rewardAmount);

        advanceRound();

        vm.expectEmit(true, true, true, true);
        emit UnclaimedRewardBurn(
            address(token),
            round,
            ACTION_ID,
            rewardAmount
        );

        rewardContract.burnUnclaimedReward(round);
    }

    // ============ Integration Tests ============

    function test_RewardDistribution_WithDistrust() public {
        address governor = address(0x50);

        // Setup BOTH groups with members - distrust only affects relative distribution
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(rewardContract));
        setupUser(user2, joinAmount, address(rewardContract));

        vm.prank(user1);
        rewardContract.join(groupId1, joinAmount, new string[](0));

        vm.prank(user2);
        rewardContract.join(groupId2, joinAmount, new string[](0));

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;
        vm.prank(groupOwner1);
        rewardContract.submitOriginScore(groupId1, 0, scores);

        vm.prank(groupOwner2);
        rewardContract.submitOriginScore(groupId2, 0, scores);

        uint256 round = verify.currentRound();
        uint256 totalReward = 1000e18;
        rewardContract.setReward(round, totalReward);

        // Both groups should get equal reward before distrust (same amounts)
        uint256 reward1Before = rewardContract.generatedRewardByGroupId(
            round,
            groupId1
        );
        uint256 reward2Before = rewardContract.generatedRewardByGroupId(
            round,
            groupId2
        );
        assertEq(reward1Before, totalReward / 2);
        assertEq(reward2Before, totalReward / 2);

        // Apply distrust to group1 owner
        setupVerifyVotes(governor, ACTION_ID, address(rewardContract), 100e18);

        vm.prank(governor, governor);
        rewardContract.distrustVote(groupOwner1, 50e18, "Bad");

        // After distrust, group1 should get less, group2 should get more
        uint256 reward1After = rewardContract.generatedRewardByGroupId(
            round,
            groupId1
        );
        uint256 reward2After = rewardContract.generatedRewardByGroupId(
            round,
            groupId2
        );

        assertTrue(
            reward1After < reward1Before,
            "Group1 reward should decrease"
        );
        assertTrue(
            reward2After > reward2Before,
            "Group2 reward should increase"
        );
        assertApproxEqAbs(
            reward1After + reward2After,
            totalReward,
            1,
            "Total reward should be preserved"
        );
    }

    function test_RewardDistribution_MultipleGroupsWithDistrust() public {
        address governor = address(0x50);

        // Setup group1
        address[] memory members1 = new address[](1);
        members1[0] = user1;
        uint256[] memory amounts1 = new uint256[](1);
        amounts1[0] = 10e18;
        uint256[] memory scores1 = new uint256[](1);
        scores1[0] = 80;

        setupGroupWithScores(
            groupId1,
            groupOwner1,
            members1,
            amounts1,
            scores1
        );

        // Setup group2
        address[] memory members2 = new address[](1);
        members2[0] = user2;
        uint256[] memory amounts2 = new uint256[](1);
        amounts2[0] = 10e18;
        uint256[] memory scores2 = new uint256[](1);
        scores2[0] = 80;

        setupGroupWithScores(
            groupId2,
            groupOwner2,
            members2,
            amounts2,
            scores2
        );

        uint256 round = verify.currentRound();
        uint256 totalReward = 1000e18;
        rewardContract.setReward(round, totalReward);

        // Apply 100% distrust to group1
        setupVerifyVotes(governor, ACTION_ID, address(rewardContract), 100e18);

        vm.prank(governor, governor);
        rewardContract.distrustVote(groupOwner1, 100e18, "Bad");

        // Group1 should get 0
        assertEq(rewardContract.generatedRewardByGroupId(round, groupId1), 0);

        // Group2 should get all
        assertEq(
            rewardContract.generatedRewardByGroupId(round, groupId2),
            totalReward
        );
    }
}
