// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "./utils/BaseGroupTest.sol";
import {IGroupJoin} from "../src/interface/IGroupJoin.sol";
import {ExtensionGroupAction} from "../src/ExtensionGroupAction.sol";
import {MockExtensionGroupAction} from "./mocks/MockExtensionGroupAction.sol";

/**
 * @title GroupJoinGlobalStateTest
 * @notice Unit tests for _updateGlobalStateOnJoin and _updateGlobalStateOnExit
 */
contract GroupJoinGlobalStateTest is BaseGroupTest {
    ExtensionGroupAction public groupAction;
    uint256 public groupId1;
    uint256 public groupId2;
    address public tokenAddress;
    uint256 public actionId;

    function setUp() public {
        setUpBase();

        // Create group action
        (
            address joinTokenAddress,
            uint256 activationStakeAmount,
            uint256 maxJoinAmountRatio,
            uint256 maxVerifyCapacityFactor
        ) = createDefaultConfig();

        groupAction = new ExtensionGroupAction(
            address(mockGroupActionFactory),
            address(token),
            joinTokenAddress,
            activationStakeAmount,
            maxJoinAmountRatio,
            maxVerifyCapacityFactor
        );

        // Register extension in mockGroupActionFactory
        token.mint(address(this), 1e18);
        token.approve(address(mockGroupActionFactory), type(uint256).max);
        mockGroupActionFactory.registerExtensionForTesting(
            address(groupAction),
            address(token)
        );

        // Prepare extension init
        prepareExtensionInit(address(groupAction), address(token), ACTION_ID);

        tokenAddress = address(token);
        actionId = ACTION_ID;

        // Setup group owners
        groupId1 = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        groupId2 = setupGroupOwner(groupOwner2, 10000e18, "Group2");

        // Setup users for activation
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

        // Activate groups
        vm.prank(groupOwner1);
        groupManager.activateGroup(
            address(groupAction),
            groupId1,
            "Group1",
            0,
            1e18,
            0,
            0
        );

        vm.prank(groupOwner2);
        groupManager.activateGroup(
            address(groupAction),
            groupId2,
            "Group2",
            0,
            1e18,
            0,
            0
        );
    }

    // ============ _updateGlobalStateOnJoin Tests ============

    /// @notice Test _updateGlobalStateOnJoin with single account
    function test_updateGlobalStateOnJoin_SingleAccount() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));

        // Join
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // Verify all global state
        _verifyGlobalStateAfterJoin(user1, groupId1, tokenAddress, actionId);
    }

    /// @notice Test _updateGlobalStateOnJoin with multiple accounts
    function test_updateGlobalStateOnJoin_MultipleAccounts() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));
        setupUser(user2, joinAmount, address(groupJoin));
        setupUser(user3, joinAmount, address(groupJoin));

        // Join user1
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // Join user2
        vm.prank(user2);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // Join user3
        vm.prank(user3);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // Verify gGroupIds (should still be 1)
        assertEq(groupJoin.gGroupIdsCount(), 1, "gGroupIdsCount should be 1");
        assertEq(
            groupJoin.gGroupIdsAtIndex(0),
            groupId1,
            "gGroupIdsAtIndex should be groupId1"
        );

        // Verify gAccounts (should have 3 accounts)
        assertEq(groupJoin.gAccountsCount(), 3, "gAccountsCount should be 3");
        assertTrue(
            _containsAddress(groupJoin.gAccounts(), user1),
            "gAccounts should contain user1"
        );
        assertTrue(
            _containsAddress(groupJoin.gAccounts(), user2),
            "gAccounts should contain user2"
        );
        assertTrue(
            _containsAddress(groupJoin.gAccounts(), user3),
            "gAccounts should contain user3"
        );

        // Verify gAccountsByGroupId
        assertEq(
            groupJoin.gAccountsByGroupIdCount(groupId1),
            3,
            "gAccountsByGroupIdCount should be 3"
        );
        assertTrue(
            _containsAddress(groupJoin.gAccountsByGroupId(groupId1), user1),
            "gAccountsByGroupId should contain user1"
        );
        assertTrue(
            _containsAddress(groupJoin.gAccountsByGroupId(groupId1), user2),
            "gAccountsByGroupId should contain user2"
        );
        assertTrue(
            _containsAddress(groupJoin.gAccountsByGroupId(groupId1), user3),
            "gAccountsByGroupId should contain user3"
        );

        // Verify gAccountsByTokenAddress
        assertEq(
            groupJoin.gAccountsByTokenAddressCount(tokenAddress),
            3,
            "gAccountsByTokenAddressCount should be 3"
        );
        assertTrue(
            _containsAddress(
                groupJoin.gAccountsByTokenAddress(tokenAddress),
                user1
            ),
            "gAccountsByTokenAddress should contain user1"
        );
        assertTrue(
            _containsAddress(
                groupJoin.gAccountsByTokenAddress(tokenAddress),
                user2
            ),
            "gAccountsByTokenAddress should contain user2"
        );
        assertTrue(
            _containsAddress(
                groupJoin.gAccountsByTokenAddress(tokenAddress),
                user3
            ),
            "gAccountsByTokenAddress should contain user3"
        );

        // Verify all users have the same groupId
        uint256[] memory user1GroupIds = groupJoin.gGroupIdsByAccount(user1);
        uint256[] memory user2GroupIds = groupJoin.gGroupIdsByAccount(user2);
        uint256[] memory user3GroupIds = groupJoin.gGroupIdsByAccount(user3);
        assertEq(user1GroupIds.length, 1, "user1 should have 1 groupId");
        assertEq(user2GroupIds.length, 1, "user2 should have 1 groupId");
        assertEq(user3GroupIds.length, 1, "user3 should have 1 groupId");
        assertEq(user1GroupIds[0], groupId1, "user1 groupId should match");
        assertEq(user2GroupIds[0], groupId1, "user2 groupId should match");
        assertEq(user3GroupIds[0], groupId1, "user3 groupId should match");
    }

    /// @notice Test _updateGlobalStateOnJoin with multiple groups
    function test_updateGlobalStateOnJoin_MultipleGroups() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount * 2, address(groupJoin));
        setupUser(user2, joinAmount, address(groupJoin));

        // Create second extension for groupId2
        ExtensionGroupAction groupAction2 = new ExtensionGroupAction(
            address(mockGroupActionFactory),
            address(token),
            address(token),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        uint256 actionId2 = 1;
        token.mint(address(this), 1e18);
        token.approve(address(mockGroupActionFactory), type(uint256).max);
        mockGroupActionFactory.registerExtensionForTesting(
            address(groupAction2),
            address(token)
        );

        prepareExtensionInit(address(groupAction2), address(token), actionId2);

        // Setup groupOwner2 with more tokens for second activation
        setupUser(
            groupOwner2,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        // Activate group2
        vm.prank(groupOwner2);
        groupManager.activateGroup(
            address(groupAction2),
            groupId2,
            "Group2",
            0,
            1e18,
            0,
            0
        );

        // User1 joins group1
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // User2 joins group1
        vm.prank(user2);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // User1 needs more tokens for second join
        token.mint(user1, joinAmount);
        vm.prank(user1);
        token.approve(address(groupJoin), type(uint256).max);

        // User1 joins group2 (different extension, same token)
        vm.prank(user1);
        groupJoin.join(
            address(groupAction2),
            groupId2,
            joinAmount,
            new string[](0)
        );

        // Verify gGroupIds (should have 2 groups)
        assertEq(groupJoin.gGroupIdsCount(), 2, "gGroupIdsCount should be 2");
        assertTrue(
            _containsUint256(groupJoin.gGroupIds(), groupId1),
            "gGroupIds should contain groupId1"
        );
        assertTrue(
            _containsUint256(groupJoin.gGroupIds(), groupId2),
            "gGroupIds should contain groupId2"
        );

        // Verify user1 has both groups
        uint256[] memory user1GroupIds = groupJoin.gGroupIdsByAccount(user1);
        assertEq(user1GroupIds.length, 2, "user1 should have 2 groupIds");
        assertTrue(
            _containsUint256(user1GroupIds, groupId1),
            "user1 should have groupId1"
        );
        assertTrue(
            _containsUint256(user1GroupIds, groupId2),
            "user1 should have groupId2"
        );

        // Verify user2 has only group1
        uint256[] memory user2GroupIds = groupJoin.gGroupIdsByAccount(user2);
        assertEq(user2GroupIds.length, 1, "user2 should have 1 groupId");
        assertEq(user2GroupIds[0], groupId1, "user2 should have groupId1");

        // Verify gGroupIdsByTokenAddress (should have both groups)
        uint256[] memory groupIdsByToken = groupJoin.gGroupIdsByTokenAddress(
            tokenAddress
        );
        assertEq(
            groupIdsByToken.length,
            2,
            "gGroupIdsByTokenAddress should have 2 groups"
        );
        assertTrue(
            _containsUint256(groupIdsByToken, groupId1),
            "gGroupIdsByTokenAddress should contain groupId1"
        );
        assertTrue(
            _containsUint256(groupIdsByToken, groupId2),
            "gGroupIdsByTokenAddress should contain groupId2"
        );

        // Verify gActionIdsByTokenAddress (should have both actionIds)
        uint256[] memory actionIdsByToken = groupJoin
            .gActionIdsByTokenAddress(tokenAddress);
        assertEq(
            actionIdsByToken.length,
            2,
            "gActionIdsByTokenAddress should have 2 actionIds"
        );
        assertTrue(
            _containsUint256(actionIdsByToken, actionId),
            "gActionIdsByTokenAddress should contain actionId"
        );
        assertTrue(
            _containsUint256(actionIdsByToken, actionId2),
            "gActionIdsByTokenAddress should contain actionId2"
        );
    }

    // ============ _updateGlobalStateOnExit Tests ============

    /// @notice Test _updateGlobalStateOnExit with single account
    function test_updateGlobalStateOnExit_SingleAccount() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));

        // Join
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // Verify state after join
        assertEq(groupJoin.gGroupIdsCount(), 1, "gGroupIdsCount should be 1");
        assertEq(groupJoin.gAccountsCount(), 1, "gAccountsCount should be 1");

        // Exit
        vm.prank(user1);
        groupJoin.exit(address(groupAction));

        // Verify all global state is cleaned up
        assertEq(groupJoin.gGroupIdsCount(), 0, "gGroupIdsCount should be 0");
        assertEq(groupJoin.gAccountsCount(), 0, "gAccountsCount should be 0");
        assertEq(
            groupJoin.gGroupIdsByAccountCount(user1),
            0,
            "gGroupIdsByAccountCount should be 0"
        );
        assertEq(
            groupJoin.gTokenAddressesCount(),
            0,
            "gTokenAddressesCount should be 0"
        );
        assertEq(
            groupJoin.gTokenAddressesByAccountCount(user1),
            0,
            "gTokenAddressesByAccountCount should be 0"
        );
        assertEq(
            groupJoin.gTokenAddressesByGroupIdCount(groupId1),
            0,
            "gTokenAddressesByGroupIdCount should be 0"
        );
        assertEq(
            groupJoin.gActionIdsByTokenAddressCount(tokenAddress),
            0,
            "gActionIdsByTokenAddressCount should be 0"
        );
        assertEq(
            groupJoin.gActionIdsByTokenAddressByAccountCount(
                tokenAddress,
                user1
            ),
            0,
            "gActionIdsByTokenAddressByAccountCount should be 0"
        );
        assertEq(
            groupJoin.gActionIdsByTokenAddressByGroupIdCount(
                tokenAddress,
                groupId1
            ),
            0,
            "gActionIdsByTokenAddressByGroupIdCount should be 0"
        );
        assertEq(
            groupJoin.gAccountsByGroupIdCount(groupId1),
            0,
            "gAccountsByGroupIdCount should be 0"
        );
        assertEq(
            groupJoin.gAccountsByTokenAddressCount(tokenAddress),
            0,
            "gAccountsByTokenAddressCount should be 0"
        );
        assertEq(
            groupJoin.gAccountsByTokenAddressByGroupIdCount(
                tokenAddress,
                groupId1
            ),
            0,
            "gAccountsByTokenAddressByGroupIdCount should be 0"
        );
    }

    /// @notice Test _updateGlobalStateOnExit with multiple accounts (one exits)
    function test_updateGlobalStateOnExit_MultipleAccounts_OneExits() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));
        setupUser(user2, joinAmount, address(groupJoin));
        setupUser(user3, joinAmount, address(groupJoin));

        // All users join
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        vm.prank(user2);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        vm.prank(user3);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // Verify initial state
        assertEq(groupJoin.gAccountsCount(), 3, "gAccountsCount should be 3");
        assertEq(
            groupJoin.gAccountsByGroupIdCount(groupId1),
            3,
            "gAccountsByGroupIdCount should be 3"
        );

        // User1 exits
        vm.prank(user1);
        groupJoin.exit(address(groupAction));

        // Verify state after user1 exits
        assertEq(groupJoin.gAccountsCount(), 2, "gAccountsCount should be 2");
        assertEq(
            groupJoin.gAccountsByGroupIdCount(groupId1),
            2,
            "gAccountsByGroupIdCount should be 2"
        );
        assertEq(
            groupJoin.gGroupIdsByAccountCount(user1),
            0,
            "user1 should have no groupIds"
        );
        assertEq(
            groupJoin.gGroupIdsByAccountCount(user2),
            1,
            "user2 should still have 1 groupId"
        );
        assertEq(
            groupJoin.gGroupIdsByAccountCount(user3),
            1,
            "user3 should still have 1 groupId"
        );

        // Verify groupId1 is still tracked (other users still in it)
        assertEq(groupJoin.gGroupIdsCount(), 1, "gGroupIdsCount should be 1");
        assertEq(
            groupJoin.gGroupIdsAtIndex(0),
            groupId1,
            "gGroupIds should still contain groupId1"
        );

        // Verify tokenAddress is still tracked
        assertEq(
            groupJoin.gTokenAddressesCount(),
            1,
            "gTokenAddressesCount should be 1"
        );
        assertEq(
            groupJoin.gTokenAddressesAtIndex(0),
            tokenAddress,
            "gTokenAddresses should still contain tokenAddress"
        );

        // Verify actionId is still tracked
        assertEq(
            groupJoin.gActionIdsByTokenAddressCount(tokenAddress),
            1,
            "gActionIdsByTokenAddressCount should be 1"
        );
    }

    /// @notice Test _updateGlobalStateOnExit with multiple accounts (all exit)
    function test_updateGlobalStateOnExit_MultipleAccounts_AllExit() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));
        setupUser(user2, joinAmount, address(groupJoin));
        setupUser(user3, joinAmount, address(groupJoin));

        // All users join
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        vm.prank(user2);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        vm.prank(user3);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // All users exit
        vm.prank(user1);
        groupJoin.exit(address(groupAction));

        vm.prank(user2);
        groupJoin.exit(address(groupAction));

        vm.prank(user3);
        groupJoin.exit(address(groupAction));

        // Verify all global state is cleaned up
        assertEq(groupJoin.gGroupIdsCount(), 0, "gGroupIdsCount should be 0");
        assertEq(groupJoin.gAccountsCount(), 0, "gAccountsCount should be 0");
        assertEq(
            groupJoin.gTokenAddressesCount(),
            0,
            "gTokenAddressesCount should be 0"
        );
        assertEq(
            groupJoin.gActionIdsByTokenAddressCount(tokenAddress),
            0,
            "gActionIdsByTokenAddressCount should be 0"
        );
        assertEq(
            groupJoin.gAccountsByGroupIdCount(groupId1),
            0,
            "gAccountsByGroupIdCount should be 0"
        );
    }

    /// @notice Test _updateGlobalStateOnExit with multiple groups (user exits one)
    function test_updateGlobalStateOnExit_MultipleGroups_UserExitsOne() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount * 2, address(groupJoin));
        setupUser(user2, joinAmount, address(groupJoin));

        // Create second extension for groupId2
        ExtensionGroupAction groupAction2 = new ExtensionGroupAction(
            address(mockGroupActionFactory),
            address(token),
            address(token),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        uint256 actionId2 = 1;
        token.mint(address(this), 1e18);
        token.approve(address(mockGroupActionFactory), type(uint256).max);
        mockGroupActionFactory.registerExtensionForTesting(
            address(groupAction2),
            address(token)
        );

        prepareExtensionInit(address(groupAction2), address(token), actionId2);

        // Setup groupOwner2 with more tokens for second activation
        setupUser(
            groupOwner2,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        // Activate group2
        vm.prank(groupOwner2);
        groupManager.activateGroup(
            address(groupAction2),
            groupId2,
            "Group2",
            0,
            1e18,
            0,
            0
        );

        // User1 joins both groups
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // User1 needs more tokens for second join
        token.mint(user1, joinAmount);
        vm.prank(user1);
        token.approve(address(groupJoin), type(uint256).max);

        vm.prank(user1);
        groupJoin.join(
            address(groupAction2),
            groupId2,
            joinAmount,
            new string[](0)
        );

        // User2 joins group1
        vm.prank(user2);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // Verify initial state
        assertEq(groupJoin.gGroupIdsCount(), 2, "gGroupIdsCount should be 2");
        uint256[] memory user1GroupIds = groupJoin.gGroupIdsByAccount(user1);
        assertEq(user1GroupIds.length, 2, "user1 should have 2 groupIds");

        // User1 exits group1
        vm.prank(user1);
        groupJoin.exit(address(groupAction));

        // Verify user1 still has group2
        user1GroupIds = groupJoin.gGroupIdsByAccount(user1);
        assertEq(user1GroupIds.length, 1, "user1 should have 1 groupId");
        assertEq(user1GroupIds[0], groupId2, "user1 should have groupId2");

        // Verify groupId1 is still tracked (user2 still in it)
        assertEq(groupJoin.gGroupIdsCount(), 2, "gGroupIdsCount should be 2");
        assertTrue(
            _containsUint256(groupJoin.gGroupIds(), groupId1),
            "gGroupIds should still contain groupId1"
        );
        assertTrue(
            _containsUint256(groupJoin.gGroupIds(), groupId2),
            "gGroupIds should still contain groupId2"
        );

        // Verify actionId is still tracked (user2 still in group1)
        uint256[] memory actionIdsByToken = groupJoin
            .gActionIdsByTokenAddress(tokenAddress);
        assertEq(
            actionIdsByToken.length,
            2,
            "gActionIdsByTokenAddress should have 2 actionIds"
        );
        assertTrue(
            _containsUint256(actionIdsByToken, actionId),
            "gActionIdsByTokenAddress should still contain actionId"
        );
        assertTrue(
            _containsUint256(actionIdsByToken, actionId2),
            "gActionIdsByTokenAddress should still contain actionId2"
        );
    }

    // ============ Helper Functions ============

    function _verifyGlobalStateAfterJoin(
        address account,
        uint256 groupId,
        address tokenAddr,
        uint256 actId
    ) internal view {
        // Expected values
        uint256[] memory expectedGroupIds = new uint256[](1);
        expectedGroupIds[0] = groupId;

        address[] memory expectedTokenAddresses = new address[](1);
        expectedTokenAddresses[0] = tokenAddr;

        uint256[] memory expectedActionIds = new uint256[](1);
        expectedActionIds[0] = actId;

        address[] memory expectedAccounts = new address[](1);
        expectedAccounts[0] = account;

        // Verify gGroupIds
        assertArrayEq(
            groupJoin.gGroupIds(),
            expectedGroupIds,
            "gGroupIds mismatch"
        );
        assertEq(groupJoin.gGroupIdsCount(), 1, "gGroupIdsCount should be 1");

        // Verify gGroupIdsByAccount
        assertArrayEq(
            groupJoin.gGroupIdsByAccount(account),
            expectedGroupIds,
            "gGroupIdsByAccount mismatch"
        );
        assertEq(
            groupJoin.gGroupIdsByAccountCount(account),
            1,
            "gGroupIdsByAccountCount should be 1"
        );

        // Verify gGroupIdsByTokenAddress
        assertArrayEq(
            groupJoin.gGroupIdsByTokenAddress(tokenAddr),
            expectedGroupIds,
            "gGroupIdsByTokenAddress mismatch"
        );
        assertEq(
            groupJoin.gGroupIdsByTokenAddressCount(tokenAddr),
            1,
            "gGroupIdsByTokenAddressCount should be 1"
        );

        // Verify gGroupIdsByTokenAddressByAccount
        assertArrayEq(
            groupJoin.gGroupIdsByTokenAddressByAccount(tokenAddr, account),
            expectedGroupIds,
            "gGroupIdsByTokenAddressByAccount mismatch"
        );
        assertEq(
            groupJoin.gGroupIdsByTokenAddressByAccountCount(tokenAddr, account),
            1,
            "gGroupIdsByTokenAddressByAccountCount should be 1"
        );

        // Verify gTokenAddresses
        assertArrayEq(
            groupJoin.gTokenAddresses(),
            expectedTokenAddresses,
            "gTokenAddresses mismatch"
        );
        assertEq(
            groupJoin.gTokenAddressesCount(),
            1,
            "gTokenAddressesCount should be 1"
        );

        // Verify gTokenAddressesByAccount
        assertArrayEq(
            groupJoin.gTokenAddressesByAccount(account),
            expectedTokenAddresses,
            "gTokenAddressesByAccount mismatch"
        );
        assertEq(
            groupJoin.gTokenAddressesByAccountCount(account),
            1,
            "gTokenAddressesByAccountCount should be 1"
        );

        // Verify gTokenAddressesByGroupId
        assertArrayEq(
            groupJoin.gTokenAddressesByGroupId(groupId),
            expectedTokenAddresses,
            "gTokenAddressesByGroupId mismatch"
        );
        assertEq(
            groupJoin.gTokenAddressesByGroupIdCount(groupId),
            1,
            "gTokenAddressesByGroupIdCount should be 1"
        );

        // Verify gTokenAddressesByGroupIdByAccount
        assertArrayEq(
            groupJoin.gTokenAddressesByGroupIdByAccount(groupId, account),
            expectedTokenAddresses,
            "gTokenAddressesByGroupIdByAccount mismatch"
        );
        assertEq(
            groupJoin.gTokenAddressesByGroupIdByAccountCount(groupId, account),
            1,
            "gTokenAddressesByGroupIdByAccountCount should be 1"
        );

        // Verify gActionIdsByTokenAddress
        assertArrayEq(
            groupJoin.gActionIdsByTokenAddress(tokenAddr),
            expectedActionIds,
            "gActionIdsByTokenAddress mismatch"
        );
        assertEq(
            groupJoin.gActionIdsByTokenAddressCount(tokenAddr),
            1,
            "gActionIdsByTokenAddressCount should be 1"
        );

        // Verify gActionIdsByTokenAddressByAccount
        assertArrayEq(
            groupJoin.gActionIdsByTokenAddressByAccount(tokenAddr, account),
            expectedActionIds,
            "gActionIdsByTokenAddressByAccount mismatch"
        );
        assertEq(
            groupJoin.gActionIdsByTokenAddressByAccountCount(tokenAddr, account),
            1,
            "gActionIdsByTokenAddressByAccountCount should be 1"
        );

        // Verify gActionIdsByTokenAddressByGroupId
        assertArrayEq(
            groupJoin.gActionIdsByTokenAddressByGroupId(tokenAddr, groupId),
            expectedActionIds,
            "gActionIdsByTokenAddressByGroupId mismatch"
        );
        assertEq(
            groupJoin.gActionIdsByTokenAddressByGroupIdCount(tokenAddr, groupId),
            1,
            "gActionIdsByTokenAddressByGroupIdCount should be 1"
        );

        // Verify gActionIdsByTokenAddressByGroupIdByAccount
        assertArrayEq(
            groupJoin.gActionIdsByTokenAddressByGroupIdByAccount(
                tokenAddr,
                groupId,
                account
            ),
            expectedActionIds,
            "gActionIdsByTokenAddressByGroupIdByAccount mismatch"
        );
        assertEq(
            groupJoin.gActionIdsByTokenAddressByGroupIdByAccountCount(
                tokenAddr,
                groupId,
                account
            ),
            1,
            "gActionIdsByTokenAddressByGroupIdByAccountCount should be 1"
        );

        // Verify gAccounts
        assertArrayEq(
            groupJoin.gAccounts(),
            expectedAccounts,
            "gAccounts mismatch"
        );
        assertEq(groupJoin.gAccountsCount(), 1, "gAccountsCount should be 1");

        // Verify gAccountsByGroupId
        assertArrayEq(
            groupJoin.gAccountsByGroupId(groupId),
            expectedAccounts,
            "gAccountsByGroupId mismatch"
        );
        assertEq(
            groupJoin.gAccountsByGroupIdCount(groupId),
            1,
            "gAccountsByGroupIdCount should be 1"
        );

        // Verify gAccountsByTokenAddress
        assertArrayEq(
            groupJoin.gAccountsByTokenAddress(tokenAddr),
            expectedAccounts,
            "gAccountsByTokenAddress mismatch"
        );
        assertEq(
            groupJoin.gAccountsByTokenAddressCount(tokenAddr),
            1,
            "gAccountsByTokenAddressCount should be 1"
        );

        // Verify gAccountsByTokenAddressByGroupId
        assertArrayEq(
            groupJoin.gAccountsByTokenAddressByGroupId(tokenAddr, groupId),
            expectedAccounts,
            "gAccountsByTokenAddressByGroupId mismatch"
        );
        assertEq(
            groupJoin.gAccountsByTokenAddressByGroupIdCount(tokenAddr, groupId),
            1,
            "gAccountsByTokenAddressByGroupIdCount should be 1"
        );
    }

    function _containsAddress(
        address[] memory array,
        address target
    ) internal pure returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == target) {
                return true;
            }
        }
        return false;
    }

    function _containsUint256(
        uint256[] memory array,
        uint256 target
    ) internal pure returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == target) {
                return true;
            }
        }
        return false;
    }
}
