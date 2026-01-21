// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "./utils/BaseGroupTest.sol";
import {IGroupJoinEvents} from "../src/interface/IGroupJoin.sol";
import {IGroupJoinErrors} from "../src/interface/IGroupJoin.sol";
import {ExtensionGroupAction} from "../src/ExtensionGroupAction.sol";
import {IGroupJoin} from "../src/interface/IGroupJoin.sol";

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

    // ============ isAccountInRangeByRound Tests ============

    /// @notice Test: isAccountInRangeByRound returns correct values for different ranges
    /// @dev Verifies that the function correctly identifies accounts within specified index ranges
    function test_isAccountInRangeByRound_WithValidRanges_ReturnsCorrectValues()
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
        bool expectedTrue = true;
        bool expectedFalse = false;
        address nonMember = address(0x999);

        assertEq(
            groupJoin.isAccountInRangeByRound(
                address(groupAction),
                round,
                groupId1,
                users[0],
                0,
                1
            ),
            expectedTrue,
            "User 0 should be in range [0,1]"
        );
        assertEq(
            groupJoin.isAccountInRangeByRound(
                address(groupAction),
                round,
                groupId1,
                users[2],
                0,
                1
            ),
            expectedFalse,
            "User 2 should be out of range [0,1]"
        );
        assertEq(
            groupJoin.isAccountInRangeByRound(
                address(groupAction),
                round,
                groupId1,
                users[2],
                2,
                2
            ),
            expectedTrue,
            "User 2 should be in range [2,2]"
        );
        assertEq(
            groupJoin.isAccountInRangeByRound(
                address(groupAction),
                round,
                groupId1,
                nonMember,
                0,
                2
            ),
            expectedFalse,
            "Non-member should be out of range"
        );
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

        (uint256 joinedRound, uint256 amount, , ) = groupJoin.joinInfo(
            address(groupAction),
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

        (uint256 joinedRound, uint256 amount, , ) = groupJoin.joinInfo(
            address(groupAction),
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
            groupJoin.accountsByGroupIdCount(address(groupAction), groupId1),
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
            groupJoin.accountsByGroupIdCount(address(groupAction), groupId1),
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
            groupJoin.accountsByGroupIdCount(address(groupAction), groupId1),
            3,
            "Final accountCountByGroupId should be 3"
        );
        assertEq(
            center.accountsCount(tokenAddress, actionId),
            3,
            "Final accountCountByActionId should be 3"
        );
    }

    // ============ joinInfo Tests ============

    /// @notice Test: joinInfo returns correct latest values after join
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
        ) = groupJoin.joinInfo(address(groupAction), user1);
        assertEq(joinedRound, expectedRound, "joinedRound should match");
        assertEq(amount, expectedAmount, "amount should match");
        assertEq(groupId, expectedGroupId, "groupId should match");
        assertEq(provider, address(0), "provider should be zero");
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
        (, , , address clearedProvider) = groupJoin.joinInfo(
            address(groupAction),
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
        (, , , address exitProvider) = groupJoin.joinInfo(
            address(groupAction),
            user1
        );
        assertEq(exitProvider, address(0), "trial provider should be cleared");
        assertEq(
            groupJoin.accountsByGroupIdCount(address(groupAction), groupId1),
            0,
            "accounts should be removed after exit"
        );
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
        ) = groupJoin.joinInfo(address(groupAction), account);
        assertEq(joinedRound, expectedRound, "joinedRound should match");
        assertEq(amount, expectedAmount, "amount should match");
        assertEq(groupId, expectedGroupId, "groupId should match");
        assertEq(provider, expectedProvider, "provider should match");
    }
}
