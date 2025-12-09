// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "../utils/BaseGroupTest.sol";
import {GroupCore} from "../../src/base/GroupCore.sol";
import {IGroupCore} from "../../src/interface/base/IGroupCore.sol";
import {ExtensionReward} from "@extension/src/base/ExtensionReward.sol";
import {IExtensionReward} from "@extension/src/interface/base/IExtensionReward.sol";

/**
 * @title MockGroupCore
 * @notice Concrete implementation of GroupCore for testing
 */
contract MockGroupCore is GroupCore {
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
    {}

    function isJoinedValueCalculated() external pure returns (bool) {
        return false;
    }

    function joinedValue() external pure returns (uint256) {
        return 0;
    }

    function joinedValueByAccount(address) external pure returns (uint256) {
        return 0;
    }

    function _calculateReward(uint256, address) internal pure override returns (uint256) {
        return 0;
    }
}

/**
 * @title GroupCoreTest
 * @notice Test suite for GroupCore
 */
contract GroupCoreTest is BaseGroupTest {
    MockGroupCore public groupCore;

    uint256 public groupId1;
    uint256 public groupId2;

    function setUp() public {
        setUpBase();

        // Deploy GroupCore
        groupCore = new MockGroupCore(
            address(mockFactory),
            address(token),
            address(group),
            address(token), // stakeToken = token
            MIN_GOV_VOTE_RATIO_BPS,
            CAPACITY_MULTIPLIER,
            STAKING_MULTIPLIER,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            MIN_JOIN_AMOUNT
        );

        // Register factory and extension
        registerFactory(address(token), address(mockFactory));
        token.mint(address(this), 1e18);
        token.approve(address(mockFactory), type(uint256).max);
        mockFactory.registerExtension(address(groupCore), address(token));

        // Setup group owners with NFTs and governance votes
        // groupOwner1: 10000e18 govVotes (10% of 100000e18 total)
        groupId1 = setupGroupOwner(groupOwner1, 10000e18, "TestGroup1");
        // groupOwner2: 10000e18 govVotes (10% of 100000e18 total)
        groupId2 = setupGroupOwner(groupOwner2, 10000e18, "TestGroup2");

        // Prepare extension init
        prepareExtensionInit(address(groupCore), address(token), ACTION_ID);
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsImmutables() public view {
        assertEq(groupCore.GROUP_ADDRESS(), address(group));
        assertEq(groupCore.STAKE_TOKEN_ADDRESS(), address(token));
        assertEq(groupCore.MIN_GOV_VOTE_RATIO_BPS(), MIN_GOV_VOTE_RATIO_BPS);
        assertEq(groupCore.CAPACITY_MULTIPLIER(), CAPACITY_MULTIPLIER);
        assertEq(groupCore.STAKING_MULTIPLIER(), STAKING_MULTIPLIER);
        assertEq(groupCore.MAX_JOIN_AMOUNT_MULTIPLIER(), MAX_JOIN_AMOUNT_MULTIPLIER);
        assertEq(groupCore.MIN_JOIN_AMOUNT(), MIN_JOIN_AMOUNT);
    }

    // ============ activateGroup Tests ============

    function test_ActivateGroup_Success() public {
        uint256 stakeAmount = 10000e18;
        setupUser(groupOwner1, stakeAmount, address(groupCore));

        vm.prank(groupOwner1);
        bool success = groupCore.activateGroup(groupId1, "Test Description", stakeAmount, 0, 0);

        assertTrue(success);
        assertTrue(groupCore.isGroupActive(groupId1));
        assertEq(groupCore.totalStaked(), stakeAmount);

        IGroupCore.GroupInfo memory info = groupCore.groupInfo(groupId1);
        assertEq(info.groupId, groupId1);
        assertEq(info.description, "Test Description");
        assertEq(info.stakedAmount, stakeAmount);
        assertTrue(info.isActive);
    }

    function test_ActivateGroup_RevertOnlyGroupOwner() public {
        uint256 stakeAmount = 10000e18;
        setupUser(user1, stakeAmount, address(groupCore));

        vm.prank(user1);
        vm.expectRevert(IGroupCore.OnlyGroupOwner.selector);
        groupCore.activateGroup(groupId1, "Test", stakeAmount, 0, 0);
    }

    function test_ActivateGroup_RevertAlreadyActivated() public {
        uint256 stakeAmount = 10000e18;
        setupUser(groupOwner1, stakeAmount * 2, address(groupCore));

        vm.startPrank(groupOwner1);
        groupCore.activateGroup(groupId1, "Test", stakeAmount, 0, 0);

        vm.expectRevert(IGroupCore.GroupAlreadyActivated.selector);
        groupCore.activateGroup(groupId1, "Test", stakeAmount, 0, 0);
        vm.stopPrank();
    }

    function test_ActivateGroup_RevertZeroStakeAmount() public {
        vm.prank(groupOwner1);
        vm.expectRevert(IGroupCore.ZeroStakeAmount.selector);
        groupCore.activateGroup(groupId1, "Test", 0, 0, 0);
    }

    function test_ActivateGroup_RevertInvalidMinMaxJoinAmount() public {
        uint256 stakeAmount = 10000e18;
        setupUser(groupOwner1, stakeAmount, address(groupCore));

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupCore.InvalidMinMaxJoinAmount.selector);
        groupCore.activateGroup(groupId1, "Test", stakeAmount, 100e18, 50e18);
    }

    function test_ActivateGroup_RevertInsufficientGovVotes() public {
        // Create a group owner with very low governance votes
        address lowVoteOwner = address(0x99);
        uint256 newGroupId = group.mint(lowVoteOwner, "LowVoteGroup");
        stake.setValidGovVotes(address(token), lowVoteOwner, 1e18); // 0.01% of total

        uint256 stakeAmount = 10000e18;
        setupUser(lowVoteOwner, stakeAmount, address(groupCore));

        vm.prank(lowVoteOwner);
        vm.expectRevert(IGroupCore.InsufficientGovVotes.selector);
        groupCore.activateGroup(newGroupId, "Test", stakeAmount, 0, 0);
    }

    function test_ActivateGroup_RevertMinStakeNotMet() public {
        uint256 tooLowStake = 1e15; // Very small stake
        setupUser(groupOwner1, tooLowStake, address(groupCore));

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupCore.MinStakeNotMet.selector);
        groupCore.activateGroup(groupId1, "Test", tooLowStake, 0, 0);
    }

    // ============ expandGroup Tests ============

    function test_ExpandGroup_Success() public {
        // First activate with sufficient stake, then expand
        // Need to stay within maxStake = maxCapacity / STAKING_MULTIPLIER
        // maxCapacity = totalSupply * govVotes * CAPACITY_MULTIPLIER / totalGovVotes
        // = 1_000_000e18 * 10000e18 * 10 / 100_000e18 = 1_000_000e18
        // maxStake = 1_000_000e18 / 100 = 10_000e18
        uint256 initialStake = 5000e18;
        uint256 additionalStake = 500e18;
        setupUser(groupOwner1, initialStake + additionalStake, address(groupCore));

        vm.startPrank(groupOwner1);
        groupCore.activateGroup(groupId1, "Test", initialStake, 0, 0);

        (uint256 newStaked, uint256 newCapacity) = groupCore.expandGroup(groupId1, additionalStake);
        vm.stopPrank();

        assertEq(newStaked, initialStake + additionalStake);
        assertEq(groupCore.totalStaked(), newStaked);

        IGroupCore.GroupInfo memory info = groupCore.groupInfo(groupId1);
        assertEq(info.stakedAmount, newStaked);
        assertEq(info.capacity, newCapacity);
    }

    function test_ExpandGroup_RevertNotActive() public {
        uint256 stakeAmount = 10000e18;
        setupUser(groupOwner1, stakeAmount, address(groupCore));

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupCore.GroupNotActive.selector);
        groupCore.expandGroup(groupId1, stakeAmount);
    }

    function test_ExpandGroup_RevertZeroStakeAmount() public {
        uint256 stakeAmount = 10000e18;
        setupUser(groupOwner1, stakeAmount, address(groupCore));

        vm.startPrank(groupOwner1);
        groupCore.activateGroup(groupId1, "Test", stakeAmount, 0, 0);

        vm.expectRevert(IGroupCore.ZeroStakeAmount.selector);
        groupCore.expandGroup(groupId1, 0);
        vm.stopPrank();
    }

    // ============ deactivateGroup Tests ============

    function test_DeactivateGroup_Success() public {
        uint256 stakeAmount = 10000e18;
        setupUser(groupOwner1, stakeAmount, address(groupCore));

        vm.prank(groupOwner1);
        groupCore.activateGroup(groupId1, "Test", stakeAmount, 0, 0);

        // Advance round to allow deactivation
        advanceRound();

        uint256 balanceBefore = token.balanceOf(groupOwner1);

        vm.prank(groupOwner1);
        groupCore.deactivateGroup(groupId1);

        assertFalse(groupCore.isGroupActive(groupId1));
        assertEq(groupCore.totalStaked(), 0);
        assertEq(token.balanceOf(groupOwner1), balanceBefore + stakeAmount);
    }

    function test_DeactivateGroup_RevertNotFound() public {
        vm.prank(groupOwner1);
        vm.expectRevert(IGroupCore.GroupNotFound.selector);
        groupCore.deactivateGroup(groupId1);
    }

    function test_DeactivateGroup_RevertAlreadyDeactivated() public {
        uint256 stakeAmount = 10000e18;
        setupUser(groupOwner1, stakeAmount, address(groupCore));

        vm.prank(groupOwner1);
        groupCore.activateGroup(groupId1, "Test", stakeAmount, 0, 0);

        advanceRound();

        vm.startPrank(groupOwner1);
        groupCore.deactivateGroup(groupId1);

        vm.expectRevert(IGroupCore.GroupAlreadyDeactivated.selector);
        groupCore.deactivateGroup(groupId1);
        vm.stopPrank();
    }

    function test_DeactivateGroup_RevertInActivatedRound() public {
        uint256 stakeAmount = 10000e18;
        setupUser(groupOwner1, stakeAmount, address(groupCore));

        vm.startPrank(groupOwner1);
        groupCore.activateGroup(groupId1, "Test", stakeAmount, 0, 0);

        // Try to deactivate in the same round
        vm.expectRevert(IGroupCore.CannotDeactivateInActivatedRound.selector);
        groupCore.deactivateGroup(groupId1);
        vm.stopPrank();
    }

    // ============ updateGroupInfo Tests ============

    function test_UpdateGroupInfo_Success() public {
        uint256 stakeAmount = 10000e18;
        setupUser(groupOwner1, stakeAmount, address(groupCore));

        vm.prank(groupOwner1);
        groupCore.activateGroup(groupId1, "Test", stakeAmount, 0, 0);

        vm.prank(groupOwner1);
        groupCore.updateGroupInfo(groupId1, "New Description", 10e18, 100e18);

        IGroupCore.GroupInfo memory info = groupCore.groupInfo(groupId1);
        assertEq(info.description, "New Description");
        assertEq(info.groupMinJoinAmount, 10e18);
        assertEq(info.groupMaxJoinAmount, 100e18);
    }

    function test_UpdateGroupInfo_RevertInvalidMinMax() public {
        uint256 stakeAmount = 10000e18;
        setupUser(groupOwner1, stakeAmount, address(groupCore));

        vm.prank(groupOwner1);
        groupCore.activateGroup(groupId1, "Test", stakeAmount, 0, 0);

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupCore.InvalidMinMaxJoinAmount.selector);
        groupCore.updateGroupInfo(groupId1, "New", 100e18, 50e18);
    }

    // ============ View Functions Tests ============

    function test_ActiveGroupIds() public {
        uint256 stakeAmount = 10000e18;
        setupUser(groupOwner1, stakeAmount, address(groupCore));
        setupUser(groupOwner2, stakeAmount, address(groupCore));

        vm.prank(groupOwner1);
        groupCore.activateGroup(groupId1, "Test1", stakeAmount, 0, 0);

        vm.prank(groupOwner2);
        groupCore.activateGroup(groupId2, "Test2", stakeAmount, 0, 0);

        uint256[] memory activeIds = groupCore.activeGroupIds();
        assertEq(activeIds.length, 2);
        assertEq(groupCore.activeGroupIdsCount(), 2);
    }

    function test_ActiveGroupIdsByOwner() public {
        // Mint another group for owner1
        uint256 groupId3 = group.mint(groupOwner1, "TestGroup3");

        // Increase governance votes to allow multiple groups
        // maxStake = (totalSupply * govVotes * CAPACITY_MULTIPLIER) / totalGovVotes / STAKING_MULTIPLIER
        // To allow 2 * 5000e18 = 10000e18 stake, need more govVotes
        stake.setValidGovVotes(address(token), groupOwner1, 20000e18);

        uint256 stakeAmount = 5000e18;
        setupUser(groupOwner1, stakeAmount * 2, address(groupCore));

        vm.startPrank(groupOwner1);
        groupCore.activateGroup(groupId1, "Test1", stakeAmount, 0, 0);
        groupCore.activateGroup(groupId3, "Test3", stakeAmount, 0, 0);
        vm.stopPrank();

        uint256[] memory ownerActiveIds = groupCore.activeGroupIdsByOwner(groupOwner1);
        assertEq(ownerActiveIds.length, 2);
    }

    function test_CalculateJoinMaxAmount() public view {
        uint256 totalSupply = token.totalSupply();
        uint256 expected = totalSupply / MAX_JOIN_AMOUNT_MULTIPLIER;
        assertEq(groupCore.calculateJoinMaxAmount(), expected);
    }

    function test_MaxCapacityByOwner() public view {
        uint256 maxCapacity = groupCore.maxCapacityByOwner(groupOwner1);
        // groupOwner1 has 1000e18 govVotes out of 10000e18 total (10%)
        // maxCapacity = totalSupply * ownerGovVotes * CAPACITY_MULTIPLIER / totalGovVotes
        uint256 totalSupply = token.totalSupply();
        uint256 expected = (totalSupply * 1000e18 * CAPACITY_MULTIPLIER) / 10000e18;
        assertEq(maxCapacity, expected);
    }

    function test_TotalStakedByOwner() public {
        uint256 stakeAmount = 10000e18;
        setupUser(groupOwner1, stakeAmount, address(groupCore));

        assertEq(groupCore.totalStakedByOwner(groupOwner1), 0);

        vm.prank(groupOwner1);
        groupCore.activateGroup(groupId1, "Test", stakeAmount, 0, 0);

        assertEq(groupCore.totalStakedByOwner(groupOwner1), stakeAmount);
    }

    function test_ExpandableInfo() public {
        uint256 stakeAmount = 10000e18;
        setupUser(groupOwner1, stakeAmount, address(groupCore));

        vm.prank(groupOwner1);
        groupCore.activateGroup(groupId1, "Test", stakeAmount, 0, 0);

        (
            uint256 currentCapacity,
            uint256 maxCapacity,
            uint256 currentStake,
            uint256 maxStake,
            uint256 additionalStakeAllowed
        ) = groupCore.expandableInfo(groupOwner1);

        assertTrue(currentCapacity > 0);
        assertEq(currentStake, stakeAmount);
        assertTrue(maxCapacity > 0);
        assertTrue(maxStake > 0);
        if (maxStake > currentStake) {
            assertEq(additionalStakeAllowed, maxStake - currentStake);
        }
    }
}

