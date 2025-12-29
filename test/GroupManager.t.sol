// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "./utils/BaseGroupTest.sol";
import {GroupManager} from "../src/GroupManager.sol";
import {IGroupManager} from "../src/interface/IGroupManager.sol";
import {MockGroupToken} from "./mocks/MockGroupToken.sol";
import {MockExtensionGroupAction} from "./mocks/MockExtensionGroupAction.sol";

/**
 * @title GroupManagerTest
 * @notice Test suite for GroupManager extension uniqueness constraint
 */
contract GroupManagerTest is BaseGroupTest {
    // Additional test extensions and tokens
    MockExtensionGroupAction public extension1;
    MockExtensionGroupAction public extension2;
    MockGroupToken public token2;
    uint256 constant ACTION_ID_1 = 0;
    uint256 constant ACTION_ID_2 = 1;

    function setUp() public {
        setUpBase();

        // Create mock extensions with proper factory setup and config
        extension1 = new MockExtensionGroupAction(
            address(mockFactory),
            address(token),
            address(token), // stakeTokenAddress
            address(token), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );
        extension2 = new MockExtensionGroupAction(
            address(mockFactory),
            address(token),
            address(token), // stakeTokenAddress
            address(token), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        // Approve factory to transfer tokens for registration
        // DEFAULT_JOIN_AMOUNT is typically 1e18
        token.approve(address(mockFactory), type(uint256).max);

        // Register extensions in factory (this will transfer DEFAULT_JOIN_AMOUNT to each extension)
        mockFactory.registerExtension(address(extension1), address(token));
        mockFactory.registerExtension(address(extension2), address(token));

        // Create second token
        token2 = new MockGroupToken();

        // Setup initial token2 supply
        token2.mint(address(this), 1_000_000e18);

        // Config is now stored in extension contracts, not in GroupManager
        // No need to call setConfig anymore

        // Setup extension mappings
        submit.setActionInfo(address(token), ACTION_ID_1, address(extension1));
        submit.setActionInfo(address(token), ACTION_ID_2, address(extension2));
        submit.setActionInfo(address(token2), ACTION_ID_1, address(extension1));

        // Setup group owners
        setupGroupOwner(groupOwner1, 10000e18, "TestGroup1");
        setupGroupOwner(groupOwner2, 10000e18, "TestGroup2");
    }

    // ============ Tests for _checkAndSetExtensionTokenActionPair ============

    /// @notice Test: First activation should set the binding
    function test_firstActivationSetsBinding() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId,
            "Test Group",
            0,
            1e18,
            0,
            0
        );

        // Verify group is active
        assertTrue(
            groupManager.isGroupActive(address(token), ACTION_ID_1, groupId),
            "Group should be active"
        );
    }

    /// @notice Test: Same extension with same (tokenAddress, actionId) should succeed
    function test_sameExtensionSameTokenActionIdSucceeds() public {
        uint256 groupId1 = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        uint256 groupId2 = setupGroupOwner(groupOwner2, 10000e18, "Group2");

        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT * 2,
            address(groupManager)
        );
        setupUser(
            groupOwner2,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        // First activation
        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId1,
            "Test Group 1",
            0,
            1e18,
            0,
            0
        );

        // Second activation with same extension, same (tokenAddress, actionId) should succeed
        vm.prank(groupOwner2, groupOwner2);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId2,
            "Test Group 2",
            0,
            1e18,
            0,
            0
        );

        // Both groups should be active
        assertTrue(
            groupManager.isGroupActive(address(token), ACTION_ID_1, groupId1),
            "Group1 should be active"
        );
        assertTrue(
            groupManager.isGroupActive(address(token), ACTION_ID_1, groupId2),
            "Group2 should be active"
        );
    }

    /// @notice Test: Same extension with different tokenAddress should revert
    function test_sameExtensionDifferentTokenAddressReverts() public {
        uint256 groupId1 = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        uint256 groupId2 = setupGroupOwner(groupOwner2, 10000e18, "Group2");

        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT * 2,
            address(groupManager)
        );
        setupUser(
            groupOwner2,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        // First activation with token
        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId1,
            "Test Group 1",
            0,
            1e18,
            0,
            0
        );

        // Map extension1 to (token2, ACTION_ID_1) - same extension, different token
        submit.setActionInfo(address(token2), ACTION_ID_1, address(extension1));

        // Second activation with same extension but different tokenAddress should revert
        // Note: This will fail at config check since extension1's config uses token, not token2
        // But the uniqueness check should happen first, so we expect ExtensionTokenActionMismatch
        vm.prank(groupOwner2, groupOwner2);
        vm.expectRevert(
            IGroupManager.ExtensionTokenActionMismatch.selector
        );
        groupManager.activateGroup(
            address(token2),
            ACTION_ID_1,
            groupId2,
            "Test Group 2",
            0,
            1e18,
            0,
            0
        );
    }

    /// @notice Test: Same extension with different actionId should revert
    function test_sameExtensionDifferentActionIdReverts() public {
        uint256 groupId1 = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        uint256 groupId2 = setupGroupOwner(groupOwner2, 10000e18, "Group2");

        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT * 2,
            address(groupManager)
        );
        setupUser(
            groupOwner2,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        // First activation with ACTION_ID_1
        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId1,
            "Test Group 1",
            0,
            1e18,
            0,
            0
        );

        // Setup extension1 for ACTION_ID_2 (but same extension address)
        submit.setActionInfo(address(token), ACTION_ID_2, address(extension1));

        // Second activation with same extension but different actionId should revert
        vm.prank(groupOwner2, groupOwner2);
        vm.expectRevert(
            IGroupManager.ExtensionTokenActionMismatch.selector
        );
        groupManager.activateGroup(
            address(token),
            ACTION_ID_2,
            groupId2,
            "Test Group 2",
            0,
            1e18,
            0,
            0
        );
    }

    /// @notice Test: Different extensions can use same token (with different actionIds)
    /// @dev Since one (tokenAddress, actionId) maps to one extension, we test with different actionIds
    function test_differentExtensionsCanUseSameTokenActionId() public {
        // extension2 config is already set in setUp

        uint256 groupId1 = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        uint256 groupId2 = setupGroupOwner(groupOwner2, 10000e18, "Group2");

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

        // First activation with extension1
        submit.setActionInfo(address(token), ACTION_ID_1, address(extension1));
        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId1,
            "Test Group 1",
            0,
            1e18,
            0,
            0
        );

        // Verify group1 is active with extension1
        assertTrue(
            groupManager.isGroupActive(address(token), ACTION_ID_1, groupId1),
            "Group1 should be active"
        );

        // Second activation with extension2 (different extension, same token, different actionId)
        // This verifies that different extensions can coexist with the same token
        submit.setActionInfo(address(token), ACTION_ID_2, address(extension2));
        vm.prank(groupOwner2, groupOwner2);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_2,
            groupId2,
            "Test Group 2",
            0,
            1e18,
            0,
            0
        );

        // Verify both groups are active with their respective extensions
        assertTrue(
            groupManager.isGroupActive(address(token), ACTION_ID_1, groupId1),
            "Group1 should be active"
        );
        assertTrue(
            groupManager.isGroupActive(address(token), ACTION_ID_2, groupId2),
            "Group2 should be active"
        );
    }

    /// @notice Test: Binding persists even after deactivation
    function test_bindingPersistsAfterDeactivation() public {
        uint256 groupId1 = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        uint256 groupId2 = setupGroupOwner(groupOwner2, 10000e18, "Group2");

        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT * 2,
            address(groupManager)
        );
        setupUser(
            groupOwner2,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        // First activation
        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId1,
            "Test Group 1",
            0,
            1e18,
            0,
            0
        );

        // Deactivate group1
        advanceRound();
        vm.prank(groupOwner1, groupOwner1);
        groupManager.deactivateGroup(address(token), ACTION_ID_1, groupId1);

        // Try to activate with different actionId should still revert
        submit.setActionInfo(address(token), ACTION_ID_2, address(extension1));
        vm.prank(groupOwner2, groupOwner2);
        vm.expectRevert(
            IGroupManager.ExtensionTokenActionMismatch.selector
        );
        groupManager.activateGroup(
            address(token),
            ACTION_ID_2,
            groupId2,
            "Test Group 2",
            0,
            1e18,
            0,
            0
        );
    }

    // ============ Tests for activateGroup error cases ============

    /// @notice Test: Activating already activated group should revert
    function test_activateGroup_GroupAlreadyActivated() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT * 2,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId,
            "Test Group",
            0,
            1e18,
            0,
            0
        );

        // Try to activate again should revert
        vm.prank(groupOwner1, groupOwner1);
        vm.expectRevert(IGroupManager.GroupAlreadyActivated.selector);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId,
            "Test Group 2",
            0,
            1e18,
            0,
            0
        );
    }

    /// @notice Test: Activating with invalid min/max join amount should revert
    function test_activateGroup_InvalidMinMaxJoinAmount() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        // maxJoinAmount < minJoinAmount should revert
        vm.prank(groupOwner1, groupOwner1);
        vm.expectRevert(IGroupManager.InvalidMinMaxJoinAmount.selector);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId,
            "Test Group",
            0,
            2e18, // minJoinAmount
            1e18, // maxJoinAmount < minJoinAmount
            0
        );
    }

    /// @notice Test: Activating with non-owner should revert
    function test_activateGroup_OnlyGroupOwner() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner2,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        // groupOwner2 tries to activate groupOwner1's group
        vm.prank(groupOwner2, groupOwner2);
        vm.expectRevert(IGroupManager.OnlyGroupOwner.selector);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId,
            "Test Group",
            0,
            1e18,
            0,
            0
        );
    }

    // ============ Tests for deactivateGroup ============

    /// @notice Test: Deactivating in the same round should revert
    function test_deactivateGroup_CannotDeactivateInActivatedRound() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT * 2,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId,
            "Test Group",
            0,
            1e18,
            0,
            0
        );

        // Try to deactivate in the same round should revert
        vm.prank(groupOwner1, groupOwner1);
        vm.expectRevert(
            IGroupManager.CannotDeactivateInActivatedRound.selector
        );
        groupManager.deactivateGroup(address(token), ACTION_ID_1, groupId);
    }

    /// @notice Test: Deactivating non-existent group should revert
    function test_deactivateGroup_GroupNotFound() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");

        vm.prank(groupOwner1, groupOwner1);
        vm.expectRevert(IGroupManager.GroupNotFound.selector);
        groupManager.deactivateGroup(address(token), ACTION_ID_1, groupId);
    }

    /// @notice Test: Deactivating already deactivated group should revert
    function test_deactivateGroup_GroupAlreadyDeactivated() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT * 2,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId,
            "Test Group",
            0,
            1e18,
            0,
            0
        );

        advanceRound();
        vm.prank(groupOwner1, groupOwner1);
        groupManager.deactivateGroup(address(token), ACTION_ID_1, groupId);

        // Try to deactivate again should revert
        vm.prank(groupOwner1, groupOwner1);
        vm.expectRevert(IGroupManager.GroupAlreadyDeactivated.selector);
        groupManager.deactivateGroup(address(token), ACTION_ID_1, groupId);
    }

    /// @notice Test: Deactivating with non-owner should revert
    function test_deactivateGroup_OnlyGroupOwner() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT * 2,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId,
            "Test Group",
            0,
            1e18,
            0,
            0
        );

        advanceRound();
        // groupOwner2 tries to deactivate groupOwner1's group
        vm.prank(groupOwner2, groupOwner2);
        vm.expectRevert(IGroupManager.OnlyGroupOwner.selector);
        groupManager.deactivateGroup(address(token), ACTION_ID_1, groupId);
    }

    /// @notice Test: Deactivating should return stake to owner
    function test_deactivateGroup_ReturnsStake() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT * 2,
            address(groupManager)
        );

        uint256 balanceBefore = token.balanceOf(groupOwner1);

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId,
            "Test Group",
            0,
            1e18,
            0,
            0
        );

        uint256 balanceAfterActivation = token.balanceOf(groupOwner1);
        assertEq(
            balanceBefore - balanceAfterActivation,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            "Stake should be transferred"
        );

        advanceRound();
        vm.prank(groupOwner1, groupOwner1);
        groupManager.deactivateGroup(address(token), ACTION_ID_1, groupId);

        uint256 balanceAfterDeactivation = token.balanceOf(groupOwner1);
        assertEq(
            balanceAfterDeactivation,
            balanceBefore,
            "Stake should be returned"
        );
    }

    // ============ Tests for updateGroupInfo ============

    /// @notice Test: Update group info successfully
    function test_updateGroupInfo_Success() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId,
            "Initial Description",
            100,
            1e18,
            2e18,
            10
        );

        // Update group info
        vm.prank(groupOwner1, groupOwner1);
        groupManager.updateGroupInfo(
            address(token),
            ACTION_ID_1,
            groupId,
            "Updated Description",
            200,
            2e18,
            3e18,
            20
        );

        // Verify updated info
        (
            uint256 groupId_,
            string memory description,
            uint256 maxCapacity,
            uint256 minJoinAmount,
            uint256 maxJoinAmount,
            uint256 maxAccounts,
            bool isActive,
            ,
        ) = groupManager.groupInfo(address(token), ACTION_ID_1, groupId);

        assertEq(groupId_, groupId, "GroupId should match");
        assertEq(description, "Updated Description", "Description should be updated");
        assertEq(maxCapacity, 200, "MaxCapacity should be updated");
        assertEq(minJoinAmount, 2e18, "MinJoinAmount should be updated");
        assertEq(maxJoinAmount, 3e18, "MaxJoinAmount should be updated");
        assertEq(maxAccounts, 20, "MaxAccounts should be updated");
        assertTrue(isActive, "Group should still be active");
    }

    /// @notice Test: Update group info with invalid min/max join amount should revert
    function test_updateGroupInfo_InvalidMinMaxJoinAmount() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId,
            "Test Group",
            0,
            1e18,
            0,
            0
        );

        // maxJoinAmount < minJoinAmount should revert
        vm.prank(groupOwner1, groupOwner1);
        vm.expectRevert(IGroupManager.InvalidMinMaxJoinAmount.selector);
        groupManager.updateGroupInfo(
            address(token),
            ACTION_ID_1,
            groupId,
            "Updated Description",
            0,
            2e18, // minJoinAmount
            1e18, // maxJoinAmount < minJoinAmount
            0
        );
    }

    /// @notice Test: Update inactive group should revert
    function test_updateGroupInfo_GroupNotActive() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT * 2,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId,
            "Test Group",
            0,
            1e18,
            0,
            0
        );

        advanceRound();
        vm.prank(groupOwner1, groupOwner1);
        groupManager.deactivateGroup(address(token), ACTION_ID_1, groupId);

        // Try to update deactivated group should revert
        vm.prank(groupOwner1, groupOwner1);
        vm.expectRevert(IGroupManager.GroupNotActive.selector);
        groupManager.updateGroupInfo(
            address(token),
            ACTION_ID_1,
            groupId,
            "Updated Description",
            0,
            1e18,
            0,
            0
        );
    }

    /// @notice Test: Update group info with non-owner should revert
    function test_updateGroupInfo_OnlyGroupOwner() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId,
            "Test Group",
            0,
            1e18,
            0,
            0
        );

        // groupOwner2 tries to update groupOwner1's group
        vm.prank(groupOwner2, groupOwner2);
        vm.expectRevert(IGroupManager.OnlyGroupOwner.selector);
        groupManager.updateGroupInfo(
            address(token),
            ACTION_ID_1,
            groupId,
            "Updated Description",
            0,
            1e18,
            0,
            0
        );
    }

    // ============ Tests for view functions ============

    /// @notice Test: groupInfo returns correct values
    function test_groupInfo_ReturnsCorrectValues() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId,
            "Test Description",
            100,
            1e18,
            2e18,
            10
        );

        (
            uint256 groupId_,
            string memory description,
            uint256 maxCapacity,
            uint256 minJoinAmount,
            uint256 maxJoinAmount,
            uint256 maxAccounts,
            bool isActive,
            uint256 activatedRound,
            uint256 deactivatedRound
        ) = groupManager.groupInfo(address(token), ACTION_ID_1, groupId);

        assertEq(groupId_, groupId, "GroupId should match");
        assertEq(description, "Test Description", "Description should match");
        assertEq(maxCapacity, 100, "MaxCapacity should match");
        assertEq(minJoinAmount, 1e18, "MinJoinAmount should match");
        assertEq(maxJoinAmount, 2e18, "MaxJoinAmount should match");
        assertEq(maxAccounts, 10, "MaxAccounts should match");
        assertTrue(isActive, "Group should be active");
        assertEq(activatedRound, join.currentRound(), "ActivatedRound should match");
        assertEq(deactivatedRound, 0, "DeactivatedRound should be 0");
    }

    /// @notice Test: activeGroupIds returns correct group IDs
    function test_activeGroupIds_ReturnsCorrectIds() public {
        uint256 groupId1 = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        uint256 groupId2 = setupGroupOwner(groupOwner2, 10000e18, "Group2");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT * 2,
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
            ACTION_ID_1,
            groupId1,
            "Test Group 1",
            0,
            1e18,
            0,
            0
        );

        vm.prank(groupOwner2, groupOwner2);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId2,
            "Test Group 2",
            0,
            1e18,
            0,
            0
        );

        uint256[] memory activeIds = groupManager.activeGroupIds(
            address(token),
            ACTION_ID_1
        );
        assertEq(activeIds.length, 2, "Should have 2 active groups");
        assertTrue(
            (activeIds[0] == groupId1 && activeIds[1] == groupId2) ||
                (activeIds[0] == groupId2 && activeIds[1] == groupId1),
            "Should contain both group IDs"
        );
    }

    /// @notice Test: activeGroupIdsCount returns correct count
    function test_activeGroupIdsCount_ReturnsCorrectCount() public {
        uint256 groupId1 = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        uint256 groupId2 = setupGroupOwner(groupOwner2, 10000e18, "Group2");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT * 2,
            address(groupManager)
        );
        setupUser(
            groupOwner2,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        assertEq(
            groupManager.activeGroupIdsCount(address(token), ACTION_ID_1),
            0,
            "Should have 0 active groups initially"
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId1,
            "Test Group 1",
            0,
            1e18,
            0,
            0
        );

        assertEq(
            groupManager.activeGroupIdsCount(address(token), ACTION_ID_1),
            1,
            "Should have 1 active group"
        );

        vm.prank(groupOwner2, groupOwner2);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId2,
            "Test Group 2",
            0,
            1e18,
            0,
            0
        );

        assertEq(
            groupManager.activeGroupIdsCount(address(token), ACTION_ID_1),
            2,
            "Should have 2 active groups"
        );
    }

    /// @notice Test: activeGroupIdsByOwner returns correct group IDs
    function test_activeGroupIdsByOwner_ReturnsCorrectIds() public {
        uint256 groupId1 = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        uint256 groupId2 = setupGroupOwner(groupOwner1, 10000e18, "Group2");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT * 2,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId1,
            "Test Group 1",
            0,
            1e18,
            0,
            0
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId2,
            "Test Group 2",
            0,
            1e18,
            0,
            0
        );

        uint256[] memory activeIds = groupManager.activeGroupIdsByOwner(
            address(token),
            ACTION_ID_1,
            groupOwner1
        );
        assertEq(activeIds.length, 2, "Should have 2 active groups");
        assertTrue(
            (activeIds[0] == groupId1 && activeIds[1] == groupId2) ||
                (activeIds[0] == groupId2 && activeIds[1] == groupId1),
            "Should contain both group IDs"
        );
    }

    /// @notice Test: totalStaked returns correct amount
    function test_totalStaked_ReturnsCorrectAmount() public {
        uint256 groupId1 = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        uint256 groupId2 = setupGroupOwner(groupOwner2, 10000e18, "Group2");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT * 2,
            address(groupManager)
        );
        setupUser(
            groupOwner2,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        assertEq(
            groupManager.totalStaked(address(token), ACTION_ID_1),
            0,
            "Should have 0 staked initially"
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId1,
            "Test Group 1",
            0,
            1e18,
            0,
            0
        );

        assertEq(
            groupManager.totalStaked(address(token), ACTION_ID_1),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            "Should have 1 stake amount"
        );

        vm.prank(groupOwner2, groupOwner2);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId2,
            "Test Group 2",
            0,
            1e18,
            0,
            0
        );

        assertEq(
            groupManager.totalStaked(address(token), ACTION_ID_1),
            GROUP_ACTIVATION_STAKE_AMOUNT * 2,
            "Should have 2 stake amounts"
        );
    }

    /// @notice Test: totalStakedByActionIdByOwner returns correct amount
    function test_totalStakedByActionIdByOwner_ReturnsCorrectAmount() public {
        uint256 groupId1 = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        uint256 groupId2 = setupGroupOwner(groupOwner1, 10000e18, "Group2");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT * 2,
            address(groupManager)
        );

        assertEq(
            groupManager.totalStakedByActionIdByOwner(
                address(token),
                ACTION_ID_1,
                groupOwner1
            ),
            0,
            "Should have 0 staked initially"
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId1,
            "Test Group 1",
            0,
            1e18,
            0,
            0
        );

        assertEq(
            groupManager.totalStakedByActionIdByOwner(
                address(token),
                ACTION_ID_1,
                groupOwner1
            ),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            "Should have 1 stake amount"
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID_1,
            groupId2,
            "Test Group 2",
            0,
            1e18,
            0,
            0
        );

        assertEq(
            groupManager.totalStakedByActionIdByOwner(
                address(token),
                ACTION_ID_1,
                groupOwner1
            ),
            GROUP_ACTIVATION_STAKE_AMOUNT * 2,
            "Should have 2 stake amounts"
        );
    }

    // ============ Tests for constants ============

    /// @notice Test: FACTORY_ADDRESS returns correct address
    function test_FACTORY_ADDRESS_ReturnsCorrectAddress() public view {
        assertEq(
            groupManager.FACTORY_ADDRESS(),
            address(mockGroupActionFactory),
            "Factory address should match"
        );
    }

    /// @notice Test: PRECISION returns correct value
    function test_PRECISION_ReturnsCorrectValue() public view {
        assertEq(groupManager.PRECISION(), 1e18, "Precision should be 1e18");
    }

    // ============ Tests for initialize ============

    /// @notice Test: Initialize should set factory address
    function test_initialize_SetsFactoryAddress() public {
        GroupManager newGroupManager = new GroupManager();
        IGroupManager(address(newGroupManager)).initialize(
            address(mockGroupActionFactory)
        );

        assertEq(
            newGroupManager.FACTORY_ADDRESS(),
            address(mockGroupActionFactory),
            "Factory address should be set"
        );
    }

    /// @notice Test: Initialize twice should revert
    function test_initialize_AlreadyInitialized() public {
        GroupManager newGroupManager = new GroupManager();
        IGroupManager(address(newGroupManager)).initialize(
            address(mockGroupActionFactory)
        );

        vm.expectRevert(IGroupManager.AlreadyInitialized.selector);
        IGroupManager(address(newGroupManager)).initialize(
            address(mockGroupActionFactory)
        );
    }

    /// @notice Test: Initialize with zero address should revert
    function test_initialize_InvalidFactory() public {
        GroupManager newGroupManager = new GroupManager();

        vm.expectRevert(IGroupManager.InvalidFactory.selector);
        IGroupManager(address(newGroupManager)).initialize(address(0));
    }
}
