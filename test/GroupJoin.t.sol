// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "./utils/BaseGroupTest.sol";
import {IGroupJoinEvents} from "../src/interface/IGroupJoin.sol";
import {IGroupJoinErrors} from "../src/interface/IGroupJoin.sol";
import {ExtensionGroupAction} from "../src/ExtensionGroupAction.sol";
import {IGroupJoin} from "../src/interface/IGroupJoin.sol";
import {MockGroupToken} from "./mocks/MockGroupToken.sol";

/**
 * @title GroupJoinTest
 * @notice Comprehensive test suite for GroupJoin contract
 * @dev Tests cover join/exit functionality, trial joins, round history, and error cases
 */
contract GroupJoinTest is BaseGroupTest, IGroupJoinEvents {
    ExtensionGroupAction public groupAction;
    uint256 public groupId1;
    uint256 public groupId2;

    // ============ Setup ============

    function setUp() public {
        setUpBase();

        groupAction = new ExtensionGroupAction(
            address(mockGroupActionFactory),
            address(token),
            address(token),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        token.mint(address(this), 1e18);
        token.approve(address(mockGroupActionFactory), type(uint256).max);
        mockGroupActionFactory.registerExtensionForTesting(
            address(groupAction),
            address(token)
        );

        prepareExtensionInit(address(groupAction), address(token), ACTION_ID);

        groupId1 = setupGroupOwner(groupOwner1, 10000e18, "Group1");
        groupId2 = setupGroupOwner(groupOwner2, 10000e18, "Group2");

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

    // ============ accountIndexByGroupIdByRound Tests ============

    /// @notice Test: accountIndexByGroupIdByRound returns correct index values
    /// @dev Verifies that the function correctly returns found status and index for accounts
    function test_accountIndexByGroupIdByRound_WithValidAccounts_ReturnsCorrectValues()
        public
    {
        address[] memory users = new address[](3);
        uint256[] memory joinAmounts = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            users[i] = address(uint160(0x200 + i));
            joinAmounts[i] = (i + 1) * 10e18;
            setupUser(users[i], joinAmounts[i], address(groupJoin));

            vm.prank(users[i]);
            groupJoin.join(
                address(groupAction),
                groupId1,
                joinAmounts[i],
                new string[](0)
            );
        }

        uint256 round = verify.currentRound();
        address nonMember = address(0x999);

        (bool found0, uint256 index0) = groupJoin.accountIndexByGroupIdByRound(
            address(groupAction),
            groupId1,
            users[0],
            round
        );
        assertTrue(found0, "User 0 should be found");
        assertEq(index0, 0, "User 0 should be at index 0");

        (bool found2, uint256 index2) = groupJoin.accountIndexByGroupIdByRound(
            address(groupAction),
            groupId1,
            users[2],
            round
        );
        assertTrue(found2, "User 2 should be found");
        assertEq(index2, 2, "User 2 should be at index 2");

        (bool foundNonMember, ) = groupJoin.accountIndexByGroupIdByRound(
            address(groupAction),
            groupId1,
            nonMember,
            round
        );
        assertFalse(foundNonMember, "Non-member should not be found");
    }

    // ============ join Tests ============

    // Error Cases

    /// @notice Test: join with zero amount should revert
    /// @dev Boundary condition: zero value should trigger JoinAmountZero error
    function test_join_WithZeroAmount_Reverts() public {
        setupUser(user1, 1e18, address(groupJoin));
        uint256 joinAmount = 0;

        vm.prank(user1);
        vm.expectRevert(IGroupJoinErrors.JoinAmountZero.selector);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );
    }

    // Success Cases

    /// @notice Test: join with minimum valid amount succeeds
    /// @dev Boundary condition: minimum amount should be accepted
    function test_join_WithMinimumAmount_Succeeds() public {
        uint256 minJoinAmount = 1e18;
        vm.prank(groupOwner1);
        groupManager.updateGroupInfo(
            address(groupAction),
            groupId1,
            "Group1",
            0,
            minJoinAmount,
            0,
            0
        );

        setupUser(user1, minJoinAmount, address(groupJoin));

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            minJoinAmount,
            new string[](0)
        );

        (uint256 joinedRound, uint256 amount, , ) = groupJoin.joinInfoByRound(
            address(groupAction),
            join.currentRound(),
            user1
        );
        assertTrue(joinedRound > 0, "Should be joined");
        assertEq(amount, minJoinAmount, "Amount should match minimum");
    }

    /// @notice Test: join with maximum valid amount succeeds
    /// @dev Boundary condition: maximum amount should be accepted
    function test_join_WithMaximumAmount_Succeeds() public {
        uint256 maxJoinAmount = 100e18;
        vm.prank(groupOwner1);
        groupManager.updateGroupInfo(
            address(groupAction),
            groupId1,
            "Group1",
            0,
            1e18,
            maxJoinAmount,
            0
        );

        setupUser(user1, maxJoinAmount, address(groupJoin));

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            maxJoinAmount,
            new string[](0)
        );

        (uint256 joinedRound, uint256 amount, , ) = groupJoin.joinInfoByRound(
            address(groupAction),
            join.currentRound(),
            user1
        );
        assertTrue(joinedRound > 0, "Should be joined");
        assertEq(amount, maxJoinAmount, "Amount should match maximum");
    }

    /// @notice Test: join when already in another group should revert
    /// @dev State validation: user cannot join multiple groups simultaneously
    function test_join_WhenAlreadyInOtherGroup_Reverts() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount * 2, address(groupJoin));

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        vm.prank(user1);
        vm.expectRevert(IGroupJoinErrors.AlreadyInOtherGroup.selector);
        groupJoin.join(
            address(groupAction),
            groupId2,
            joinAmount,
            new string[](0)
        );
    }

    /// @notice Test: join to deactivated group should revert
    /// @dev State validation: cannot join inactive groups
    function test_join_ToDeactivatedGroup_Reverts() public {
        advanceRound();
        vm.prank(groupOwner1);
        groupManager.deactivateGroup(address(groupAction), groupId1);

        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));

        vm.prank(user1);
        vm.expectRevert(IGroupJoinErrors.CannotJoinInactiveGroup.selector);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );
    }

    /// @notice Test: join with amount below minimum should revert
    /// @dev Boundary condition: amount validation against group minimum
    function test_join_WithAmountBelowMinimum_Reverts() public {
        uint256 minJoinAmount = 10e18;
        uint256 joinAmount = minJoinAmount - 1;

        vm.prank(groupOwner1);
        groupManager.updateGroupInfo(
            address(groupAction),
            groupId1,
            "Group1",
            0,
            minJoinAmount,
            0,
            0
        );

        setupUser(user1, joinAmount, address(groupJoin));

        vm.prank(user1);
        vm.expectRevert(IGroupJoinErrors.AmountBelowMinimum.selector);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );
    }

    /// @notice Test: join with amount exceeding group max should revert
    /// @dev Boundary condition: amount validation against group maximum
    function test_join_WithAmountExceedingGroupMax_Reverts() public {
        uint256 maxJoinAmount = 10e18;
        uint256 joinAmount = maxJoinAmount + 1;

        vm.prank(groupOwner1);
        groupManager.updateGroupInfo(
            address(groupAction),
            groupId1,
            "Group1",
            0,
            1e18,
            maxJoinAmount,
            0
        );

        setupUser(user1, joinAmount, address(groupJoin));

        vm.prank(user1);
        vm.expectRevert(IGroupJoinErrors.ExceedsGroupMaxJoinAmount.selector);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );
    }

    /// @notice Test: join when group accounts are full should revert
    /// @dev Capacity validation: maxAccounts limit enforcement
    function test_join_WhenGroupAccountsFull_Reverts() public {
        uint256 maxAccounts = 1;
        uint256 joinAmount = 10e18;

        vm.prank(groupOwner1);
        groupManager.updateGroupInfo(
            address(groupAction),
            groupId1,
            "Group1",
            0,
            1e18,
            0,
            maxAccounts
        );

        setupUser(user1, joinAmount, address(groupJoin));
        setupUser(user2, joinAmount, address(groupJoin));

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        vm.prank(user2);
        vm.expectRevert(IGroupJoinErrors.GroupAccountsFull.selector);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );
    }

    /// @notice Test: join when group capacity is exceeded should revert
    /// @dev Capacity validation: maxCapacity limit enforcement
    function test_join_WhenGroupCapacityExceeded_Reverts() public {
        uint256 maxCapacity = 15e18;
        uint256 joinAmount1 = 10e18;
        uint256 joinAmount2 = 10e18;

        vm.prank(groupOwner1);
        groupManager.updateGroupInfo(
            address(groupAction),
            groupId1,
            "Group1",
            maxCapacity,
            1e18,
            0,
            0
        );

        setupUser(user1, joinAmount1, address(groupJoin));
        setupUser(user2, joinAmount2, address(groupJoin));

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount1,
            new string[](0)
        );

        vm.prank(user2);
        vm.expectRevert(IGroupJoinErrors.GroupCapacityExceeded.selector);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount2,
            new string[](0)
        );
    }

    /// @notice Test: join with amount exactly at maxCapacity boundary succeeds
    /// @dev Capacity validation: amount == maxCapacity when group is empty is accepted
    function test_join_AmountExactlyAtMaxCapacity_Succeeds() public {
        uint256 maxCapacity = 10e18;
        uint256 joinAmount = maxCapacity;

        vm.prank(groupOwner1);
        groupManager.updateGroupInfo(
            address(groupAction),
            groupId1,
            "Group1",
            maxCapacity,
            1e18,
            0,
            0
        );

        setupUser(user1, joinAmount, address(groupJoin));

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        assertEq(
            groupJoin.totalJoinedAmountByGroupIdByRound(
                address(groupAction),
                join.currentRound(),
                groupId1
            ),
            maxCapacity,
            "total joined should equal maxCapacity"
        );
        (uint256 joinedRound, uint256 amount, , ) = groupJoin.joinInfoByRound(
            address(groupAction),
            join.currentRound(),
            user1
        );
        assertTrue(joinedRound > 0, "should be joined");
        assertEq(amount, joinAmount, "amount should match");
    }

    /// @notice Test: join when owner capacity is exceeded should revert
    /// @dev Capacity validation: owner's verify capacity limit enforcement
    function test_join_WhenOwnerCapacityExceeded_Reverts() public {
        stake.setValidGovVotes(address(token), groupOwner1, 1);

        uint256 ownerMaxCapacity = groupManager.maxVerifyCapacityByOwner(
            address(groupAction),
            groupOwner1
        );
        uint256 joinAmount = ownerMaxCapacity + 1;

        vm.prank(groupOwner1);
        groupManager.updateGroupInfo(
            address(groupAction),
            groupId1,
            "Group1",
            0,
            1,
            0,
            0
        );

        setupUser(user1, joinAmount, address(groupJoin));

        vm.prank(user1);
        vm.expectRevert(IGroupJoinErrors.OwnerCapacityExceeded.selector);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );
    }

    /// @notice Test: join when extension account cap is exceeded should revert
    /// @dev Capacity validation: extension-level max join amount limit
    function test_join_WhenExtensionAccountCapExceeded_Reverts() public {
        uint256 totalGovVotes = stake.govVotesNum(address(token));
        stake.setValidGovVotes(address(token), groupOwner1, totalGovVotes);

        uint256 totalSupplyBefore = token.totalSupply();
        uint256 joinAmount = (totalSupplyBefore / 50) + 1;

        vm.prank(groupOwner1);
        groupManager.updateGroupInfo(
            address(groupAction),
            groupId1,
            "Group1",
            0,
            1,
            0,
            0
        );

        setupUser(user1, joinAmount, address(groupJoin));

        vm.prank(user1);
        vm.expectRevert(IGroupJoinErrors.ExceedsActionMaxJoinAmount.selector);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );
    }

    // ============ exit Tests ============

    // Error Cases

    /// @notice Test: exit when not joined should revert
    /// @dev State validation: cannot exit if not a member
    function test_exit_WhenNotJoined_Reverts() public {
        vm.prank(user1);
        vm.expectRevert(IGroupJoinErrors.NotJoinedAction.selector);
        groupJoin.exit(address(groupAction));
    }

    // ============ Event Tests ============

    /// @notice Test: Join event emits with correct account counts
    /// @dev Event validation: verifies Join event includes correct count parameters
    function test_join_EmitsJoinEvent_WithCorrectAccountCounts() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));

        address tokenAddress = address(token);
        uint256 actionId = ACTION_ID;
        uint256 currentRound = join.currentRound();

        // Event is emitted after account is added, so counts should include the new account
        vm.expectEmit(true, true, true, true);
        emit Join(
            tokenAddress,
            currentRound,
            actionId,
            groupId1,
            user1,
            address(0),
            joinAmount,
            1, // After join, should be 1 (includes user1)
            center.accountsCount(tokenAddress, actionId) + 1, // After join, should increase by 1
            groupJoin.gAccountsByTokenAddressCount(tokenAddress) == 0
                ? 1
                : groupJoin.gAccountsByTokenAddressCount(tokenAddress) + 1 // After join, may increase
        );

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // Verify counts after join
        assertEq(
            groupJoin.accountsByGroupIdByRoundCount(
                address(groupAction),
                join.currentRound(),
                groupId1
            ),
            1,
            "accountCountByGroupId should be 1"
        );
        assertEq(
            center.accountsCount(tokenAddress, actionId),
            1,
            "accountCountByActionId should be 1"
        );
    }

    /// @notice Test: Exit event emits with correct account counts
    /// @dev Event validation: verifies Exit event includes correct count parameters
    function test_exit_EmitsExitEvent_WithCorrectAccountCounts() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));

        // Join first
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        address tokenAddress = address(token);
        uint256 actionId = ACTION_ID;
        uint256 currentRound = join.currentRound();

        // Event is emitted after account is removed, so counts should not include the exited account
        vm.expectEmit(true, true, true, true);
        emit Exit(
            tokenAddress,
            currentRound,
            actionId,
            groupId1,
            user1,
            address(0),
            joinAmount,
            0, // After exit, should be 0 (user1 removed)
            center.accountsCount(tokenAddress, actionId) - 1, // After exit, should decrease by 1
            groupJoin.gAccountsByTokenAddressCount(tokenAddress) - 1 // After exit, should decrease
        );

        vm.prank(user1);
        groupJoin.exit(address(groupAction));

        // Verify counts after exit
        assertEq(
            groupJoin.accountsByGroupIdByRoundCount(
                address(groupAction),
                join.currentRound(),
                groupId1
            ),
            0,
            "accountCountByGroupId should be 0"
        );
        assertEq(
            center.accountsCount(tokenAddress, actionId),
            0,
            "accountCountByActionId should be 0"
        );
    }

    /// @notice Test: Join event account counts with multiple users
    /// @dev Event validation: verifies account counts increment correctly with multiple joins
    function test_join_EmitsJoinEvent_WithMultipleUsers_AccountCountsIncrement()
        public
    {
        uint256 joinAmount = 10e18;
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        address tokenAddress = address(token);
        uint256 actionId = ACTION_ID;

        // First user joins
        setupUser(users[0], joinAmount, address(groupJoin));
        uint256 currentRound = join.currentRound();

        vm.expectEmit(true, true, true, true);
        emit Join(
            tokenAddress,
            currentRound,
            actionId,
            groupId1,
            users[0],
            address(0),
            joinAmount,
            1, // After first join, count should be 1
            center.accountsCount(tokenAddress, actionId) + 1,
            groupJoin.gAccountsByTokenAddressCount(tokenAddress) == 0
                ? 1
                : groupJoin.gAccountsByTokenAddressCount(tokenAddress) + 1
        );

        vm.prank(users[0]);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // Second user joins
        setupUser(users[1], joinAmount, address(groupJoin));
        currentRound = join.currentRound();

        vm.expectEmit(true, true, true, true);
        emit Join(
            tokenAddress,
            currentRound,
            actionId,
            groupId1,
            users[1],
            address(0),
            joinAmount,
            2, // After second join, count should be 2
            center.accountsCount(tokenAddress, actionId) + 1,
            groupJoin.gAccountsByTokenAddressCount(tokenAddress) + 1
        );

        vm.prank(users[1]);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // Third user joins
        setupUser(users[2], joinAmount, address(groupJoin));
        currentRound = join.currentRound();

        vm.expectEmit(true, true, true, true);
        emit Join(
            tokenAddress,
            currentRound,
            actionId,
            groupId1,
            users[2],
            address(0),
            joinAmount,
            3, // After third join, count should be 3
            center.accountsCount(tokenAddress, actionId) + 1,
            groupJoin.gAccountsByTokenAddressCount(tokenAddress) + 1
        );

        vm.prank(users[2]);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // Verify final counts
        assertEq(
            groupJoin.accountsByGroupIdByRoundCount(
                address(groupAction),
                join.currentRound(),
                groupId1
            ),
            3,
            "Final accountCountByGroupId should be 3"
        );
        assertEq(
            center.accountsCount(tokenAddress, actionId),
            3,
            "Final accountCountByActionId should be 3"
        );
    }

    // ============ joinInfoByRound Tests ============

    /// @notice Test: joinInfoByRound at current round returns correct values after join
    /// @dev View function validation: verifies join state is correctly stored
    function test_joinInfo_AfterJoin_ReturnsCorrectValues() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));

        uint256 expectedRound = join.currentRound();
        uint256 expectedAmount = joinAmount;
        uint256 expectedGroupId = groupId1;

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        (
            uint256 joinedRound,
            uint256 amount,
            uint256 groupId,
            address provider
        ) = groupJoin.joinInfoByRound(
            address(groupAction),
            join.currentRound(),
            user1
        );
        assertEq(joinedRound, expectedRound, "joinedRound should match");
        assertEq(amount, expectedAmount, "amount should match");
        assertEq(groupId, expectedGroupId, "groupId should match");
        assertEq(provider, address(0), "provider should be zero");
    }

    /// @notice Test: joinInfoByRound returns correct values at join round
    function test_joinInfoByRound_AtJoinRound_ReturnsCorrectValues() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));

        uint256 r = join.currentRound();
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        (
            uint256 joinedRound,
            uint256 amount,
            uint256 groupId,
            address provider
        ) = groupJoin.joinInfoByRound(address(groupAction), r, user1);
        assertEq(joinedRound, r, "joinedRound at join round");
        assertEq(amount, joinAmount, "amount at join round");
        assertEq(groupId, groupId1, "groupId at join round");
        assertEq(provider, address(0), "provider");
    }

    /// @notice Test: joinInfoByRound after increase amount keeps joinedRound
    function test_joinInfoByRound_AfterIncrease_JoinedRoundUnchanged() public {
        uint256 joinAmount1 = 10e18;
        uint256 joinAmount2 = 5e18;
        setupUser(user1, joinAmount1 + joinAmount2, address(groupJoin));

        uint256 r1 = join.currentRound();
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount1,
            new string[](0)
        );

        advanceRound();
        uint256 r2 = join.currentRound();
        vote.setVotedActionIds(address(token), r2, ACTION_ID);
        vote.setVotesNum(address(token), r2, 10000e18);
        vote.setVotesNumByActionId(address(token), r2, ACTION_ID, 10000e18);
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount2,
            new string[](0)
        );

        (
            uint256 joinedRound1,
            uint256 amount1,
            ,
        ) = groupJoin.joinInfoByRound(address(groupAction), r1, user1);
        assertEq(joinedRound1, r1, "joinedRound at r1");
        assertEq(amount1, joinAmount1, "amount at r1");

        (
            uint256 joinedRound2,
            uint256 amount2,
            ,
        ) = groupJoin.joinInfoByRound(address(groupAction), r2, user1);
        assertEq(joinedRound2, r1, "joinedRound at r2 still r1");
        assertEq(amount2, joinAmount1 + joinAmount2, "amount at r2");
    }

    /// @notice Test: joinInfoByRound at round 0 or before join returns zeros
    function test_joinInfoByRound_BeforeJoin_ReturnsZeros() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));

        uint256 r = join.currentRound();
        (
            uint256 joinedRound,
            uint256 amount,
            uint256 groupId,
        ) = groupJoin.joinInfoByRound(address(groupAction), r, user1);
        assertEq(joinedRound, 0, "joinedRound before join");
        assertEq(amount, 0, "amount before join");
        assertEq(groupId, 0, "groupId before join");

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );
        (joinedRound, amount, groupId, ) = groupJoin.joinInfoByRound(
            address(groupAction),
            r,
            user1
        );
        assertEq(joinedRound, r, "joinedRound at r after join");
        assertEq(amount, joinAmount, "amount at r");
        assertEq(groupId, groupId1, "groupId at r");
    }

    /// @notice Test: joinInfoByRound at round after exit returns zeros
    function test_joinInfoByRound_AfterExit_ReturnsZerosAtLaterRound() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));

        uint256 r1 = join.currentRound();
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        advanceRound();
        uint256 r2 = join.currentRound();
        vm.prank(user1);
        groupJoin.exit(address(groupAction));

        (
            uint256 joinedRound2,
            uint256 amount2,
            uint256 gIdAtR2,
        ) = groupJoin.joinInfoByRound(address(groupAction), r2, user1);
        assertEq(joinedRound2, 0, "joinedRound at r2 after exit");
        assertEq(amount2, 0, "amount at r2 after exit");
        assertEq(gIdAtR2, 0, "groupId at r2 after exit");

        (
            uint256 joinedRound1,
            uint256 amount1,
            uint256 groupId1AtR1,
        ) = groupJoin.joinInfoByRound(address(groupAction), r1, user1);
        assertEq(joinedRound1, r1, "joinedRound at r1 still r1");
        assertEq(amount1, joinAmount, "amount at r1 unchanged");
        assertEq(groupId1AtR1, groupId1, "groupId at r1 unchanged");
    }

    // ============ Round History Tests ============

    /// @notice Test: round history correctly tracks join and amount increases across rounds
    /// @dev Round-based state tracking: verifies historical data preservation
    function test_roundHistory_JoinAndIncreaseAmount_TracksCorrectly() public {
        uint256 joinAmount1 = 10e18;
        uint256 joinAmount2 = 5e18;
        uint256 expectedRound1 = join.currentRound();
        uint256 expectedRound2 = expectedRound1 + 1;
        uint256 expectedAmountRound1 = joinAmount1;
        uint256 expectedAmountRound2 = joinAmount1 + joinAmount2;

        setupUser(user1, joinAmount1 + joinAmount2, address(groupJoin));

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount1,
            new string[](0)
        );

        advanceRound();
        uint256 currentRound2 = join.currentRound();
        vote.setVotedActionIds(address(token), currentRound2, ACTION_ID);
        vote.setVotesNum(address(token), currentRound2, 10000e18);
        vote.setVotesNumByActionId(
            address(token),
            currentRound2,
            ACTION_ID,
            10000e18
        );

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount2,
            new string[](0)
        );

        assertEq(
            groupJoin.groupIdByAccountByRound(
                address(groupAction),
                expectedRound1,
                user1
            ),
            groupId1,
            "groupId should match in round1"
        );
        assertEq(
            groupJoin.groupIdByAccountByRound(
                address(groupAction),
                expectedRound2,
                user1
            ),
            groupId1,
            "groupId should match in round2"
        );

        assertEq(
            groupJoin.joinedAmountByAccountByRound(
                address(groupAction),
                expectedRound1,
                user1
            ),
            expectedAmountRound1,
            "amount should match in round1"
        );
        assertEq(
            groupJoin.joinedAmountByAccountByRound(
                address(groupAction),
                expectedRound2,
                user1
            ),
            expectedAmountRound2,
            "amount should match in round2"
        );

        assertEq(
            groupJoin.totalJoinedAmountByGroupIdByRound(
                address(groupAction),
                expectedRound1,
                groupId1
            ),
            expectedAmountRound1,
            "group amount should match in round1"
        );
        assertEq(
            groupJoin.totalJoinedAmountByGroupIdByRound(
                address(groupAction),
                expectedRound2,
                groupId1
            ),
            expectedAmountRound2,
            "group amount should match in round2"
        );

        assertEq(
            groupJoin.joinedAmountByRound(address(groupAction), expectedRound1),
            expectedAmountRound1,
            "total joined should match in round1"
        );
        assertEq(
            groupJoin.joinedAmountByRound(address(groupAction), expectedRound2),
            expectedAmountRound2,
            "total joined should match in round2"
        );

        assertEq(
            groupJoin.accountsByGroupIdByRoundCount(
                address(groupAction),
                expectedRound1,
                groupId1
            ),
            1,
            "accounts count should be 1 in round1"
        );
        assertEq(
            groupJoin.accountsByGroupIdByRoundCount(
                address(groupAction),
                expectedRound2,
                groupId1
            ),
            1,
            "accounts count should be 1 in round2"
        );
        assertEq(
            groupJoin.accountsByGroupIdByRoundAtIndex(
                address(groupAction),
                expectedRound1,
                groupId1,
                0
            ),
            user1,
            "account should match in round1"
        );
        assertEq(
            groupJoin.accountsByGroupIdByRoundAtIndex(
                address(groupAction),
                expectedRound2,
                groupId1,
                0
            ),
            user1,
            "account should match in round2"
        );
    }

    /// @notice Test: round history correctly tracks exit updates across rounds
    /// @dev Round-based state tracking: verifies exit state is recorded in subsequent rounds
    function test_roundHistory_ExitUpdates_TracksCorrectly() public {
        uint256 joinAmount1 = 10e18;
        uint256 joinAmount2 = 5e18;
        uint256 expectedRound1 = join.currentRound();
        uint256 expectedRound2 = expectedRound1 + 1;
        uint256 expectedRound3 = expectedRound2 + 1;
        uint256 expectedAmountRound1 = joinAmount1;
        uint256 expectedAmountRound2 = joinAmount1 + joinAmount2;
        uint256 expectedAmountRound3 = 0;

        setupUser(user1, joinAmount1 + joinAmount2, address(groupJoin));

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount1,
            new string[](0)
        );

        advanceRound();
        uint256 currentRound2 = join.currentRound();
        vote.setVotedActionIds(address(token), currentRound2, ACTION_ID);
        vote.setVotesNum(address(token), currentRound2, 10000e18);
        vote.setVotesNumByActionId(
            address(token),
            currentRound2,
            ACTION_ID,
            10000e18
        );

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount2,
            new string[](0)
        );

        advanceRound();

        vm.prank(user1);
        groupJoin.exit(address(groupAction));

        assertEq(
            groupJoin.joinedAmountByAccountByRound(
                address(groupAction),
                expectedRound1,
                user1
            ),
            expectedAmountRound1,
            "amount should match in round1"
        );
        assertEq(
            groupJoin.joinedAmountByAccountByRound(
                address(groupAction),
                expectedRound2,
                user1
            ),
            expectedAmountRound2,
            "amount should match in round2"
        );
        assertEq(
            groupJoin.joinedAmountByAccountByRound(
                address(groupAction),
                expectedRound3,
                user1
            ),
            expectedAmountRound3,
            "amount should be 0 in round3"
        );

        assertEq(
            groupJoin.totalJoinedAmountByGroupIdByRound(
                address(groupAction),
                expectedRound3,
                groupId1
            ),
            expectedAmountRound3,
            "group amount should be 0 in round3"
        );
        assertEq(
            groupJoin.joinedAmountByRound(address(groupAction), expectedRound3),
            expectedAmountRound3,
            "total joined should be 0 in round3"
        );

        assertEq(
            groupJoin.groupIdByAccountByRound(
                address(groupAction),
                expectedRound3,
                user1
            ),
            0,
            "groupId should be 0 in round3"
        );
        assertEq(
            groupJoin.accountsByGroupIdByRoundCount(
                address(groupAction),
                expectedRound3,
                groupId1
            ),
            0,
            "accounts count should be 0 in round3"
        );
    }

    /// @notice Test: join and exit in same round leaves state correct
    /// @dev Round boundary: no round advance between join and exit
    function test_joinAndExit_InSameRound_StateCorrect() public {
        uint256 joinAmount = 10e18;
        uint256 currentRound = join.currentRound();
        setupUser(user1, joinAmount, address(groupJoin));

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        vm.prank(user1);
        groupJoin.exit(address(groupAction));

        (uint256 joinedRound, uint256 amount, uint256 groupId, ) = groupJoin
            .joinInfoByRound(
                address(groupAction),
                join.currentRound(),
                user1
            );
        uint256 expectedJoinedRound = 0;
        uint256 expectedAmount = 0;
        uint256 expectedGroupId = 0;
        assertEq(
            joinedRound,
            expectedJoinedRound,
            "joinedRound should be cleared"
        );
        assertEq(amount, expectedAmount, "amount should be cleared");
        assertEq(groupId, expectedGroupId, "groupId should be cleared");

        assertEq(
            groupJoin.accountsByGroupIdByRoundCount(
                address(groupAction),
                join.currentRound(),
                groupId1
            ),
            0,
            "accountsByGroupIdCount should be 0"
        );
        assertEq(
            groupJoin.totalJoinedAmountByGroupIdByRound(
                address(groupAction),
                join.currentRound(),
                groupId1
            ),
            0,
            "totalJoinedAmountByGroupId should be 0"
        );
        assertEq(
            groupJoin.joinedAmountByAccountByRound(
                address(groupAction),
                currentRound,
                user1
            ),
            0,
            "joinedAmountByAccountByRound at current round should be 0"
        );
        assertEq(
            groupJoin.groupIdByAccountByRound(
                address(groupAction),
                currentRound,
                user1
            ),
            0,
            "groupIdByAccountByRound at current round should be 0"
        );
    }

    /// @notice Test: quick join-exit-rejoin leaves state correct
    /// @dev Boundary: join, exit, then rejoin same group without round advance
    function test_quickJoinExitRejoin_StateCorrect() public {
        uint256 joinAmount1 = 10e18;
        uint256 joinAmount2 = 15e18;
        setupUser(user1, joinAmount1 + joinAmount2, address(groupJoin));

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount1,
            new string[](0)
        );

        vm.prank(user1);
        groupJoin.exit(address(groupAction));

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount2,
            new string[](0)
        );

        (uint256 joinedRound, uint256 amount, uint256 groupId, ) = groupJoin
            .joinInfoByRound(
                address(groupAction),
                join.currentRound(),
                user1
            );
        assertTrue(joinedRound > 0, "should be joined after rejoin");
        assertEq(amount, joinAmount2, "amount should be second join amount");
        assertEq(groupId, groupId1, "groupId should match");
        assertEq(
            groupJoin.totalJoinedAmountByGroupIdByRound(
                address(groupAction),
                join.currentRound(),
                groupId1
            ),
            joinAmount2,
            "group total should reflect rejoin amount only"
        );
        assertEq(
            groupJoin.accountsByGroupIdByRoundCount(
                address(groupAction),
                join.currentRound(),
                groupId1
            ),
            1,
            "accounts count should be 1"
        );
    }

    /// @notice Test: querying historical data at round 0 returns zero/empty
    /// @dev Round boundary: round 0 has no recorded data
    function test_queryHistoricalData_AtRound0_ReturnsZero() public view {
        uint256 round0 = 0;
        uint256 expectedTotalByGroup = 0;
        uint256 expectedJoinedByRound = 0;
        uint256 expectedCountByRound = 0;
        uint256 expectedGroupIdByAccount = 0;

        assertEq(
            groupJoin.totalJoinedAmountByGroupIdByRound(
                address(groupAction),
                round0,
                groupId1
            ),
            expectedTotalByGroup,
            "totalJoinedAmountByGroupIdByRound at round 0 should be 0"
        );
        assertEq(
            groupJoin.joinedAmountByRound(address(groupAction), round0),
            expectedJoinedByRound,
            "joinedAmountByRound at round 0 should be 0"
        );
        assertEq(
            groupJoin.accountsByGroupIdByRoundCount(
                address(groupAction),
                round0,
                groupId1
            ),
            expectedCountByRound,
            "accountsByGroupIdByRoundCount at round 0 should be 0"
        );

        assertEq(
            groupJoin.groupIdByAccountByRound(
                address(groupAction),
                round0,
                user1
            ),
            expectedGroupIdByAccount,
            "groupIdByAccountByRound at round 0 for non-joined account should be 0"
        );
    }

    // ============ Global State Tests ============

    /// @notice Test: after last user exits, global indices are cleaned up
    /// @dev Global state: gGroupIds, gAccounts, gTokenAddresses etc. cleared when last user exits
    function test_lastUserExit_GlobalStateCleanup() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        assertEq(
            groupJoin.gGroupIdsCount(),
            1,
            "gGroupIdsCount should be 1 before exit"
        );
        assertEq(
            groupJoin.gAccountsCount(),
            1,
            "gAccountsCount should be 1 before exit"
        );

        vm.prank(user1);
        groupJoin.exit(address(groupAction));

        assertEq(
            groupJoin.gGroupIdsCount(),
            0,
            "gGroupIdsCount should be 0 after last exit"
        );
        assertEq(
            groupJoin.gAccountsCount(),
            0,
            "gAccountsCount should be 0 after last exit"
        );
        assertEq(
            groupJoin.gTokenAddressesCount(),
            0,
            "gTokenAddressesCount should be 0 after last exit"
        );
        assertEq(
            groupJoin.gGroupIdsByAccountCount(user1),
            0,
            "gGroupIdsByAccount should be empty"
        );
        assertEq(
            groupJoin.gAccountsByGroupIdCount(groupId1),
            0,
            "gAccountsByGroupId should be empty"
        );
    }

    /// @notice Test: same groupId participated via two different tokenAddresses has isolated state
    /// @dev Boundary: one groupId activated for two extensions (two tokens); user joins both
    function test_sameGroupId_DifferentTokenAddress_StateIsolated() public {
        uint256 actionId2 = 1;
        MockGroupToken token2 = new MockGroupToken();
        token2.mint(address(this), 1e18);
        token2.mint(user1, 20e18);
        launch.setLOVE20Token(address(token2), true);
        stake.setGovVotesNum(address(token2), 100_000e18);
        stake.setValidGovVotes(address(token2), groupOwner1, 10000e18);

        ExtensionGroupAction groupAction2 = new ExtensionGroupAction(
            address(mockGroupActionFactory),
            address(token2),
            address(token2),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );
        token2.approve(address(mockGroupActionFactory), type(uint256).max);
        mockGroupActionFactory.registerExtensionForTesting(
            address(groupAction2),
            address(token2)
        );
        prepareExtensionInit(address(groupAction2), address(token2), actionId2);

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

        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));
        vm.prank(user1);
        token2.approve(address(groupJoin), type(uint256).max);

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );
        vm.prank(user1);
        groupJoin.join(
            address(groupAction2),
            groupId1,
            joinAmount,
            new string[](0)
        );

        (uint256 r1, uint256 amt1, uint256 g1, ) = groupJoin.joinInfoByRound(
            address(groupAction),
            join.currentRound(),
            user1
        );
        (uint256 r2, uint256 amt2, uint256 g2, ) = groupJoin.joinInfoByRound(
            address(groupAction2),
            join.currentRound(),
            user1
        );
        assertTrue(r1 > 0 && r2 > 0, "joined both extensions");
        assertEq(amt1, joinAmount, "amount for ext1");
        assertEq(amt2, joinAmount, "amount for ext2");
        assertEq(g1, groupId1, "groupId for ext1");
        assertEq(g2, groupId1, "groupId for ext2");

        assertEq(
            groupJoin.accountsByGroupIdByRoundCount(
                address(groupAction),
                join.currentRound(),
                groupId1
            ),
            1,
            "ext1 groupId1 count"
        );
        assertEq(
            groupJoin.accountsByGroupIdByRoundCount(
                address(groupAction2),
                join.currentRound(),
                groupId1
            ),
            1,
            "ext2 groupId1 count"
        );
        assertTrue(
            groupJoin.gGroupIdsByTokenAddressCount(address(token)) >= 1,
            "token should have groupId"
        );
        assertTrue(
            groupJoin.gGroupIdsByTokenAddressCount(address(token2)) >= 1,
            "token2 should have groupId"
        );
    }

    /// @notice Test: 3 extensions on same token; global and per-extension state correct
    /// @dev Boundary: 3 actionIds, 3 groups, 3 users; verify g* and per-extension views
    function test_threeExtensions_SameToken_GlobalAndPerExtensionState()
        public
    {
        uint256 actionId2 = 1;
        uint256 actionId3 = 2;
        uint256 joinAmount = 10e18;

        ExtensionGroupAction groupAction2 = new ExtensionGroupAction(
            address(mockGroupActionFactory),
            address(token),
            address(token),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );
        ExtensionGroupAction groupAction3 = new ExtensionGroupAction(
            address(mockGroupActionFactory),
            address(token),
            address(token),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );
        token.approve(address(mockGroupActionFactory), type(uint256).max);
        mockGroupActionFactory.registerExtensionForTesting(
            address(groupAction2),
            address(token)
        );
        mockGroupActionFactory.registerExtensionForTesting(
            address(groupAction3),
            address(token)
        );
        prepareExtensionInit(address(groupAction2), address(token), actionId2);
        prepareExtensionInit(address(groupAction3), address(token), actionId3);

        uint256 groupId3 = setupGroupOwner(groupOwner1, 10000e18, "Group3");
        uint256 groupId4 = setupGroupOwner(groupOwner2, 10000e18, "Group4");

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
        vm.prank(groupOwner1);
        groupManager.activateGroup(
            address(groupAction2),
            groupId3,
            "Group3",
            0,
            1e18,
            0,
            0
        );
        vm.prank(groupOwner2);
        groupManager.activateGroup(
            address(groupAction3),
            groupId4,
            "Group4",
            0,
            1e18,
            0,
            0
        );

        setupUser(user1, joinAmount, address(groupJoin));
        setupUser(user2, joinAmount, address(groupJoin));
        setupUser(user3, joinAmount, address(groupJoin));

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );
        vm.prank(user2);
        groupJoin.join(
            address(groupAction2),
            groupId3,
            joinAmount,
            new string[](0)
        );
        vm.prank(user3);
        groupJoin.join(
            address(groupAction3),
            groupId4,
            joinAmount,
            new string[](0)
        );

        assertEq(groupJoin.gTokenAddressesCount(), 1, "single tokenAddress");
        assertTrue(
            groupJoin.gActionIdsByTokenAddressCount(address(token)) >= 3,
            "at least 3 actionIds for token"
        );
        assertTrue(groupJoin.gGroupIdsCount() >= 3, "at least 3 groupIds");
        assertEq(
            groupJoin.accountsByGroupIdByRoundCount(
                address(groupAction),
                join.currentRound(),
                groupId1
            ),
            1,
            "ext1 groupId1"
        );
        assertEq(
            groupJoin.accountsByGroupIdByRoundCount(
                address(groupAction2),
                join.currentRound(),
                groupId3
            ),
            1,
            "ext2 groupId3"
        );
        assertEq(
            groupJoin.accountsByGroupIdByRoundCount(
                address(groupAction3),
                join.currentRound(),
                groupId4
            ),
            1,
            "ext3 groupId4"
        );
        assertEq(
            groupJoin.totalJoinedAmountByGroupIdByRound(
                address(groupAction),
                join.currentRound(),
                groupId1
            ),
            joinAmount,
            "ext1 total"
        );
        assertEq(
            groupJoin.totalJoinedAmountByGroupIdByRound(
                address(groupAction2),
                join.currentRound(),
                groupId3
            ),
            joinAmount,
            "ext2 total"
        );
        assertEq(
            groupJoin.totalJoinedAmountByGroupIdByRound(
                address(groupAction3),
                join.currentRound(),
                groupId4
            ),
            joinAmount,
            "ext3 total"
        );
    }

    /// @notice Test: first user joining a newly activated group updates global state correctly
    /// @dev Global state: new groupId appears in gGroupIds after first join
    function test_firstUserJoin_NewlyActivatedGroup() public {
        uint256 groupId3 = setupGroupOwner(groupOwner2, 10000e18, "Group3");
        setupUser(
            groupOwner2,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );
        vm.prank(groupOwner2);
        groupManager.activateGroup(
            address(groupAction),
            groupId3,
            "Group3",
            0,
            1e18,
            0,
            0
        );

        uint256 joinAmount = 10e18;
        address firstUser = user3;
        setupUser(firstUser, joinAmount, address(groupJoin));

        uint256 gGroupIdsCountBefore = groupJoin.gGroupIdsCount();
        vm.prank(firstUser);
        groupJoin.join(
            address(groupAction),
            groupId3,
            joinAmount,
            new string[](0)
        );

        assertTrue(
            groupJoin.gGroupIdsCount() >= gGroupIdsCountBefore + 1,
            "gGroupIds should include new group"
        );
        assertTrue(
            groupJoin.gAccountsByGroupIdCount(groupId3) >= 1,
            "groupId3 should have at least one account"
        );
        assertEq(
            groupJoin.accountsByGroupIdByRoundAtIndex(
                address(groupAction),
                join.currentRound(),
                groupId3,
                0
            ),
            firstUser,
            "first account in groupId3 should be firstUser"
        );
        assertEq(
            groupJoin.totalJoinedAmountByGroupIdByRound(
                address(groupAction),
                join.currentRound(),
                groupId3
            ),
            joinAmount,
            "totalJoinedAmountByGroupId for groupId3 should match"
        );
    }

    // ============ Trial Join Tests ============

    /// @notice Test: trialJoin uses provider escrow and exit refunds provider
    /// @dev Trial join flow: provider funds escrow, user joins, exit refunds provider
    function test_trialJoin_UsesProviderEscrow_ExitRefundsProvider() public {
        uint256 providerFunds = 20e18;
        uint256 trialAmount = 10e18;
        address provider = user2;

        setupUser(provider, providerFunds, address(groupJoin));

        uint256 providerBalanceBeforeSet = token.balanceOf(provider);

        _setTrialAccounts(provider, trialAmount, user1);

        uint256 expectedProviderBalanceAfterSet = providerBalanceBeforeSet -
            trialAmount;

        assertEq(
            token.balanceOf(provider),
            expectedProviderBalanceAfterSet,
            "provider balance should decrease by trialAmount"
        );
        uint256 expectedRound = join.currentRound();

        vm.prank(user1);
        groupJoin.trialJoin(
            address(groupAction),
            groupId1,
            provider,
            new string[](0)
        );

        _assertJoinInfo(user1, expectedRound, trialAmount, groupId1, provider);

        address inUseAccount = groupJoin.trialAccountsJoinedAtIndex(
            address(groupAction),
            groupId1,
            provider,
            0
        );
        assertEq(inUseAccount, user1, "in-use account should be user1");

        uint256 providerBalanceBeforeExit = token.balanceOf(provider);
        uint256 userBalanceBeforeExit = token.balanceOf(user1);
        vm.prank(user1);
        groupJoin.exit(address(groupAction));

        assertEq(
            token.balanceOf(provider),
            providerBalanceBeforeExit + trialAmount,
            "provider balance should be refunded"
        );
        assertEq(
            token.balanceOf(user1),
            userBalanceBeforeExit,
            "trial user should not receive refund"
        );
        (, , , address clearedProvider) = groupJoin.joinInfoByRound(
            address(groupAction),
            join.currentRound(),
            user1
        );
        assertEq(
            clearedProvider,
            address(0),
            "trial provider should be cleared"
        );
    }

    /// @notice Test: join after trialJoin should revert
    /// @dev State validation: trial users cannot join normally
    function test_trialJoin_AfterTrialJoin_JoinReverts() public {
        uint256 poolAmount = 20e18;
        uint256 trialAmount = 10e18;
        address provider = user2;

        setupUser(provider, poolAmount, address(groupJoin));

        _setTrialAccounts(provider, trialAmount, user1);

        vm.prank(user1);
        groupJoin.trialJoin(
            address(groupAction),
            groupId1,
            provider,
            new string[](0)
        );

        vm.prank(user1);
        vm.expectRevert(IGroupJoinErrors.TrialAlreadyJoined.selector);
        groupJoin.join(address(groupAction), groupId1, 1e18, new string[](0));
    }

    /// @notice Test: trialAccountsWaitingAdd with self as account should revert
    /// @dev Validation: provider cannot add themselves as trial account
    function test_trialAccountsWaitingAdd_WithSelfAsAccount_Reverts() public {
        uint256 poolAmount = 20e18;
        uint256 trialAmount = 10e18;
        address provider = user2;

        setupUser(provider, poolAmount, address(groupJoin));

        address[] memory trialAccounts = new address[](1);
        uint256[] memory trialAmounts = new uint256[](1);
        trialAccounts[0] = provider;
        trialAmounts[0] = trialAmount;

        vm.prank(provider);
        vm.expectRevert(IGroupJoinErrors.TrialAccountIsProvider.selector);
        groupJoin.trialAccountsWaitingAdd(
            address(groupAction),
            groupId1,
            trialAccounts,
            trialAmounts
        );
    }

    /// @notice Test: provider can exit on behalf of trial user
    /// @dev Trial join flow: provider can force exit trial users
    function test_trialExit_ByProvider_ExitsTrialUser() public {
        uint256 poolAmount = 20e18;
        uint256 trialAmount = 10e18;
        address provider = user2;

        setupUser(provider, poolAmount, address(groupJoin));

        _setTrialAccounts(provider, trialAmount, user1);

        vm.prank(user1);
        groupJoin.trialJoin(
            address(groupAction),
            groupId1,
            provider,
            new string[](0)
        );

        uint256 providerBalanceBeforeExit = token.balanceOf(provider);
        vm.prank(provider);
        groupJoin.trialExit(address(groupAction), user1);

        assertEq(
            token.balanceOf(provider),
            providerBalanceBeforeExit + trialAmount,
            "provider balance should be refunded"
        );
        (, , , address exitProvider) = groupJoin.joinInfoByRound(
            address(groupAction),
            join.currentRound(),
            user1
        );
        assertEq(exitProvider, address(0), "trial provider should be cleared");
        assertEq(
            groupJoin.accountsByGroupIdByRoundCount(
                address(groupAction),
                join.currentRound(),
                groupId1
            ),
            0,
            "accounts should be removed after exit"
        );
    }

    /// @notice Test: trialJoin after provider removes account from waiting list reverts
    /// @dev Trial account: user cannot trialJoin if provider has removed them from waiting list
    function test_trialJoin_AfterProviderRemoves_Reverts() public {
        uint256 poolAmount = 20e18;
        uint256 trialAmount = 10e18;
        address provider = user2;

        setupUser(provider, poolAmount, address(groupJoin));
        _setTrialAccounts(provider, trialAmount, user1);

        address[] memory toRemove = new address[](1);
        toRemove[0] = user1;
        vm.prank(provider);
        groupJoin.trialAccountsWaitingRemove(
            address(groupAction),
            groupId1,
            toRemove
        );

        vm.prank(user1);
        vm.expectRevert(IGroupJoinErrors.TrialAmountZero.selector);
        groupJoin.trialJoin(
            address(groupAction),
            groupId1,
            provider,
            new string[](0)
        );
    }

    /// @notice Test: same account added by multiple providers has independent waiting lists
    /// @dev Trial account: per-provider waiting list; one trialJoin consumes only that provider's entry
    function test_trialAccountsWaiting_MultipleProviders_Independent() public {
        uint256 trialAmount = 10e18;
        address provider1 = user2;
        address provider2 = user3;

        setupUser(provider1, trialAmount, address(groupJoin));
        setupUser(provider2, trialAmount, address(groupJoin));

        _setTrialAccounts(provider1, trialAmount, user1);
        _setTrialAccounts(provider2, trialAmount, user1);

        assertEq(
            groupJoin.trialAccountsWaitingCount(
                address(groupAction),
                groupId1,
                provider1
            ),
            1,
            "provider1 waiting count should be 1"
        );
        assertEq(
            groupJoin.trialAccountsWaitingCount(
                address(groupAction),
                groupId1,
                provider2
            ),
            1,
            "provider2 waiting count should be 1"
        );

        vm.prank(user1);
        groupJoin.trialJoin(
            address(groupAction),
            groupId1,
            provider1,
            new string[](0)
        );

        assertEq(
            groupJoin.trialAccountsWaitingCount(
                address(groupAction),
                groupId1,
                provider2
            ),
            1,
            "provider2 waiting list still has user1 (independent)"
        );
    }

    /// @notice Test: trialAccountsWaitingRemove reverts when account is not in waiting list
    function test_trialAccountsWaitingRemove_WhenAccountNotInWaitingList_Reverts()
        public
    {
        uint256 trialAmount = 10e18;
        address provider = user2;
        setupUser(provider, trialAmount, address(groupJoin));
        _setTrialAccounts(provider, trialAmount, user1);

        address notInList = user3;
        address[] memory toRemove = new address[](1);
        toRemove[0] = notInList;

        vm.prank(provider);
        vm.expectRevert(
            abi.encodeWithSelector(
                IGroupJoinErrors.TrialAccountNotInWaitingList.selector,
                notInList
            )
        );
        groupJoin.trialAccountsWaitingRemove(
            address(groupAction),
            groupId1,
            toRemove
        );
    }

    /// @notice Test: trial join with amount exactly equal to group max succeeds
    /// @dev Trial account: boundary when trialAmount == group maxJoinAmount
    function test_trialJoin_AmountEqualsGroupMax_Succeeds() public {
        uint256 maxJoinAmount = 10e18;
        vm.prank(groupOwner1);
        groupManager.updateGroupInfo(
            address(groupAction),
            groupId1,
            "Group1",
            0,
            1e18,
            maxJoinAmount,
            0
        );

        address provider = user2;
        setupUser(provider, maxJoinAmount, address(groupJoin));
        _setTrialAccounts(provider, maxJoinAmount, user1);

        vm.prank(user1);
        groupJoin.trialJoin(
            address(groupAction),
            groupId1,
            provider,
            new string[](0)
        );

        (
            uint256 joinedRound,
            uint256 amount,
            uint256 groupId,
            address prov
        ) = groupJoin.joinInfoByRound(
            address(groupAction),
            join.currentRound(),
            user1
        );
        assertTrue(joinedRound > 0, "should be joined");
        assertEq(amount, maxJoinAmount, "amount should equal group max");
        assertEq(groupId, groupId1, "groupId should match");
        assertEq(prov, provider, "provider should match");
    }

    // ============ Helper Functions ============

    /// @notice Helper: Setup trial accounts for testing
    function _setTrialAccounts(
        address provider,
        uint256 trialAmount,
        address account
    ) internal {
        address[] memory trialAccounts = new address[](1);
        uint256[] memory trialAmounts = new uint256[](1);
        trialAccounts[0] = account;
        trialAmounts[0] = trialAmount;

        vm.prank(provider);
        groupJoin.trialAccountsWaitingAdd(
            address(groupAction),
            groupId1,
            trialAccounts,
            trialAmounts
        );
    }

    /// @notice Helper: Assert join info matches expected values
    function _assertJoinInfo(
        address account,
        uint256 expectedRound,
        uint256 expectedAmount,
        uint256 expectedGroupId,
        address expectedProvider
    ) internal view {
        (
            uint256 joinedRound,
            uint256 amount,
            uint256 groupId,
            address provider
        ) = groupJoin.joinInfoByRound(
            address(groupAction),
            join.currentRound(),
            account
        );
        assertEq(joinedRound, expectedRound, "joinedRound should match");
        assertEq(amount, expectedAmount, "amount should match");
        assertEq(groupId, expectedGroupId, "groupId should match");
        assertEq(provider, expectedProvider, "provider should match");
    }
}
