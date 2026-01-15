// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "./utils/BaseGroupTest.sol";
import {IGroupJoin} from "../src/interface/IGroupJoin.sol";
import {ExtensionGroupAction} from "../src/ExtensionGroupAction.sol";
import {MockExtensionGroupAction} from "./mocks/MockExtensionGroupAction.sol";
import {MockERC20} from "@extension/test/mocks/MockERC20.sol";

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
        uint256[] memory actionIdsByToken = groupJoin.gActionIdsByTokenAddress(
            tokenAddress
        );
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
        uint256[] memory actionIdsByToken = groupJoin.gActionIdsByTokenAddress(
            tokenAddress
        );
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

    // ============ totalJoinedAmountByGroupOwner Tests ============

    /// @notice Test totalJoinedAmountByGroupOwner returns 0 when no joins
    function test_totalJoinedAmountByGroupOwner_NoJoins() public view {
        uint256 amount = groupJoin.totalJoinedAmountByGroupOwner(
            address(groupAction),
            groupOwner1
        );
        assertEq(amount, 0, "Should return 0 when no joins");
    }

    /// @notice Test totalJoinedAmountByGroupOwner with single group and single user
    function test_totalJoinedAmountByGroupOwner_SingleGroupSingleUser() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));

        // User1 joins group1 (owned by groupOwner1)
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // Verify groupOwner1's total joined amount
        uint256 owner1Total = groupJoin.totalJoinedAmountByGroupOwner(
            address(groupAction),
            groupOwner1
        );
        assertEq(
            owner1Total,
            joinAmount,
            "Owner1 total should equal joinAmount"
        );

        // Verify groupOwner2's total joined amount is still 0
        uint256 owner2Total = groupJoin.totalJoinedAmountByGroupOwner(
            address(groupAction),
            groupOwner2
        );
        assertEq(owner2Total, 0, "Owner2 total should be 0");
    }

    /// @notice Test totalJoinedAmountByGroupOwner with single group and multiple users
    function test_totalJoinedAmountByGroupOwner_SingleGroupMultipleUsers()
        public
    {
        uint256 joinAmount1 = 10e18;
        uint256 joinAmount2 = 20e18;
        uint256 joinAmount3 = 15e18;
        uint256 expectedTotal = joinAmount1 + joinAmount2 + joinAmount3;

        setupUser(user1, joinAmount1, address(groupJoin));
        setupUser(user2, joinAmount2, address(groupJoin));
        setupUser(user3, joinAmount3, address(groupJoin));

        // All users join group1 (owned by groupOwner1)
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount1,
            new string[](0)
        );

        vm.prank(user2);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount2,
            new string[](0)
        );

        vm.prank(user3);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount3,
            new string[](0)
        );

        // Verify groupOwner1's total joined amount
        uint256 owner1Total = groupJoin.totalJoinedAmountByGroupOwner(
            address(groupAction),
            groupOwner1
        );
        assertEq(
            owner1Total,
            expectedTotal,
            "Owner1 total should equal sum of all join amounts"
        );
    }

    /// @notice Test totalJoinedAmountByGroupOwner with multiple groups owned by same owner
    function test_totalJoinedAmountByGroupOwner_MultipleGroupsSameOwner()
        public
    {
        uint256 joinAmount1 = 10e18;
        uint256 joinAmount2 = 20e18;
        uint256 expectedTotal = joinAmount1 + joinAmount2;

        // Create third group owned by groupOwner1
        uint256 groupId3 = setupGroupOwner(groupOwner1, 10000e18, "Group3");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1);
        groupManager.activateGroup(
            address(groupAction),
            groupId3,
            "Group3",
            0,
            1e18,
            0,
            0
        );

        setupUser(user1, joinAmount1, address(groupJoin));
        setupUser(user2, joinAmount2, address(groupJoin));

        // User1 joins group1
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount1,
            new string[](0)
        );

        // User2 joins group3 (also owned by groupOwner1)
        vm.prank(user2);
        groupJoin.join(
            address(groupAction),
            groupId3,
            joinAmount2,
            new string[](0)
        );

        // Verify groupOwner1's total joined amount (sum of group1 and group3)
        uint256 owner1Total = groupJoin.totalJoinedAmountByGroupOwner(
            address(groupAction),
            groupOwner1
        );
        assertEq(
            owner1Total,
            expectedTotal,
            "Owner1 total should equal sum of all groups"
        );
    }

    /// @notice Test totalJoinedAmountByGroupOwner with multiple groups owned by different owners
    function test_totalJoinedAmountByGroupOwner_MultipleGroupsDifferentOwners()
        public
    {
        uint256 joinAmount1 = 10e18;
        uint256 joinAmount2 = 20e18;

        setupUser(user1, joinAmount1, address(groupJoin));
        setupUser(user2, joinAmount2, address(groupJoin));

        // User1 joins group1 (owned by groupOwner1)
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount1,
            new string[](0)
        );

        // User2 joins group2 (owned by groupOwner2)
        vm.prank(user2);
        groupJoin.join(
            address(groupAction),
            groupId2,
            joinAmount2,
            new string[](0)
        );

        // Verify each owner's total
        uint256 owner1Total = groupJoin.totalJoinedAmountByGroupOwner(
            address(groupAction),
            groupOwner1
        );
        assertEq(
            owner1Total,
            joinAmount1,
            "Owner1 total should equal joinAmount1"
        );

        uint256 owner2Total = groupJoin.totalJoinedAmountByGroupOwner(
            address(groupAction),
            groupOwner2
        );
        assertEq(
            owner2Total,
            joinAmount2,
            "Owner2 total should equal joinAmount2"
        );
    }

    /// @notice Test totalJoinedAmountByGroupOwner decreases after exit
    function test_totalJoinedAmountByGroupOwner_AfterExit() public {
        uint256 joinAmount1 = 10e18;
        uint256 joinAmount2 = 20e18;
        uint256 expectedTotalBefore = joinAmount1 + joinAmount2;
        uint256 expectedTotalAfter = joinAmount2;

        setupUser(user1, joinAmount1, address(groupJoin));
        setupUser(user2, joinAmount2, address(groupJoin));

        // Both users join group1
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount1,
            new string[](0)
        );

        vm.prank(user2);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount2,
            new string[](0)
        );

        // Verify total before exit
        uint256 owner1TotalBefore = groupJoin.totalJoinedAmountByGroupOwner(
            address(groupAction),
            groupOwner1
        );
        assertEq(
            owner1TotalBefore,
            expectedTotalBefore,
            "Owner1 total before exit should equal sum"
        );

        // User1 exits
        vm.prank(user1);
        groupJoin.exit(address(groupAction));

        // Verify total after exit
        uint256 owner1TotalAfter = groupJoin.totalJoinedAmountByGroupOwner(
            address(groupAction),
            groupOwner1
        );
        assertEq(
            owner1TotalAfter,
            expectedTotalAfter,
            "Owner1 total after exit should decrease"
        );
    }

    /// @notice Test totalJoinedAmountByGroupOwner returns 0 after all users exit
    function test_totalJoinedAmountByGroupOwner_AllUsersExit() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));

        // User1 joins group1
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // Verify total before exit
        uint256 owner1TotalBefore = groupJoin.totalJoinedAmountByGroupOwner(
            address(groupAction),
            groupOwner1
        );
        assertEq(
            owner1TotalBefore,
            joinAmount,
            "Owner1 total should equal joinAmount"
        );

        // User1 exits
        vm.prank(user1);
        groupJoin.exit(address(groupAction));

        // Verify total after exit
        uint256 owner1TotalAfter = groupJoin.totalJoinedAmountByGroupOwner(
            address(groupAction),
            groupOwner1
        );
        assertEq(
            owner1TotalAfter,
            0,
            "Owner1 total should be 0 after all exit"
        );
    }

    /// @notice Test totalJoinedAmountByGroupOwner excludes deactivated group
    function test_totalJoinedAmountByGroupOwner_DeactivatedGroup() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));

        // User1 joins group1
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // Verify total before deactivation
        uint256 owner1TotalBefore = groupJoin.totalJoinedAmountByGroupOwner(
            address(groupAction),
            groupOwner1
        );
        assertEq(
            owner1TotalBefore,
            joinAmount,
            "Owner1 total should equal joinAmount"
        );

        // Advance to next round (required for deactivation)
        advanceRound();
        uint256 newRound = verify.currentRound();
        vote.setVotedActionIds(tokenAddress, newRound, actionId);
        vote.setVotesNum(tokenAddress, newRound, 10000e18);
        vote.setVotesNumByActionId(tokenAddress, newRound, actionId, 10000e18);

        // Deactivate group1
        vm.prank(groupOwner1);
        groupManager.deactivateGroup(address(groupAction), groupId1);

        // Verify total after deactivation (should exclude deactivated group)
        uint256 owner1TotalAfter = groupJoin.totalJoinedAmountByGroupOwner(
            address(groupAction),
            groupOwner1
        );
        assertEq(
            owner1TotalAfter,
            0,
            "Owner1 total should exclude deactivated group"
        );
    }

    // ============ gGroupIdsByTokenAddressByActionId Tests ============

    /// @notice Test gGroupIdsByTokenAddressByActionId with single groupId
    function test_gGroupIdsByTokenAddressByActionId_SingleGroupId() public {
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

        // Expected values
        uint256[] memory expectedGroupIds = new uint256[](1);
        expectedGroupIds[0] = groupId1;

        // Verify gGroupIdsByTokenAddressByActionId
        uint256[] memory groupIds = groupJoin.gGroupIdsByTokenAddressByActionId(
            tokenAddress,
            actionId
        );
        assertArrayEq(
            groupIds,
            expectedGroupIds,
            "gGroupIdsByTokenAddressByActionId should return groupId1"
        );

        // Verify gGroupIdsByTokenAddressByActionIdCount
        assertEq(
            groupJoin.gGroupIdsByTokenAddressByActionIdCount(
                tokenAddress,
                actionId
            ),
            1,
            "gGroupIdsByTokenAddressByActionIdCount should be 1"
        );

        // Verify gGroupIdsByTokenAddressByActionIdAtIndex
        assertEq(
            groupJoin.gGroupIdsByTokenAddressByActionIdAtIndex(
                tokenAddress,
                actionId,
                0
            ),
            groupId1,
            "gGroupIdsByTokenAddressByActionIdAtIndex should return groupId1"
        );
    }

    /// @notice Test gGroupIdsByTokenAddressByActionId with multiple groupIds
    function test_gGroupIdsByTokenAddressByActionId_MultipleGroupIds() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));
        setupUser(user2, joinAmount, address(groupJoin));

        // User1 joins groupId1
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // User2 joins groupId2
        vm.prank(user2);
        groupJoin.join(
            address(groupAction),
            groupId2,
            joinAmount,
            new string[](0)
        );

        // Expected values - both groupIds should be present
        uint256[] memory groupIds = groupJoin.gGroupIdsByTokenAddressByActionId(
            tokenAddress,
            actionId
        );
        assertEq(
            groupIds.length,
            2,
            "gGroupIdsByTokenAddressByActionId should have 2 groupIds"
        );
        assertTrue(
            _containsUint256(groupIds, groupId1),
            "gGroupIdsByTokenAddressByActionId should contain groupId1"
        );
        assertTrue(
            _containsUint256(groupIds, groupId2),
            "gGroupIdsByTokenAddressByActionId should contain groupId2"
        );

        // Verify count
        assertEq(
            groupJoin.gGroupIdsByTokenAddressByActionIdCount(
                tokenAddress,
                actionId
            ),
            2,
            "gGroupIdsByTokenAddressByActionIdCount should be 2"
        );

        // Verify atIndex - check both indices
        uint256 groupIdAtIndex0 = groupJoin
            .gGroupIdsByTokenAddressByActionIdAtIndex(
                tokenAddress,
                actionId,
                0
            );
        uint256 groupIdAtIndex1 = groupJoin
            .gGroupIdsByTokenAddressByActionIdAtIndex(
                tokenAddress,
                actionId,
                1
            );
        assertTrue(
            (groupIdAtIndex0 == groupId1 && groupIdAtIndex1 == groupId2) ||
                (groupIdAtIndex0 == groupId2 && groupIdAtIndex1 == groupId1),
            "gGroupIdsByTokenAddressByActionIdAtIndex should return correct groupIds"
        );
    }

    /// @notice Test gGroupIdsByTokenAddressByActionId with empty set
    function test_gGroupIdsByTokenAddressByActionId_EmptySet() public view {
        // Before any join, should return empty array
        uint256[] memory groupIds = groupJoin.gGroupIdsByTokenAddressByActionId(
            tokenAddress,
            actionId
        );
        assertEq(
            groupIds.length,
            0,
            "gGroupIdsByTokenAddressByActionId should return empty array"
        );

        // Verify count is 0
        assertEq(
            groupJoin.gGroupIdsByTokenAddressByActionIdCount(
                tokenAddress,
                actionId
            ),
            0,
            "gGroupIdsByTokenAddressByActionIdCount should be 0"
        );
    }

    /// @notice Test gGroupIdsByTokenAddressByActionId after exit
    function test_gGroupIdsByTokenAddressByActionId_AfterExit() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));
        setupUser(user2, joinAmount, address(groupJoin));

        // Both users join groupId1
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

        // Verify groupId1 is present
        assertEq(
            groupJoin.gGroupIdsByTokenAddressByActionIdCount(
                tokenAddress,
                actionId
            ),
            1,
            "gGroupIdsByTokenAddressByActionIdCount should be 1 before exit"
        );
        assertTrue(
            _containsUint256(
                groupJoin.gGroupIdsByTokenAddressByActionId(
                    tokenAddress,
                    actionId
                ),
                groupId1
            ),
            "gGroupIdsByTokenAddressByActionId should contain groupId1 before exit"
        );

        // User1 exits
        vm.prank(user1);
        groupJoin.exit(address(groupAction));

        // Verify groupId1 is still present (user2 still in it)
        assertEq(
            groupJoin.gGroupIdsByTokenAddressByActionIdCount(
                tokenAddress,
                actionId
            ),
            1,
            "gGroupIdsByTokenAddressByActionIdCount should still be 1 after user1 exit"
        );
        assertTrue(
            _containsUint256(
                groupJoin.gGroupIdsByTokenAddressByActionId(
                    tokenAddress,
                    actionId
                ),
                groupId1
            ),
            "gGroupIdsByTokenAddressByActionId should still contain groupId1 after user1 exit"
        );

        // User2 exits
        vm.prank(user2);
        groupJoin.exit(address(groupAction));

        // Verify groupId1 is removed (no users left)
        assertEq(
            groupJoin.gGroupIdsByTokenAddressByActionIdCount(
                tokenAddress,
                actionId
            ),
            0,
            "gGroupIdsByTokenAddressByActionIdCount should be 0 after all users exit"
        );
        assertEq(
            groupJoin
                .gGroupIdsByTokenAddressByActionId(tokenAddress, actionId)
                .length,
            0,
            "gGroupIdsByTokenAddressByActionId should return empty array after all users exit"
        );
    }

    /// @notice Test gGroupIdsByTokenAddressByActionId with different actionIds
    function test_gGroupIdsByTokenAddressByActionId_DifferentActionIds()
        public
    {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount * 2, address(groupJoin));

        // Create second extension with different actionId
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

        // User1 joins groupId1 with actionId
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

        // User1 joins groupId2 with actionId2
        vm.prank(user1);
        groupJoin.join(
            address(groupAction2),
            groupId2,
            joinAmount,
            new string[](0)
        );

        // Verify actionId has groupId1
        uint256[] memory groupIdsForActionId = groupJoin
            .gGroupIdsByTokenAddressByActionId(tokenAddress, actionId);
        assertEq(
            groupIdsForActionId.length,
            1,
            "gGroupIdsByTokenAddressByActionId for actionId should have 1 groupId"
        );
        assertEq(
            groupIdsForActionId[0],
            groupId1,
            "gGroupIdsByTokenAddressByActionId for actionId should contain groupId1"
        );

        // Verify actionId2 has groupId2
        uint256[] memory groupIdsForActionId2 = groupJoin
            .gGroupIdsByTokenAddressByActionId(tokenAddress, actionId2);
        assertEq(
            groupIdsForActionId2.length,
            1,
            "gGroupIdsByTokenAddressByActionId for actionId2 should have 1 groupId"
        );
        assertEq(
            groupIdsForActionId2[0],
            groupId2,
            "gGroupIdsByTokenAddressByActionId for actionId2 should contain groupId2"
        );

        // Verify counts
        assertEq(
            groupJoin.gGroupIdsByTokenAddressByActionIdCount(
                tokenAddress,
                actionId
            ),
            1,
            "gGroupIdsByTokenAddressByActionIdCount for actionId should be 1"
        );
        assertEq(
            groupJoin.gGroupIdsByTokenAddressByActionIdCount(
                tokenAddress,
                actionId2
            ),
            1,
            "gGroupIdsByTokenAddressByActionIdCount for actionId2 should be 1"
        );
    }

    // ============ AtIndex Functions Tests ============

    /// @notice Test gGroupIdsByAccountAtIndex with multiple groupIds
    function test_gGroupIdsByAccountAtIndex_MultipleGroupIds() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount * 2, address(groupJoin));

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

        setupUser(
            groupOwner2,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

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

        // User1 joins groupId1
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // User1 joins groupId2
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

        // Verify gGroupIdsByAccountAtIndex
        uint256[] memory groupIds = groupJoin.gGroupIdsByAccount(user1);
        assertEq(groupIds.length, 2, "user1 should have 2 groupIds");

        uint256 groupIdAtIndex0 = groupJoin.gGroupIdsByAccountAtIndex(user1, 0);
        uint256 groupIdAtIndex1 = groupJoin.gGroupIdsByAccountAtIndex(user1, 1);

        assertTrue(
            (groupIdAtIndex0 == groupId1 && groupIdAtIndex1 == groupId2) ||
                (groupIdAtIndex0 == groupId2 && groupIdAtIndex1 == groupId1),
            "gGroupIdsByAccountAtIndex should return correct groupIds"
        );

        // Verify consistency with values()
        assertTrue(
            _containsUint256(groupIds, groupIdAtIndex0),
            "gGroupIdsByAccountAtIndex[0] should be in values"
        );
        assertTrue(
            _containsUint256(groupIds, groupIdAtIndex1),
            "gGroupIdsByAccountAtIndex[1] should be in values"
        );
    }

    /// @notice Test gGroupIdsByTokenAddressAtIndex with multiple groupIds
    function test_gGroupIdsByTokenAddressAtIndex_MultipleGroupIds() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));
        setupUser(user2, joinAmount, address(groupJoin));

        // User1 joins groupId1
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // User2 joins groupId2
        vm.prank(user2);
        groupJoin.join(
            address(groupAction),
            groupId2,
            joinAmount,
            new string[](0)
        );

        // Verify gGroupIdsByTokenAddressAtIndex
        uint256[] memory groupIds = groupJoin.gGroupIdsByTokenAddress(
            tokenAddress
        );
        assertEq(groupIds.length, 2, "should have 2 groupIds");

        uint256 groupIdAtIndex0 = groupJoin.gGroupIdsByTokenAddressAtIndex(
            tokenAddress,
            0
        );
        uint256 groupIdAtIndex1 = groupJoin.gGroupIdsByTokenAddressAtIndex(
            tokenAddress,
            1
        );

        assertTrue(
            (groupIdAtIndex0 == groupId1 && groupIdAtIndex1 == groupId2) ||
                (groupIdAtIndex0 == groupId2 && groupIdAtIndex1 == groupId1),
            "gGroupIdsByTokenAddressAtIndex should return correct groupIds"
        );
    }

    /// @notice Test gGroupIdsByTokenAddressByAccountAtIndex with multiple groupIds
    function test_gGroupIdsByTokenAddressByAccountAtIndex_MultipleGroupIds()
        public
    {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount * 2, address(groupJoin));

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

        setupUser(
            groupOwner2,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

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

        // User1 joins groupId1
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // User1 joins groupId2
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

        // Verify gGroupIdsByTokenAddressByAccountAtIndex
        uint256[] memory groupIds = groupJoin.gGroupIdsByTokenAddressByAccount(
            tokenAddress,
            user1
        );
        assertEq(groupIds.length, 2, "should have 2 groupIds");

        uint256 groupIdAtIndex0 = groupJoin
            .gGroupIdsByTokenAddressByAccountAtIndex(tokenAddress, user1, 0);
        uint256 groupIdAtIndex1 = groupJoin
            .gGroupIdsByTokenAddressByAccountAtIndex(tokenAddress, user1, 1);

        assertTrue(
            (groupIdAtIndex0 == groupId1 && groupIdAtIndex1 == groupId2) ||
                (groupIdAtIndex0 == groupId2 && groupIdAtIndex1 == groupId1),
            "gGroupIdsByTokenAddressByAccountAtIndex should return correct groupIds"
        );
    }

    /// @notice Test gTokenAddressesByAccountAtIndex with multiple tokenAddresses
    function test_gTokenAddressesByAccountAtIndex_MultipleTokenAddresses()
        public
    {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount * 2, address(groupJoin));

        // Create second token and extension
        MockERC20 token2 = new MockERC20();
        ExtensionGroupAction groupAction2 = new ExtensionGroupAction(
            address(mockGroupActionFactory),
            address(token2),
            address(token2),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        uint256 actionId2 = 1;
        token2.mint(address(this), 1e18);
        token2.approve(address(mockGroupActionFactory), type(uint256).max);
        mockGroupActionFactory.registerExtensionForTesting(
            address(groupAction2),
            address(token2)
        );

        prepareExtensionInit(address(groupAction2), address(token2), actionId2);

        // Setup governance votes for token2
        stake.setGovVotesNum(address(token2), 10000e18);
        stake.setValidGovVotes(address(token2), groupOwner2, 10000e18);

        // Create new groupId for groupAction2
        uint256 groupId3 = setupGroupOwner(groupOwner2, 10000e18, "Group3");
        token2.mint(groupOwner2, GROUP_ACTIVATION_STAKE_AMOUNT);
        vm.prank(groupOwner2);
        token2.approve(address(groupManager), type(uint256).max);

        vm.prank(groupOwner2);
        groupManager.activateGroup(
            address(groupAction2),
            groupId3,
            "Group3",
            0,
            1e18,
            0,
            0
        );

        // User1 joins with tokenAddress
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // User1 joins with token2
        token2.mint(user1, joinAmount);
        vm.prank(user1);
        token2.approve(address(groupJoin), type(uint256).max);

        vm.prank(user1);
        groupJoin.join(
            address(groupAction2),
            groupId3,
            joinAmount,
            new string[](0)
        );

        // Verify gTokenAddressesByAccountAtIndex
        address[] memory tokenAddresses = groupJoin.gTokenAddressesByAccount(
            user1
        );
        assertEq(tokenAddresses.length, 2, "should have 2 tokenAddresses");

        address tokenAddressAtIndex0 = groupJoin
            .gTokenAddressesByAccountAtIndex(user1, 0);
        address tokenAddressAtIndex1 = groupJoin
            .gTokenAddressesByAccountAtIndex(user1, 1);

        assertTrue(
            (tokenAddressAtIndex0 == tokenAddress &&
                tokenAddressAtIndex1 == address(token2)) ||
                (tokenAddressAtIndex0 == address(token2) &&
                    tokenAddressAtIndex1 == tokenAddress),
            "gTokenAddressesByAccountAtIndex should return correct tokenAddresses"
        );
    }

    /// @notice Test gTokenAddressesByGroupIdAtIndex with multiple tokenAddresses
    function test_gTokenAddressesByGroupIdAtIndex_MultipleTokenAddresses()
        public
    {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));
        setupUser(user2, joinAmount, address(groupJoin));

        // Create second token and extension
        MockERC20 token2 = new MockERC20();
        ExtensionGroupAction groupAction2 = new ExtensionGroupAction(
            address(mockGroupActionFactory),
            address(token2),
            address(token2),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        uint256 actionId2 = 1;
        token2.mint(address(this), 1e18);
        token2.approve(address(mockGroupActionFactory), type(uint256).max);
        mockGroupActionFactory.registerExtensionForTesting(
            address(groupAction2),
            address(token2)
        );

        prepareExtensionInit(address(groupAction2), address(token2), actionId2);

        // Setup governance votes for token2
        stake.setGovVotesNum(address(token2), 10000e18);
        stake.setValidGovVotes(address(token2), groupOwner1, 10000e18);
        token2.mint(groupOwner1, GROUP_ACTIVATION_STAKE_AMOUNT);
        vm.prank(groupOwner1);
        token2.approve(address(groupManager), type(uint256).max);

        vm.prank(groupOwner1);
        groupManager.activateGroup(
            address(groupAction2),
            groupId1,
            "Group1",
            0,
            1e18,
            0,
            0
        );

        // User1 joins groupId1 with tokenAddress
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // User2 joins groupId1 with token2
        token2.mint(user2, joinAmount);
        vm.prank(user2);
        token2.approve(address(groupJoin), type(uint256).max);

        vm.prank(user2);
        groupJoin.join(
            address(groupAction2),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // Verify gTokenAddressesByGroupIdAtIndex
        address[] memory tokenAddresses = groupJoin.gTokenAddressesByGroupId(
            groupId1
        );
        assertEq(tokenAddresses.length, 2, "should have 2 tokenAddresses");

        address tokenAddressAtIndex0 = groupJoin
            .gTokenAddressesByGroupIdAtIndex(groupId1, 0);
        address tokenAddressAtIndex1 = groupJoin
            .gTokenAddressesByGroupIdAtIndex(groupId1, 1);

        assertTrue(
            (tokenAddressAtIndex0 == tokenAddress &&
                tokenAddressAtIndex1 == address(token2)) ||
                (tokenAddressAtIndex0 == address(token2) &&
                    tokenAddressAtIndex1 == tokenAddress),
            "gTokenAddressesByGroupIdAtIndex should return correct tokenAddresses"
        );
    }

    /// @notice Test gTokenAddressesByGroupIdByAccountAtIndex with single tokenAddress
    function test_gTokenAddressesByGroupIdByAccountAtIndex_SingleTokenAddress()
        public
    {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));

        // User1 joins groupId1
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // Verify gTokenAddressesByGroupIdByAccountAtIndex
        address[] memory tokenAddresses = groupJoin
            .gTokenAddressesByGroupIdByAccount(groupId1, user1);
        assertEq(tokenAddresses.length, 1, "should have 1 tokenAddress");

        address tokenAddressAtIndex0 = groupJoin
            .gTokenAddressesByGroupIdByAccountAtIndex(groupId1, user1, 0);

        assertEq(
            tokenAddressAtIndex0,
            tokenAddress,
            "gTokenAddressesByGroupIdByAccountAtIndex should return correct tokenAddress"
        );
    }

    /// @notice Test gActionIdsByTokenAddressAtIndex with multiple actionIds
    function test_gActionIdsByTokenAddressAtIndex_MultipleActionIds() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount * 2, address(groupJoin));

        // Create second extension with different actionId
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

        setupUser(
            groupOwner2,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

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

        // User1 joins with actionId
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // User1 joins with actionId2
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

        // Verify gActionIdsByTokenAddressAtIndex
        uint256[] memory actionIds = groupJoin.gActionIdsByTokenAddress(
            tokenAddress
        );
        assertEq(actionIds.length, 2, "should have 2 actionIds");

        uint256 actionIdAtIndex0 = groupJoin.gActionIdsByTokenAddressAtIndex(
            tokenAddress,
            0
        );
        uint256 actionIdAtIndex1 = groupJoin.gActionIdsByTokenAddressAtIndex(
            tokenAddress,
            1
        );

        assertTrue(
            (actionIdAtIndex0 == actionId && actionIdAtIndex1 == actionId2) ||
                (actionIdAtIndex0 == actionId2 && actionIdAtIndex1 == actionId),
            "gActionIdsByTokenAddressAtIndex should return correct actionIds"
        );
    }

    /// @notice Test gActionIdsByTokenAddressByAccountAtIndex with multiple actionIds
    function test_gActionIdsByTokenAddressByAccountAtIndex_MultipleActionIds()
        public
    {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount * 2, address(groupJoin));

        // Create second extension with different actionId
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

        setupUser(
            groupOwner2,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

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

        // User1 joins with actionId
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // User1 joins with actionId2
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

        // Verify gActionIdsByTokenAddressByAccountAtIndex
        uint256[] memory actionIds = groupJoin
            .gActionIdsByTokenAddressByAccount(tokenAddress, user1);
        assertEq(actionIds.length, 2, "should have 2 actionIds");

        uint256 actionIdAtIndex0 = groupJoin
            .gActionIdsByTokenAddressByAccountAtIndex(tokenAddress, user1, 0);
        uint256 actionIdAtIndex1 = groupJoin
            .gActionIdsByTokenAddressByAccountAtIndex(tokenAddress, user1, 1);

        assertTrue(
            (actionIdAtIndex0 == actionId && actionIdAtIndex1 == actionId2) ||
                (actionIdAtIndex0 == actionId2 && actionIdAtIndex1 == actionId),
            "gActionIdsByTokenAddressByAccountAtIndex should return correct actionIds"
        );
    }

    /// @notice Test gActionIdsByTokenAddressByGroupIdAtIndex with multiple actionIds
    function test_gActionIdsByTokenAddressByGroupIdAtIndex_MultipleActionIds()
        public
    {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount * 2, address(groupJoin));

        // Create second extension with different actionId
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

        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1);
        groupManager.activateGroup(
            address(groupAction2),
            groupId1,
            "Group1",
            0,
            1e18,
            0,
            0
        );

        // User1 joins groupId1 with actionId
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // User1 joins groupId1 with actionId2
        token.mint(user1, joinAmount);
        vm.prank(user1);
        token.approve(address(groupJoin), type(uint256).max);

        vm.prank(user1);
        groupJoin.join(
            address(groupAction2),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // Verify gActionIdsByTokenAddressByGroupIdAtIndex
        uint256[] memory actionIds = groupJoin
            .gActionIdsByTokenAddressByGroupId(tokenAddress, groupId1);
        assertEq(actionIds.length, 2, "should have 2 actionIds");

        uint256 actionIdAtIndex0 = groupJoin
            .gActionIdsByTokenAddressByGroupIdAtIndex(
                tokenAddress,
                groupId1,
                0
            );
        uint256 actionIdAtIndex1 = groupJoin
            .gActionIdsByTokenAddressByGroupIdAtIndex(
                tokenAddress,
                groupId1,
                1
            );

        assertTrue(
            (actionIdAtIndex0 == actionId && actionIdAtIndex1 == actionId2) ||
                (actionIdAtIndex0 == actionId2 && actionIdAtIndex1 == actionId),
            "gActionIdsByTokenAddressByGroupIdAtIndex should return correct actionIds"
        );
    }

    /// @notice Test gActionIdsByTokenAddressByGroupIdByAccountAtIndex with multiple actionIds
    function test_gActionIdsByTokenAddressByGroupIdByAccountAtIndex_MultipleActionIds()
        public
    {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount * 2, address(groupJoin));

        // Create second extension with different actionId
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

        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1);
        groupManager.activateGroup(
            address(groupAction2),
            groupId1,
            "Group1",
            0,
            1e18,
            0,
            0
        );

        // User1 joins groupId1 with actionId
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // User1 joins groupId1 with actionId2
        token.mint(user1, joinAmount);
        vm.prank(user1);
        token.approve(address(groupJoin), type(uint256).max);

        vm.prank(user1);
        groupJoin.join(
            address(groupAction2),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // Verify gActionIdsByTokenAddressByGroupIdByAccountAtIndex
        uint256[] memory actionIds = groupJoin
            .gActionIdsByTokenAddressByGroupIdByAccount(
                tokenAddress,
                groupId1,
                user1
            );
        assertEq(actionIds.length, 2, "should have 2 actionIds");

        uint256 actionIdAtIndex0 = groupJoin
            .gActionIdsByTokenAddressByGroupIdByAccountAtIndex(
                tokenAddress,
                groupId1,
                user1,
                0
            );
        uint256 actionIdAtIndex1 = groupJoin
            .gActionIdsByTokenAddressByGroupIdByAccountAtIndex(
                tokenAddress,
                groupId1,
                user1,
                1
            );

        assertTrue(
            (actionIdAtIndex0 == actionId && actionIdAtIndex1 == actionId2) ||
                (actionIdAtIndex0 == actionId2 && actionIdAtIndex1 == actionId),
            "gActionIdsByTokenAddressByGroupIdByAccountAtIndex should return correct actionIds"
        );
    }

    /// @notice Test gAccountsAtIndex with multiple accounts
    function test_gAccountsAtIndex_MultipleAccounts() public {
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

        // Verify gAccountsAtIndex
        address[] memory accounts = groupJoin.gAccounts();
        assertEq(accounts.length, 3, "should have 3 accounts");

        address accountAtIndex0 = groupJoin.gAccountsAtIndex(0);
        address accountAtIndex1 = groupJoin.gAccountsAtIndex(1);
        address accountAtIndex2 = groupJoin.gAccountsAtIndex(2);

        assertTrue(
            _containsAddress(accounts, accountAtIndex0),
            "gAccountsAtIndex[0] should be in values"
        );
        assertTrue(
            _containsAddress(accounts, accountAtIndex1),
            "gAccountsAtIndex[1] should be in values"
        );
        assertTrue(
            _containsAddress(accounts, accountAtIndex2),
            "gAccountsAtIndex[2] should be in values"
        );

        // Verify all three accounts are present
        assertTrue(
            _containsAddress(accounts, user1) &&
                _containsAddress(accounts, user2) &&
                _containsAddress(accounts, user3),
            "gAccounts should contain all three users"
        );
    }

    /// @notice Test gAccountsByGroupIdAtIndex with multiple accounts
    function test_gAccountsByGroupIdAtIndex_MultipleAccounts() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));
        setupUser(user2, joinAmount, address(groupJoin));
        setupUser(user3, joinAmount, address(groupJoin));

        // All users join groupId1
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

        // Verify gAccountsByGroupIdAtIndex
        address[] memory accounts = groupJoin.gAccountsByGroupId(groupId1);
        assertEq(accounts.length, 3, "should have 3 accounts");

        address accountAtIndex0 = groupJoin.gAccountsByGroupIdAtIndex(
            groupId1,
            0
        );
        address accountAtIndex1 = groupJoin.gAccountsByGroupIdAtIndex(
            groupId1,
            1
        );
        address accountAtIndex2 = groupJoin.gAccountsByGroupIdAtIndex(
            groupId1,
            2
        );

        assertTrue(
            _containsAddress(accounts, accountAtIndex0),
            "gAccountsByGroupIdAtIndex[0] should be in values"
        );
        assertTrue(
            _containsAddress(accounts, accountAtIndex1),
            "gAccountsByGroupIdAtIndex[1] should be in values"
        );
        assertTrue(
            _containsAddress(accounts, accountAtIndex2),
            "gAccountsByGroupIdAtIndex[2] should be in values"
        );
    }

    /// @notice Test gAccountsByTokenAddressAtIndex with multiple accounts
    function test_gAccountsByTokenAddressAtIndex_MultipleAccounts() public {
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

        // Verify gAccountsByTokenAddressAtIndex
        address[] memory accounts = groupJoin.gAccountsByTokenAddress(
            tokenAddress
        );
        assertEq(accounts.length, 3, "should have 3 accounts");

        address accountAtIndex0 = groupJoin.gAccountsByTokenAddressAtIndex(
            tokenAddress,
            0
        );
        address accountAtIndex1 = groupJoin.gAccountsByTokenAddressAtIndex(
            tokenAddress,
            1
        );
        address accountAtIndex2 = groupJoin.gAccountsByTokenAddressAtIndex(
            tokenAddress,
            2
        );

        assertTrue(
            _containsAddress(accounts, accountAtIndex0),
            "gAccountsByTokenAddressAtIndex[0] should be in values"
        );
        assertTrue(
            _containsAddress(accounts, accountAtIndex1),
            "gAccountsByTokenAddressAtIndex[1] should be in values"
        );
        assertTrue(
            _containsAddress(accounts, accountAtIndex2),
            "gAccountsByTokenAddressAtIndex[2] should be in values"
        );
    }

    /// @notice Test gAccountsByTokenAddressByGroupIdAtIndex with multiple accounts
    function test_gAccountsByTokenAddressByGroupIdAtIndex_MultipleAccounts()
        public
    {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));
        setupUser(user2, joinAmount, address(groupJoin));
        setupUser(user3, joinAmount, address(groupJoin));

        // All users join groupId1
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

        // Verify gAccountsByTokenAddressByGroupIdAtIndex
        address[] memory accounts = groupJoin.gAccountsByTokenAddressByGroupId(
            tokenAddress,
            groupId1
        );
        assertEq(accounts.length, 3, "should have 3 accounts");

        address accountAtIndex0 = groupJoin
            .gAccountsByTokenAddressByGroupIdAtIndex(tokenAddress, groupId1, 0);
        address accountAtIndex1 = groupJoin
            .gAccountsByTokenAddressByGroupIdAtIndex(tokenAddress, groupId1, 1);
        address accountAtIndex2 = groupJoin
            .gAccountsByTokenAddressByGroupIdAtIndex(tokenAddress, groupId1, 2);

        assertTrue(
            _containsAddress(accounts, accountAtIndex0),
            "gAccountsByTokenAddressByGroupIdAtIndex[0] should be in values"
        );
        assertTrue(
            _containsAddress(accounts, accountAtIndex1),
            "gAccountsByTokenAddressByGroupIdAtIndex[1] should be in values"
        );
        assertTrue(
            _containsAddress(accounts, accountAtIndex2),
            "gAccountsByTokenAddressByGroupIdAtIndex[2] should be in values"
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
            groupJoin.gActionIdsByTokenAddressByAccountCount(
                tokenAddr,
                account
            ),
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
            groupJoin.gActionIdsByTokenAddressByGroupIdCount(
                tokenAddr,
                groupId
            ),
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
