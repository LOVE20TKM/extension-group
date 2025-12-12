// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "../utils/BaseGroupTest.sol";
import {GroupTokenJoin} from "../../src/base/GroupTokenJoin.sol";
import {GroupCore} from "../../src/base/GroupCore.sol";
import {IGroupTokenJoin} from "../../src/interface/base/IGroupTokenJoin.sol";
import {IGroupCore} from "../../src/interface/base/IGroupCore.sol";
import {ILOVE20GroupManager} from "../../src/interface/ILOVE20GroupManager.sol";

/**
 * @title MockGroupTokenJoin
 * @notice Concrete implementation of GroupTokenJoin for testing
 */
contract MockGroupTokenJoin is GroupTokenJoin {
    constructor(
        address factory_,
        address tokenAddress_,
        address groupManagerAddress_,
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
            groupManagerAddress_,
            stakeTokenAddress_,
            minGovVoteRatioBps_,
            capacityMultiplier_,
            stakingMultiplier_,
            maxJoinAmountMultiplier_,
            minJoinAmount_
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
        return _joinInfo[account].amount;
    }

    function _calculateReward(
        uint256,
        address
    ) internal pure override returns (uint256) {
        return 0;
    }

    // Expose for testing
    function getAccounts() external view returns (address[] memory) {
        return _center.accounts(tokenAddress, actionId);
    }
}

/**
 * @title GroupTokenJoinTest
 * @notice Test suite for GroupTokenJoin
 */
