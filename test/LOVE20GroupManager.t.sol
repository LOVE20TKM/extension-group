// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "./utils/BaseGroupTest.sol";
import {LOVE20GroupManager} from "../src/LOVE20GroupManager.sol";
import {ILOVE20GroupManager} from "../src/interface/ILOVE20GroupManager.sol";
import {MockGroupToken} from "./mocks/MockGroupToken.sol";
import {MockExtension} from "@extension/test/mocks/MockExtension.sol";

/**
 * @title LOVE20GroupManagerTest
 * @notice Test suite for LOVE20GroupManager extension uniqueness constraint
 */
contract LOVE20GroupManagerTest is BaseGroupTest {
    // Additional test extensions and tokens
    MockExtension public extension1;
    MockExtension public extension2;
    MockGroupToken public token2;
    uint256 constant ACTION_ID_1 = 0;
    uint256 constant ACTION_ID_2 = 1;

    function setUp() public {
        setUpBase();

        // Create mock extensions with proper factory setup
        extension1 = new MockExtension(address(mockFactory), address(token));
        extension2 = new MockExtension(address(mockFactory), address(token));

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

        // Setup extension1 config
        vm.prank(address(extension1));
        groupManager.setConfig(
            address(token),
            address(token),
            address(token),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        // Setup extension2 config
        vm.prank(address(extension2));
        groupManager.setConfig(
            address(token),
            address(token),
            address(token),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

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
            ILOVE20GroupManager.ExtensionTokenActionMismatch.selector
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
            ILOVE20GroupManager.ExtensionTokenActionMismatch.selector
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
            ILOVE20GroupManager.ExtensionTokenActionMismatch.selector
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
}
