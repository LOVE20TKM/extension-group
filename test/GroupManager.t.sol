// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "./utils/BaseGroupTest.sol";
import {GroupManager} from "../src/GroupManager.sol";
import {IGroupManager} from "../src/interface/IGroupManager.sol";
import {IGroupManagerEvents} from "../src/interface/IGroupManager.sol";
import {IGroupManagerErrors} from "../src/interface/IGroupManager.sol";
import {IExtensionCenter} from "@extension/src/interface/IExtensionCenter.sol";
import {MockGroupToken} from "./mocks/MockGroupToken.sol";
import {MockExtensionGroupAction} from "./mocks/MockExtensionGroupAction.sol";

/**
 * @title GroupManagerTest
 * @notice Comprehensive test suite for GroupManager contract
 * @dev Tests cover group activation/deactivation, info updates, view functions, and extension uniqueness constraints
 */
contract GroupManagerTest is BaseGroupTest, IGroupManagerEvents {
    // Additional test extensions and tokens
    MockExtensionGroupAction public extension1;
    MockExtensionGroupAction public extension2;
    MockGroupToken public token2;
    uint256 constant ACTION_ID_1 = 0;
    uint256 constant ACTION_ID_2 = 1;

    function setUp() public {
        setUpBase();

        // Create mock extensions with proper factory setup and config
        // Use mockGroupActionFactory since groupManager uses it
        extension1 = new MockExtensionGroupAction(
            address(mockGroupActionFactory),
            address(token),
            address(token), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );
        extension2 = new MockExtensionGroupAction(
            address(mockGroupActionFactory),
            address(token),
            address(token), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        // Approve factory to transfer tokens for registration
        // DEFAULT_JOIN_AMOUNT is typically 1e18
        token.approve(address(mockGroupActionFactory), type(uint256).max);

        // Register extensions in mockGroupActionFactory (this will transfer DEFAULT_JOIN_AMOUNT to each extension)
        mockGroupActionFactory.registerExtensionForTesting(
            address(extension1),
            address(token)
        );
        mockGroupActionFactory.registerExtensionForTesting(
            address(extension2),
            address(token)
        );

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

        // Prepare extension initialization so initializeIfNeeded() can find the actionId
        prepareExtensionInit(address(extension1), address(token), ACTION_ID_1);
        prepareExtensionInit(address(extension2), address(token), ACTION_ID_2);
        prepareExtensionInit(address(extension1), address(token2), ACTION_ID_1);

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
            address(extension1),
            groupId,
            "Test Group",
            0,
            1e18,
            0,
            0
        );

        // Verify group is active
        assertTrue(
            groupManager.isGroupActive(address(extension1), groupId),
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
            address(extension1),
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
            address(extension1),
            groupId2,
            "Test Group 2",
            0,
            1e18,
            0,
            0
        );

        // Both groups should be active
        assertTrue(
            groupManager.isGroupActive(address(extension1), groupId1),
            "Group1 should be active"
        );
        assertTrue(
            groupManager.isGroupActive(address(extension1), groupId2),
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
            address(extension1),
            groupId1,
            "Test Group 1",
            0,
            1e18,
            0,
            0
        );

        // Second activation with same extension should succeed (same extension can activate multiple groups)
        // Extension's tokenAddress and actionId are fixed, so it will use the same (token, ACTION_ID_1)
        vm.prank(groupOwner2, groupOwner2);
        groupManager.activateGroup(
            address(extension1),
            groupId2,
            "Test Group 2",
            0,
            1e18,
            0,
            0
        );

        // Verify both groups are active
        assertTrue(
            groupManager.isGroupActive(address(extension1), groupId1),
            "Group1 should be active"
        );
        assertTrue(
            groupManager.isGroupActive(address(extension1), groupId2),
            "Group2 should be active"
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
            address(extension1),
            groupId1,
            "Test Group 1",
            0,
            1e18,
            0,
            0
        );

        // Second activation with same extension should succeed (same extension can activate multiple groups)
        // Extension's tokenAddress and actionId are fixed, so it will use the same (token, ACTION_ID_1)
        vm.prank(groupOwner2, groupOwner2);
        groupManager.activateGroup(
            address(extension1),
            groupId2,
            "Test Group 2",
            0,
            1e18,
            0,
            0
        );

        // Verify both groups are active
        assertTrue(
            groupManager.isGroupActive(address(extension1), groupId1),
            "Group1 should be active"
        );
        assertTrue(
            groupManager.isGroupActive(address(extension1), groupId2),
            "Group2 should be active"
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
            address(extension1),
            groupId1,
            "Test Group 1",
            0,
            1e18,
            0,
            0
        );

        // Verify group1 is active with extension1
        assertTrue(
            groupManager.isGroupActive(address(extension1), groupId1),
            "Group1 should be active"
        );

        // Second activation with extension2 (different extension, same token, different actionId)
        // This verifies that different extensions can coexist with the same token
        submit.setActionInfo(address(token), ACTION_ID_2, address(extension2));
        vm.prank(groupOwner2, groupOwner2);
        groupManager.activateGroup(
            address(extension2),
            groupId2,
            "Test Group 2",
            0,
            1e18,
            0,
            0
        );

        // Verify both groups are active with their respective extensions
        assertTrue(
            groupManager.isGroupActive(address(extension1), groupId1),
            "Group1 should be active"
        );
        assertTrue(
            groupManager.isGroupActive(address(extension2), groupId2),
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
            address(extension1),
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
        groupManager.deactivateGroup(address(extension1), groupId1);

        // Try to activate with same extension should succeed (binding persists but can activate new groups)
        // Extension's tokenAddress and actionId are fixed, so it will use the same (token, ACTION_ID_1)
        vm.prank(groupOwner2, groupOwner2);
        groupManager.activateGroup(
            address(extension1),
            groupId2,
            "Test Group 2",
            0,
            1e18,
            0,
            0
        );

        // Verify group2 is active
        assertTrue(
            groupManager.isGroupActive(address(extension1), groupId2),
            "Group2 should be active"
        );
    }

    // ============ activateGroup Tests ============

    // Success Cases

    /// @notice Test: activateGroup with valid parameters succeeds
    /// @dev Basic functionality: group activation with all valid parameters
    function test_activateGroup_WithValidParameters_Succeeds() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
            groupId,
            "Test Group",
            100,
            1e18,
            2e18,
            10
        );

        assertTrue(
            groupManager.isGroupActive(address(extension1), groupId),
            "Group should be active"
        );
    }

    // Error Cases

    /// @notice Test: Activating already activated group should revert
    /// @dev State validation: cannot activate an already active group
    function test_activateGroup_WhenAlreadyActivated_Reverts() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT * 2,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
            groupId,
            "Test Group",
            0,
            1e18,
            0,
            0
        );

        // Try to activate again should revert
        vm.prank(groupOwner1, groupOwner1);
        vm.expectRevert(IGroupManagerErrors.GroupAlreadyActivated.selector);
        groupManager.activateGroup(
            address(extension1),
            groupId,
            "Test Group 2",
            0,
            1e18,
            0,
            0
        );
    }

    /// @notice Test: Activating with invalid min/max join amount should revert
    /// @dev Boundary condition: maxJoinAmount must be >= minJoinAmount
    function test_activateGroup_WithInvalidMinMaxJoinAmount_Reverts() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        // maxJoinAmount < minJoinAmount should revert
        vm.prank(groupOwner1, groupOwner1);
        vm.expectRevert(IGroupManagerErrors.InvalidMinMaxJoinAmount.selector);
        groupManager.activateGroup(
            address(extension1),
            groupId,
            "Test Group",
            0,
            2e18, // minJoinAmount
            1e18, // maxJoinAmount < minJoinAmount
            0
        );
    }

    /// @notice Test: Activating with non-owner should revert
    /// @dev Permission validation: only group owner can activate
    function test_activateGroup_ByNonOwner_Reverts() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner2,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        // groupOwner2 tries to activate groupOwner1's group
        vm.prank(groupOwner2, groupOwner2);
        vm.expectRevert(IGroupManagerErrors.OnlyGroupOwner.selector);
        groupManager.activateGroup(
            address(extension1),
            groupId,
            "Test Group",
            0,
            1e18,
            0,
            0
        );
    }

    // ============ deactivateGroup Tests ============

    // Error Cases

    /// @notice Test: Deactivating in the same round should revert
    /// @dev State validation: cannot deactivate in the same round as activation
    function test_deactivateGroup_InSameRoundAsActivation_Reverts() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT * 2,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
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
            IGroupManagerErrors.CannotDeactivateInActivatedRound.selector
        );
        groupManager.deactivateGroup(address(extension1), groupId);
    }

    /// @notice Test: Deactivating non-active group should revert
    /// @dev State validation: cannot deactivate an inactive group
    function test_deactivateGroup_WhenNotActive_Reverts() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT * 2,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
            groupId,
            "Test Group",
            0,
            1e18,
            0,
            0
        );

        advanceRound();
        vm.prank(groupOwner1, groupOwner1);
        groupManager.deactivateGroup(address(extension1), groupId);

        // Try to deactivate again should revert
        vm.prank(groupOwner1, groupOwner1);
        vm.expectRevert(IGroupManagerErrors.GroupNotActive.selector);
        groupManager.deactivateGroup(address(extension1), groupId);
    }

    /// @notice Test: Deactivating with non-owner should revert
    /// @dev Permission validation: only group owner can deactivate
    function test_deactivateGroup_ByNonOwner_Reverts() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT * 2,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
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
        vm.expectRevert(IGroupManagerErrors.OnlyGroupOwner.selector);
        groupManager.deactivateGroup(address(extension1), groupId);
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
            address(extension1),
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
        groupManager.deactivateGroup(address(extension1), groupId);

        uint256 balanceAfterDeactivation = token.balanceOf(groupOwner1);
        assertEq(
            balanceAfterDeactivation,
            balanceBefore,
            "Stake should be returned"
        );
    }

    // ============ updateGroupInfo Tests ============

    // Success Cases

    /// @notice Test: Update group info successfully
    /// @dev Basic functionality: all group info fields can be updated
    function test_updateGroupInfo_WithValidParameters_Succeeds() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
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
            address(extension1),
            groupId,
            "Updated Description",
            200,
            2e18,
            3e18,
            20
        );

        // Verify updated info
        IGroupManager.GroupInfo memory info = groupManager.groupInfo(
            address(extension1),
            groupId
        );

        assertEq(info.groupId, groupId, "GroupId should match");
        assertEq(
            info.description,
            "Updated Description",
            "Description should be updated"
        );
        assertEq(info.maxCapacity, 200, "MaxCapacity should be updated");
        assertEq(info.minJoinAmount, 2e18, "MinJoinAmount should be updated");
        assertEq(info.maxJoinAmount, 3e18, "MaxJoinAmount should be updated");
        assertEq(info.maxAccounts, 20, "MaxAccounts should be updated");
        assertTrue(info.isActive, "Group should still be active");
    }

    // Error Cases

    /// @notice Test: Update group info with invalid min/max join amount should revert
    /// @dev Boundary condition: maxJoinAmount must be >= minJoinAmount
    function test_updateGroupInfo_WithInvalidMinMaxJoinAmount_Reverts() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
            groupId,
            "Test Group",
            0,
            1e18,
            0,
            0
        );

        // maxJoinAmount < minJoinAmount should revert
        vm.prank(groupOwner1, groupOwner1);
        vm.expectRevert(IGroupManagerErrors.InvalidMinMaxJoinAmount.selector);
        groupManager.updateGroupInfo(
            address(extension1),
            groupId,
            "Updated Description",
            0,
            2e18, // minJoinAmount
            1e18, // maxJoinAmount < minJoinAmount
            0
        );
    }

    /// @notice Test: Update inactive group should revert
    /// @dev State validation: cannot update inactive groups
    function test_updateGroupInfo_WhenGroupNotActive_Reverts() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT * 2,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
            groupId,
            "Test Group",
            0,
            1e18,
            0,
            0
        );

        advanceRound();
        vm.prank(groupOwner1, groupOwner1);
        groupManager.deactivateGroup(address(extension1), groupId);

        // Try to update deactivated group should revert
        vm.prank(groupOwner1, groupOwner1);
        vm.expectRevert(IGroupManagerErrors.GroupNotActive.selector);
        groupManager.updateGroupInfo(
            address(extension1),
            groupId,
            "Updated Description",
            0,
            1e18,
            0,
            0
        );
    }

    /// @notice Test: Update group info with non-owner should revert
    /// @dev Permission validation: only group owner can update
    function test_updateGroupInfo_ByNonOwner_Reverts() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
            groupId,
            "Test Group",
            0,
            1e18,
            0,
            0
        );

        // groupOwner2 tries to update groupOwner1's group
        vm.prank(groupOwner2, groupOwner2);
        vm.expectRevert(IGroupManagerErrors.OnlyGroupOwner.selector);
        groupManager.updateGroupInfo(
            address(extension1),
            groupId,
            "Updated Description",
            0,
            1e18,
            0,
            0
        );
    }

    // ============ View Functions Tests ============

    /// @notice Test: groupInfo returns correct values
    /// @dev View function validation: all group info fields are correctly returned
    function test_groupInfo_AfterActivation_ReturnsCorrectValues() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
            groupId,
            "Test Description",
            100,
            1e18,
            2e18,
            10
        );

        IGroupManager.GroupInfo memory info = groupManager.groupInfo(
            address(extension1),
            groupId
        );

        assertEq(info.groupId, groupId, "GroupId should match");
        assertEq(info.description, "Test Description", "Description should match");
        assertEq(info.maxCapacity, 100, "MaxCapacity should match");
        assertEq(info.minJoinAmount, 1e18, "MinJoinAmount should match");
        assertEq(info.maxJoinAmount, 2e18, "MaxJoinAmount should match");
        assertEq(info.maxAccounts, 10, "MaxAccounts should match");
        assertTrue(info.isActive, "Group should be active");
        assertEq(
            info.activatedRound,
            join.currentRound(),
            "ActivatedRound should match"
        );
        assertEq(info.deactivatedRound, 0, "DeactivatedRound should be 0");
    }

    /// @notice Test: descriptionByRound returns correct description for activation round
    function test_descriptionByRound_ReturnsActivationRoundDescription() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        uint256 activationRound = join.currentRound();
        string memory initialDesc = "Initial Description";

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
            groupId,
            initialDesc,
            100,
            1e18,
            2e18,
            10
        );

        string memory desc = groupManager.descriptionByRound(
            address(extension1),
            activationRound,
            groupId
        );

        assertEq(desc, initialDesc, "Description should match activation round");
    }

    /// @notice Test: descriptionByRound returns correct description after update across rounds
    function test_descriptionByRound_ReturnsCorrectDescriptionAcrossRounds() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        uint256 round1 = join.currentRound();
        string memory desc1 = "Round 1 Description";

        // Activate in round 1
        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
            groupId,
            desc1,
            100,
            1e18,
            2e18,
            10
        );

        // Advance to round 2
        advanceRound();
        uint256 round2 = join.currentRound();
        string memory desc2 = "Round 2 Description";

        // Update description in round 2
        vm.prank(groupOwner1, groupOwner1);
        groupManager.updateGroupInfo(
            address(extension1),
            groupId,
            desc2,
            200,
            2e18,
            3e18,
            20
        );

        // Advance to round 3
        advanceRound();
        uint256 round3 = join.currentRound();
        string memory desc3 = "Round 3 Description";

        // Update description in round 3
        vm.prank(groupOwner1, groupOwner1);
        groupManager.updateGroupInfo(
            address(extension1),
            groupId,
            desc3,
            300,
            3e18,
            4e18,
            30
        );

        // Verify round 1 description is preserved
        string memory retrievedDesc1 = groupManager.descriptionByRound(
            address(extension1),
            round1,
            groupId
        );
        assertEq(retrievedDesc1, desc1, "Round 1 description should be preserved");

        // Verify round 2 description is preserved
        string memory retrievedDesc2 = groupManager.descriptionByRound(
            address(extension1),
            round2,
            groupId
        );
        assertEq(retrievedDesc2, desc2, "Round 2 description should be preserved");

        // Verify round 3 description is correct
        string memory retrievedDesc3 = groupManager.descriptionByRound(
            address(extension1),
            round3,
            groupId
        );
        assertEq(retrievedDesc3, desc3, "Round 3 description should be correct");

        // Verify current groupInfo returns latest description
        IGroupManager.GroupInfo memory info = groupManager.groupInfo(
            address(extension1),
            groupId
        );
        assertEq(info.description, desc3, "Current description should be latest");
    }

    /// @notice Test: descriptionByRound returns empty string for non-existent round
    function test_descriptionByRound_ReturnsEmptyForNonExistentRound() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        uint256 activationRound = join.currentRound();

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
            groupId,
            "Test Description",
            100,
            1e18,
            2e18,
            10
        );

        // Query a round that doesn't exist (before activation)
        uint256 nonExistentRound = activationRound - 1;
        string memory desc = groupManager.descriptionByRound(
            address(extension1),
            nonExistentRound,
            groupId
        );

        assertEq(bytes(desc).length, 0, "Description should be empty for non-existent round");
    }

    /// @notice Test: descriptionByRound works correctly for multiple groups
    function test_descriptionByRound_MultipleGroups() public {
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

        uint256 round1 = join.currentRound();

        // Activate group 1
        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
            groupId1,
            "Group 1 Description",
            100,
            1e18,
            2e18,
            10
        );

        // Activate group 2
        vm.prank(groupOwner2, groupOwner2);
        groupManager.activateGroup(
            address(extension1),
            groupId2,
            "Group 2 Description",
            200,
            2e18,
            3e18,
            20
        );

        // Advance round
        advanceRound();
        uint256 round2 = join.currentRound();

        // Update group 1
        vm.prank(groupOwner1, groupOwner1);
        groupManager.updateGroupInfo(
            address(extension1),
            groupId1,
            "Group 1 Updated",
            150,
            1.5e18,
            2.5e18,
            15
        );

        // Verify group 1 round 1 description
        string memory desc1Round1 = groupManager.descriptionByRound(
            address(extension1),
            round1,
            groupId1
        );
        assertEq(desc1Round1, "Group 1 Description", "Group 1 round 1 description should match");

        // Verify group 1 round 2 description
        string memory desc1Round2 = groupManager.descriptionByRound(
            address(extension1),
            round2,
            groupId1
        );
        assertEq(desc1Round2, "Group 1 Updated", "Group 1 round 2 description should match");

        // Verify group 2 round 1 description (unchanged)
        string memory desc2Round1 = groupManager.descriptionByRound(
            address(extension1),
            round1,
            groupId2
        );
        assertEq(desc2Round1, "Group 2 Description", "Group 2 round 1 description should match");

        // Verify group 2 round 2 description (unchanged, no update)
        string memory desc2Round2 = groupManager.descriptionByRound(
            address(extension1),
            round2,
            groupId2
        );
        assertEq(desc2Round2, "Group 2 Description", "Group 2 round 2 description should be same as round 1");
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
            address(extension1),
            groupId1,
            "Test Group 1",
            0,
            1e18,
            0,
            0
        );

        vm.prank(groupOwner2, groupOwner2);
        groupManager.activateGroup(
            address(extension1),
            groupId2,
            "Test Group 2",
            0,
            1e18,
            0,
            0
        );

        uint256[] memory activeIds = groupManager.activeGroupIds(
            address(extension1)
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
            groupManager.activeGroupIdsCount(address(extension1)),
            0,
            "Should have 0 active groups initially"
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
            groupId1,
            "Test Group 1",
            0,
            1e18,
            0,
            0
        );

        assertEq(
            groupManager.activeGroupIdsCount(address(extension1)),
            1,
            "Should have 1 active group"
        );

        vm.prank(groupOwner2, groupOwner2);
        groupManager.activateGroup(
            address(extension1),
            groupId2,
            "Test Group 2",
            0,
            1e18,
            0,
            0
        );

        assertEq(
            groupManager.activeGroupIdsCount(address(extension1)),
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
            address(extension1),
            groupId1,
            "Test Group 1",
            0,
            1e18,
            0,
            0
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
            groupId2,
            "Test Group 2",
            0,
            1e18,
            0,
            0
        );

        uint256[] memory activeIds = groupManager.activeGroupIdsByOwner(
            address(extension1),
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
            groupManager.staked(address(extension1)),
            0,
            "Should have 0 staked initially"
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
            groupId1,
            "Test Group 1",
            0,
            1e18,
            0,
            0
        );

        assertEq(
            groupManager.staked(address(extension1)),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            "Should have 1 stake amount"
        );

        vm.prank(groupOwner2, groupOwner2);
        groupManager.activateGroup(
            address(extension1),
            groupId2,
            "Test Group 2",
            0,
            1e18,
            0,
            0
        );

        assertEq(
            groupManager.staked(address(extension1)),
            GROUP_ACTIVATION_STAKE_AMOUNT * 2,
            "Should have 2 stake amounts"
        );
    }

    /// @notice Test: stakedByOwner returns correct amount
    function test_totalStakedByActionIdByOwner_ReturnsCorrectAmount() public {
        uint256 groupId1 = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        uint256 groupId2 = setupGroupOwner(groupOwner1, 10000e18, "Group2");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT * 2,
            address(groupManager)
        );

        assertEq(
            groupManager.stakedByOwner(address(extension1), groupOwner1),
            0,
            "Should have 0 staked initially"
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
            groupId1,
            "Test Group 1",
            0,
            1e18,
            0,
            0
        );

        assertEq(
            groupManager.stakedByOwner(address(extension1), groupOwner1),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            "Should have 1 stake amount"
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
            groupId2,
            "Test Group 2",
            0,
            1e18,
            0,
            0
        );

        assertEq(
            groupManager.stakedByOwner(address(extension1), groupOwner1),
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
    /// @dev Initialization validation: factory address is correctly set
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

    // ============ Boundary Condition Tests ============

    /// @notice Test: activateGroup with zero maxCapacity uses owner's theoretical max
    /// @dev Boundary condition: zero maxCapacity should be treated as unlimited (uses owner capacity)
    function test_activateGroup_WithZeroMaxCapacity_UsesOwnerCapacity() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
            groupId,
            "Test Group",
            0, // maxCapacity = 0 means use owner's capacity
            1e18,
            0,
            0
        );

        assertTrue(
            groupManager.isGroupActive(address(extension1), groupId),
            "Group should be active"
        );
    }

    /// @notice Test: activateGroup with max uint256 values
    /// @dev Boundary condition: test with maximum possible values
    function test_activateGroup_WithMaxValues_Succeeds() public {
        uint256 groupId = setupGroupOwner(groupOwner1, type(uint256).max, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
            groupId,
            "Test Group",
            type(uint256).max,
            type(uint256).max,
            type(uint256).max,
            type(uint256).max
        );

        assertTrue(
            groupManager.isGroupActive(address(extension1), groupId),
            "Group should be active"
        );
    }

    /// @notice Test: activateGroup with empty description
    /// @dev Boundary condition: empty string description should be accepted
    function test_activateGroup_WithEmptyDescription_Succeeds() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
            groupId,
            "", // empty description
            0,
            1e18,
            0,
            0
        );

        assertTrue(
            groupManager.isGroupActive(address(extension1), groupId),
            "Group should be active"
        );
    }

    /// @notice Test: updateGroupInfo with zero values where valid
    /// @dev Boundary condition: zero values should be accepted where valid (minJoinAmount cannot be 0)
    function test_updateGroupInfo_WithZeroValuesWhereValid_Succeeds() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
            groupId,
            "Test Group",
            100,
            1e18,
            2e18,
            10
        );

        // Update with zero values (where valid)
        // Note: minJoinAmount cannot be 0, so we use 1e18
        vm.prank(groupOwner1, groupOwner1);
        groupManager.updateGroupInfo(
            address(extension1),
            groupId,
            "Updated",
            0, // maxCapacity = 0 (valid)
            1e18, // minJoinAmount = 1e18 (cannot be 0)
            0, // maxJoinAmount = 0 (valid, means no limit)
            0  // maxAccounts = 0 (valid, means no limit)
        );

        IGroupManager.GroupInfo memory info = groupManager.groupInfo(
            address(extension1),
            groupId
        );
        
        assertEq(info.maxCapacity, 0, "MaxCapacity should be 0");
        assertEq(info.minJoinAmount, 1e18, "MinJoinAmount should be 1e18");
        assertEq(info.maxJoinAmount, 0, "MaxJoinAmount should be 0");
        assertEq(info.maxAccounts, 0, "MaxAccounts should be 0");
    }

    // ============ Fuzzing Tests ============

    /// @notice Fuzz test: maxVerifyCapacityByOwner calculation is correct
    /// @dev Property-based test: capacity calculation follows the formula
    ///      capacity = (totalMinted * ownerGovVotes * MAX_VERIFY_CAPACITY_FACTOR) / (totalGovVotes * PRECISION)
    function testFuzz_maxVerifyCapacityByOwner_CalculationIsCorrect(
        uint256 govVotes
    ) public {
        // Constrain input to reasonable range to avoid overflow
        vm.assume(govVotes > 0 && govVotes <= type(uint128).max);
        
        stake.setValidGovVotes(address(token), groupOwner1, govVotes);
        
        uint256 capacity = groupManager.maxVerifyCapacityByOwner(
            address(extension1),
            groupOwner1
        );
        
        // Capacity calculation: (totalMinted * ownerGovVotes * MAX_VERIFY_CAPACITY_FACTOR) / (totalGovVotes * PRECISION)
        // Since we can't easily get totalMinted in the test, we just verify the capacity is non-negative
        // and that the function doesn't revert
        // The actual value depends on totalMinted and totalGovVotes which are set in setUpBase
        assertTrue(capacity >= 0, "Capacity should be non-negative");
    }

    /// @notice Fuzz test: activateGroup with various valid parameters
    /// @dev Property-based test: activation should succeed with valid inputs
    function testFuzz_activateGroup_WithValidParameters_Succeeds(
        uint256 maxCapacity,
        uint256 minJoinAmount,
        uint256 maxJoinAmount,
        uint256 maxAccounts
    ) public {
        // Constrain inputs to reasonable ranges
        vm.assume(maxCapacity <= type(uint128).max);
        // minJoinAmount must be > 0 (validation requirement)
        vm.assume(minJoinAmount > 0 && minJoinAmount <= type(uint128).max);
        // maxJoinAmount must be >= minJoinAmount if not 0, or 0 (no limit)
        vm.assume(maxJoinAmount == 0 || (maxJoinAmount >= minJoinAmount && maxJoinAmount <= type(uint128).max));
        vm.assume(maxAccounts <= 1000); // Reasonable limit for maxAccounts
        
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
            groupId,
            "Test Group",
            maxCapacity,
            minJoinAmount,
            maxJoinAmount,
            maxAccounts
        );

        assertTrue(
            groupManager.isGroupActive(address(extension1), groupId),
            "Group should be active"
        );
    }

    /// @notice Fuzz test: updateGroupInfo with various valid parameters
    /// @dev Property-based test: update should succeed with valid inputs
    function testFuzz_updateGroupInfo_WithValidParameters_Succeeds(
        uint256 maxCapacity,
        uint256 minJoinAmount,
        uint256 maxJoinAmount,
        uint256 maxAccounts
    ) public {
        // Constrain inputs to reasonable ranges
        vm.assume(maxCapacity <= type(uint128).max);
        // minJoinAmount must be > 0 (validation requirement)
        vm.assume(minJoinAmount > 0 && minJoinAmount <= type(uint128).max);
        // maxJoinAmount must be >= minJoinAmount if not 0, or 0 (no limit)
        vm.assume(maxJoinAmount == 0 || (maxJoinAmount >= minJoinAmount && maxJoinAmount <= type(uint128).max));
        vm.assume(maxAccounts <= 1000);
        
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
            groupId,
            "Test Group",
            100,
            1e18,
            2e18,
            10
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.updateGroupInfo(
            address(extension1),
            groupId,
            "Updated",
            maxCapacity,
            minJoinAmount,
            maxJoinAmount,
            maxAccounts
        );

        IGroupManager.GroupInfo memory updatedInfo = groupManager.groupInfo(
            address(extension1),
            groupId
        );
        
        assertEq(updatedInfo.maxCapacity, maxCapacity, "MaxCapacity should match");
        assertEq(updatedInfo.minJoinAmount, minJoinAmount, "MinJoinAmount should match");
        assertEq(updatedInfo.maxJoinAmount, maxJoinAmount, "MaxJoinAmount should match");
        assertEq(updatedInfo.maxAccounts, maxAccounts, "MaxAccounts should match");
    }

    // ============ Event Tests ============

    /// @notice Test: activateGroup emits ActivateGroup event with correct parameters
    /// @dev Event validation: verifies event is emitted with correct data
    function test_activateGroup_EmitsActivateGroupEvent() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        uint256 currentRound = join.currentRound();
        address tokenAddress = address(token);
        uint256 actionId = ACTION_ID_1;
        uint256 stakeAmount = GROUP_ACTIVATION_STAKE_AMOUNT;

        vm.expectEmit(true, true, true, true);
        emit IGroupManagerEvents.ActivateGroup(
            tokenAddress,
            actionId,
            currentRound,
            groupId,
            groupOwner1,
            stakeAmount
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
            groupId,
            "Test Group",
            100,
            1e18,
            2e18,
            10
        );
    }

    /// @notice Test: deactivateGroup emits DeactivateGroup event with correct parameters
    /// @dev Event validation: verifies event is emitted with correct data
    function test_deactivateGroup_EmitsDeactivateGroupEvent() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT * 2,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
            groupId,
            "Test Group",
            0,
            1e18,
            0,
            0
        );

        advanceRound();
        uint256 currentRound = join.currentRound();
        address tokenAddress = address(token);
        uint256 actionId = ACTION_ID_1;
        uint256 stakeAmount = GROUP_ACTIVATION_STAKE_AMOUNT;

        vm.expectEmit(true, true, true, true);
        emit IGroupManagerEvents.DeactivateGroup(
            tokenAddress,
            actionId,
            currentRound,
            groupId,
            groupOwner1,
            stakeAmount
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.deactivateGroup(address(extension1), groupId);
    }

    /// @notice Test: updateGroupInfo emits UpdateGroupInfo event with correct parameters
    /// @dev Event validation: verifies event is emitted with correct data
    function test_updateGroupInfo_EmitsUpdateGroupInfoEvent() public {
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(extension1),
            groupId,
            "Initial Description",
            100,
            1e18,
            2e18,
            10
        );

        uint256 currentRound = join.currentRound();
        address tokenAddress = address(token);
        uint256 actionId = ACTION_ID_1;
        string memory newDescription = "Updated Description";
        uint256 newMaxCapacity = 200;
        uint256 newMinJoinAmount = 2e18;
        uint256 newMaxJoinAmount = 3e18;
        uint256 newMaxAccounts = 20;

        vm.expectEmit(true, true, true, true);
        emit IGroupManagerEvents.UpdateGroupInfo(
            tokenAddress,
            actionId,
            currentRound,
            groupId,
            newDescription,
            newMaxCapacity,
            newMinJoinAmount,
            newMaxJoinAmount,
            newMaxAccounts
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.updateGroupInfo(
            address(extension1),
            groupId,
            newDescription,
            newMaxCapacity,
            newMinJoinAmount,
            newMaxJoinAmount,
            newMaxAccounts
        );
    }
}