contract GroupTokenJoinTest is BaseGroupTest {
    MockGroupTokenJoin public groupTokenJoin;

    uint256 public groupId1;
    uint256 public groupId2;

    function setUp() public {
        setUpBase();

        // Deploy GroupTokenJoin
        groupTokenJoin = new MockGroupTokenJoin(
            address(mockFactory),
            address(token),
            address(groupManager),
            address(token),
            MIN_GOV_VOTE_RATIO_BPS,
            CAPACITY_MULTIPLIER,
            STAKING_MULTIPLIER,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            MIN_JOIN_AMOUNT
        );

        // Register extension
        token.mint(address(this), 1e18);
        token.approve(address(mockFactory), type(uint256).max);
        mockFactory.registerExtension(address(groupTokenJoin), address(token));

        // Setup group owners
        groupId1 = setupGroupOwner(groupOwner1, 10000e18, "TestGroup1");
        groupId2 = setupGroupOwner(groupOwner2, 10000e18, "TestGroup2");

        // Prepare extension init (config already set in GroupCore constructor)
        prepareExtensionInit(
            address(groupTokenJoin),
            address(token),
            ACTION_ID
        );

        // Activate groups through GroupManager
        uint256 stakeAmount = 10000e18;
        setupUser(groupOwner1, stakeAmount, address(groupManager));
        setupUser(groupOwner2, stakeAmount, address(groupManager));

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID,
            groupId1,
            "Group1",
            stakeAmount,
            MIN_JOIN_AMOUNT,
            0,
            0
        );

        vm.prank(groupOwner2, groupOwner2);
        groupManager.activateGroup(
            address(token),
            ACTION_ID,
            groupId2,
            "Group2",
            stakeAmount,
            MIN_JOIN_AMOUNT,
            0,
            0
        );
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsJoinTokenAddress() public view {
        assertEq(groupTokenJoin.JOIN_TOKEN_ADDRESS(), address(token));
    }

    // ============ join Tests ============

    function test_Join_Success() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupTokenJoin));

        vm.prank(user1);
        groupTokenJoin.join(groupId1, joinAmount, new string[](0));

        (uint256 joinedRound, uint256 amount, uint256 groupId) = groupTokenJoin
            .joinInfo(user1);
        assertEq(amount, joinAmount);
        assertEq(groupId, groupId1);
        assertEq(joinedRound, verify.currentRound());

        assertEq(groupTokenJoin.totalJoinedAmount(), joinAmount);
    }

    function test_Join_AddMoreTokens() public {
        uint256 initialAmount = 10e18;
        uint256 additionalAmount = 5e18;
        setupUser(
            user1,
            initialAmount + additionalAmount,
            address(groupTokenJoin)
        );

        vm.startPrank(user1);
        groupTokenJoin.join(groupId1, initialAmount, new string[](0));
        groupTokenJoin.join(groupId1, additionalAmount, new string[](0));
        vm.stopPrank();

        (, uint256 amount, ) = groupTokenJoin.joinInfo(user1);
        assertEq(amount, initialAmount + additionalAmount);
    }

    function test_Join_RevertAmountZero() public {
        setupUser(user1, 100e18, address(groupTokenJoin));

        vm.prank(user1);
        vm.expectRevert(IGroupTokenJoin.JoinAmountZero.selector);
        groupTokenJoin.join(groupId1, 0, new string[](0));
    }

    function test_Join_RevertAlreadyInOtherGroup() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount * 2, address(groupTokenJoin));

        vm.startPrank(user1);
        groupTokenJoin.join(groupId1, joinAmount, new string[](0));

        vm.expectRevert(IGroupTokenJoin.AlreadyInOtherGroup.selector);
        groupTokenJoin.join(groupId2, joinAmount, new string[](0));
        vm.stopPrank();
    }

    function test_Join_RevertCannotJoinDeactivatedGroup() public {
        advanceRound();
        // Setup actionIds for new round
        vote.setVotedActionIds(
            address(token),
            verify.currentRound(),
            ACTION_ID
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.deactivateGroup(address(token), ACTION_ID, groupId1);

        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupTokenJoin));

        vm.prank(user1);
        vm.expectRevert(IGroupTokenJoin.CannotJoinDeactivatedGroup.selector);
        groupTokenJoin.join(groupId1, joinAmount, new string[](0));
    }

    function test_Join_RevertAmountBelowMinimum() public {
        uint256 tooLowAmount = MIN_JOIN_AMOUNT / 2;
        setupUser(user1, tooLowAmount, address(groupTokenJoin));

        vm.prank(user1);
        vm.expectRevert(IGroupTokenJoin.AmountBelowMinimum.selector);
        groupTokenJoin.join(groupId1, tooLowAmount, new string[](0));
    }

    function test_Join_RevertGroupCapacityFull() public {
        // Get current capacity
        (, uint256 capacity) = groupManager.groupStakeAndCapacity(
            address(token),
            ACTION_ID,
            groupId1
        );
        uint256 maxPerAccount = groupManager.calculateJoinMaxAmount(
            address(token),
            ACTION_ID
        );

        // Calculate exact number needed to fill and amount for last user
        uint256 fullUsers = capacity / maxPerAccount;
        uint256 remaining = capacity % maxPerAccount;

        // Fill capacity
        for (uint256 i = 0; i < fullUsers; i++) {
            address testUser = address(uint160(0x1000 + i));
            setupUser(testUser, maxPerAccount, address(groupTokenJoin));
            vm.prank(testUser);
            groupTokenJoin.join(groupId1, maxPerAccount, new string[](0));
        }

        // If there's remaining space that's >= MIN_JOIN_AMOUNT, fill it
        if (remaining >= MIN_JOIN_AMOUNT) {
            address partialUser = address(uint160(0x1000 + fullUsers));
            setupUser(partialUser, remaining, address(groupTokenJoin));
            vm.prank(partialUser);
            groupTokenJoin.join(groupId1, remaining, new string[](0));
        }

        // Now capacity should be full - try to join with another user
        address extraUser = address(uint160(0x2000));
        setupUser(extraUser, MIN_JOIN_AMOUNT, address(groupTokenJoin));

        vm.prank(extraUser);
        vm.expectRevert(IGroupTokenJoin.GroupCapacityFull.selector);
        groupTokenJoin.join(groupId1, MIN_JOIN_AMOUNT, new string[](0));
    }

    function test_Join_RevertAmountExceedsAccountCap() public {
        // Update groupMaxJoinAmount to a small value
        vm.prank(groupOwner1, groupOwner1);
        groupManager.updateGroupInfo(
            address(token),
            ACTION_ID,
            groupId1,
            "Group1",
            MIN_JOIN_AMOUNT,
            5e18,
            0
        ); // maxJoinAmount = 5e18

        uint256 exceedingAmount = 6e18;
        setupUser(user1, exceedingAmount, address(groupTokenJoin));

        vm.prank(user1);
        vm.expectRevert(IGroupTokenJoin.AmountExceedsAccountCap.selector);
        groupTokenJoin.join(groupId1, exceedingAmount, new string[](0));
    }

    function test_Join_RevertGroupAccountsFull() public {
        // Limit group to 2 accounts
        vm.prank(groupOwner1, groupOwner1);
        groupManager.updateGroupInfo(
            address(token),
            ACTION_ID,
            groupId1,
            "Group1",
            MIN_JOIN_AMOUNT,
            0,
            2
        );

        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupTokenJoin));
        setupUser(user2, joinAmount, address(groupTokenJoin));
        setupUser(user3, joinAmount, address(groupTokenJoin));

        vm.prank(user1);
        groupTokenJoin.join(groupId1, joinAmount, new string[](0));

        vm.prank(user2);
        groupTokenJoin.join(groupId1, joinAmount, new string[](0));

        vm.prank(user3);
        vm.expectRevert(IGroupTokenJoin.GroupAccountsFull.selector);
        groupTokenJoin.join(groupId1, joinAmount, new string[](0));
    }

    // ============ exit Tests ============

    function test_Exit_Success() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupTokenJoin));

        vm.prank(user1);
        groupTokenJoin.join(groupId1, joinAmount, new string[](0));

        uint256 balanceBefore = token.balanceOf(user1);

        vm.prank(user1);
        groupTokenJoin.exit();

        assertEq(token.balanceOf(user1), balanceBefore + joinAmount);
        (, uint256 amount, uint256 groupId) = groupTokenJoin.joinInfo(user1);
        assertEq(amount, 0);
        assertEq(groupId, 0);
        assertEq(groupTokenJoin.totalJoinedAmount(), 0);
    }

    function test_Exit_RevertNotInGroup() public {
        vm.prank(user1);
        vm.expectRevert(IGroupTokenJoin.NotInGroup.selector);
        groupTokenJoin.exit();
    }

    // ============ View Functions Tests ============

    function test_JoinInfo() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupTokenJoin));

        vm.prank(user1);
        groupTokenJoin.join(groupId1, joinAmount, new string[](0));

        (uint256 joinedRound, uint256 amount, uint256 groupId) = groupTokenJoin
            .joinInfo(user1);
        assertEq(joinedRound, verify.currentRound());
        assertEq(amount, joinAmount);
        assertEq(groupId, groupId1);
    }

    function test_AccountsByGroupId() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupTokenJoin));
        setupUser(user2, joinAmount, address(groupTokenJoin));

        vm.prank(user1);
        groupTokenJoin.join(groupId1, joinAmount, new string[](0));

        vm.prank(user2);
        groupTokenJoin.join(groupId1, joinAmount, new string[](0));

        address[] memory accounts = groupTokenJoin.accountsByGroupId(groupId1);
        assertEq(accounts.length, 2);
        assertEq(groupTokenJoin.accountsByGroupIdCount(groupId1), 2);
        assertEq(groupTokenJoin.accountsByGroupIdAtIndex(groupId1, 0), user1);
        assertEq(groupTokenJoin.accountsByGroupIdAtIndex(groupId1, 1), user2);
    }

    function test_GroupIdByAccountByRound() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupTokenJoin));

        vm.prank(user1);
        groupTokenJoin.join(groupId1, joinAmount, new string[](0));

        uint256 currentRound = verify.currentRound();
        assertEq(
            groupTokenJoin.groupIdByAccountByRound(user1, currentRound),
            groupId1
        );
    }

    function test_TotalJoinedAmountByGroupIdByRound() public {
        uint256 joinAmount1 = 10e18;
        uint256 joinAmount2 = 20e18;
        setupUser(user1, joinAmount1, address(groupTokenJoin));
        setupUser(user2, joinAmount2, address(groupTokenJoin));

        vm.prank(user1);
        groupTokenJoin.join(groupId1, joinAmount1, new string[](0));

        vm.prank(user2);
        groupTokenJoin.join(groupId1, joinAmount2, new string[](0));

        uint256 currentRound = verify.currentRound();
        assertEq(
            groupTokenJoin.totalJoinedAmountByGroupIdByRound(
                groupId1,
                currentRound
            ),
            joinAmount1 + joinAmount2
        );
    }

    function test_TotalJoinedAmountByRound() public {
        uint256 joinAmount1 = 10e18;
        uint256 joinAmount2 = 20e18;
        setupUser(user1, joinAmount1, address(groupTokenJoin));
        setupUser(user2, joinAmount2, address(groupTokenJoin));

        vm.prank(user1);
        groupTokenJoin.join(groupId1, joinAmount1, new string[](0));

        vm.prank(user2);
        groupTokenJoin.join(groupId2, joinAmount2, new string[](0));

        uint256 currentRound = verify.currentRound();
        assertEq(
            groupTokenJoin.totalJoinedAmountByRound(currentRound),
            joinAmount1 + joinAmount2
        );
    }

    // ============ Account Management Tests ============

    function test_AccountsUpdatedOnJoin() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupTokenJoin));

        assertEq(groupTokenJoin.getAccounts().length, 0);

        vm.prank(user1);
        groupTokenJoin.join(groupId1, joinAmount, new string[](0));

        address[] memory accounts = groupTokenJoin.getAccounts();
        assertEq(accounts.length, 1);
        assertEq(accounts[0], user1);
    }

    function test_AccountsUpdatedOnExit() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupTokenJoin));

        vm.prank(user1);
        groupTokenJoin.join(groupId1, joinAmount, new string[](0));

        vm.prank(user1);
        groupTokenJoin.exit();

        assertEq(groupTokenJoin.getAccounts().length, 0);
    }

    // ============ Multiple Users Tests ============

    function test_MultipleUsersJoinSameGroup() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupTokenJoin));
        setupUser(user2, joinAmount, address(groupTokenJoin));
        setupUser(user3, joinAmount, address(groupTokenJoin));

        vm.prank(user1);
        groupTokenJoin.join(groupId1, joinAmount, new string[](0));

        vm.prank(user2);
        groupTokenJoin.join(groupId1, joinAmount, new string[](0));

        vm.prank(user3);
        groupTokenJoin.join(groupId1, joinAmount, new string[](0));

        assertEq(groupTokenJoin.totalJoinedAmount(), joinAmount * 3);
        assertEq(groupTokenJoin.accountsByGroupIdCount(groupId1), 3);
    }

    function test_UsersJoinDifferentGroups() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupTokenJoin));
        setupUser(user2, joinAmount, address(groupTokenJoin));

        vm.prank(user1);
        groupTokenJoin.join(groupId1, joinAmount, new string[](0));

        vm.prank(user2);
        groupTokenJoin.join(groupId2, joinAmount, new string[](0));

        assertEq(groupTokenJoin.accountsByGroupIdCount(groupId1), 1);
        assertEq(groupTokenJoin.accountsByGroupIdCount(groupId2), 1);
    }

    function test_UserExitFromMiddle() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupTokenJoin));
        setupUser(user2, joinAmount, address(groupTokenJoin));
        setupUser(user3, joinAmount, address(groupTokenJoin));

        vm.prank(user1);
        groupTokenJoin.join(groupId1, joinAmount, new string[](0));

        vm.prank(user2);
        groupTokenJoin.join(groupId1, joinAmount, new string[](0));

        vm.prank(user3);
        groupTokenJoin.join(groupId1, joinAmount, new string[](0));

        // user2 exits (middle user)
        vm.prank(user2);
        groupTokenJoin.exit();

        assertEq(groupTokenJoin.accountsByGroupIdCount(groupId1), 2);
        // user3 should now be at index 1 (swapped with exiting user2)
        address[] memory accounts = groupTokenJoin.accountsByGroupId(groupId1);
        assertTrue(accounts[0] == user1 || accounts[1] == user1);
        assertTrue(accounts[0] == user3 || accounts[1] == user3);
    }
}
