// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "../utils/BaseGroupTest.sol";
import {GroupTokenJoin} from "../../src/base/GroupTokenJoin.sol";
import {GroupCore} from "../../src/base/GroupCore.sol";
import {IGroupTokenJoin} from "../../src/interface/base/IGroupTokenJoin.sol";
import {IGroupCore} from "../../src/interface/base/IGroupCore.sol";
import {ExtensionAccounts} from "@extension/src/base/ExtensionAccounts.sol";

/**
 * @title MockGroupTokenJoin
 * @notice Concrete implementation of GroupTokenJoin for testing
 */
contract MockGroupTokenJoin is GroupTokenJoin, ExtensionAccounts {
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
        GroupTokenJoin(tokenAddress_)
    {}

    function _addAccount(address account) internal override(ExtensionAccounts, GroupTokenJoin) {
        ExtensionAccounts._addAccount(account);
    }

    function _removeAccount(address account) internal override(ExtensionAccounts, GroupTokenJoin) {
        ExtensionAccounts._removeAccount(account);
    }

    function isJoinedValueCalculated() external pure returns (bool) {
        return false;
    }

    function joinedValue() external view returns (uint256) {
        return totalJoinedAmount();
    }

    function joinedValueByAccount(address account) external view returns (uint256) {
        return _joinInfo[account].amount;
    }

    function _calculateReward(uint256, address) internal pure override returns (uint256) {
        return 0;
    }

    // Expose for testing
    function getAccounts() external view returns (address[] memory) {
        return this.accounts();
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
            address(group),
            address(token),
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
        mockFactory.registerExtension(address(groupTokenJoin), address(token));

        // Setup group owners
        groupId1 = setupGroupOwner(groupOwner1, 10000e18, "TestGroup1");
        groupId2 = setupGroupOwner(groupOwner2, 10000e18, "TestGroup2");

        // Prepare extension init
        prepareExtensionInit(address(groupTokenJoin), address(token), ACTION_ID);

        // Activate groups
        uint256 stakeAmount = 10000e18;
        setupUser(groupOwner1, stakeAmount, address(groupTokenJoin));
        setupUser(groupOwner2, stakeAmount, address(groupTokenJoin));

        vm.prank(groupOwner1);
        groupTokenJoin.activateGroup(groupId1, "Group1", stakeAmount, MIN_JOIN_AMOUNT, 0);

        vm.prank(groupOwner2);
        groupTokenJoin.activateGroup(groupId2, "Group2", stakeAmount, MIN_JOIN_AMOUNT, 0);
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
        groupTokenJoin.join(groupId1, joinAmount);

        (uint256 joinedRound, uint256 amount, uint256 groupId) = groupTokenJoin.joinInfo(user1);
        assertEq(amount, joinAmount);
        assertEq(groupId, groupId1);
        assertEq(joinedRound, verify.currentRound());

        assertEq(groupTokenJoin.totalJoinedAmount(), joinAmount);
    }

    function test_Join_AddMoreTokens() public {
        uint256 initialAmount = 10e18;
        uint256 additionalAmount = 5e18;
        setupUser(user1, initialAmount + additionalAmount, address(groupTokenJoin));

        vm.startPrank(user1);
        groupTokenJoin.join(groupId1, initialAmount);
        groupTokenJoin.join(groupId1, additionalAmount);
        vm.stopPrank();

        (, uint256 amount, ) = groupTokenJoin.joinInfo(user1);
        assertEq(amount, initialAmount + additionalAmount);
    }

    function test_Join_RevertAmountZero() public {
        setupUser(user1, 100e18, address(groupTokenJoin));

        vm.prank(user1);
        vm.expectRevert(IGroupTokenJoin.JoinAmountZero.selector);
        groupTokenJoin.join(groupId1, 0);
    }

    function test_Join_RevertAlreadyInOtherGroup() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount * 2, address(groupTokenJoin));

        vm.startPrank(user1);
        groupTokenJoin.join(groupId1, joinAmount);

        vm.expectRevert(IGroupTokenJoin.AlreadyInOtherGroup.selector);
        groupTokenJoin.join(groupId2, joinAmount);
        vm.stopPrank();
    }

    function test_Join_RevertCannotJoinDeactivatedGroup() public {
        advanceRound();
        // Setup actionIds for new round
        vote.setVotedActionIds(address(token), verify.currentRound(), ACTION_ID);

        vm.prank(groupOwner1);
        groupTokenJoin.deactivateGroup(groupId1);

        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupTokenJoin));

        vm.prank(user1);
        vm.expectRevert(IGroupTokenJoin.CannotJoinDeactivatedGroup.selector);
        groupTokenJoin.join(groupId1, joinAmount);
    }

    function test_Join_RevertAmountBelowMinimum() public {
        uint256 tooLowAmount = MIN_JOIN_AMOUNT / 2;
        setupUser(user1, tooLowAmount, address(groupTokenJoin));

        vm.prank(user1);
        vm.expectRevert(IGroupTokenJoin.AmountBelowMinimum.selector);
        groupTokenJoin.join(groupId1, tooLowAmount);
    }

    function test_Join_RevertGroupCapacityFull() public {
        // Get current capacity
        IGroupCore.GroupInfo memory info = groupTokenJoin.groupInfo(groupId1);
        uint256 capacity = info.capacity;
        uint256 maxPerAccount = groupTokenJoin.calculateJoinMaxAmount();

        // Calculate exact number needed to fill and amount for last user
        uint256 fullUsers = capacity / maxPerAccount;
        uint256 remaining = capacity % maxPerAccount;

        // Fill capacity
        for (uint256 i = 0; i < fullUsers; i++) {
            address testUser = address(uint160(0x1000 + i));
            setupUser(testUser, maxPerAccount, address(groupTokenJoin));
            vm.prank(testUser);
            groupTokenJoin.join(groupId1, maxPerAccount);
        }

        // If there's remaining space that's >= MIN_JOIN_AMOUNT, fill it
        if (remaining >= MIN_JOIN_AMOUNT) {
            address partialUser = address(uint160(0x1000 + fullUsers));
            setupUser(partialUser, remaining, address(groupTokenJoin));
            vm.prank(partialUser);
            groupTokenJoin.join(groupId1, remaining);
        }

        // Now capacity should be full - try to join with another user
        address extraUser = address(uint160(0x2000));
        setupUser(extraUser, MIN_JOIN_AMOUNT, address(groupTokenJoin));

        vm.prank(extraUser);
        vm.expectRevert(IGroupTokenJoin.GroupCapacityFull.selector);
        groupTokenJoin.join(groupId1, MIN_JOIN_AMOUNT);
    }

    function test_Join_RevertAmountExceedsAccountCap() public {
        // Update groupMaxJoinAmount to a small value
        vm.prank(groupOwner1);
        groupTokenJoin.updateGroupInfo(groupId1, "Group1", MIN_JOIN_AMOUNT, 5e18); // maxJoinAmount = 5e18

        uint256 exceedingAmount = 6e18;
        setupUser(user1, exceedingAmount, address(groupTokenJoin));

        vm.prank(user1);
        vm.expectRevert(IGroupTokenJoin.AmountExceedsAccountCap.selector);
        groupTokenJoin.join(groupId1, exceedingAmount);
    }

    // ============ exit Tests ============

    function test_Exit_Success() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupTokenJoin));

        vm.prank(user1);
        groupTokenJoin.join(groupId1, joinAmount);

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
        groupTokenJoin.join(groupId1, joinAmount);

        (uint256 joinedRound, uint256 amount, uint256 groupId) = groupTokenJoin.joinInfo(user1);
        assertEq(joinedRound, verify.currentRound());
        assertEq(amount, joinAmount);
        assertEq(groupId, groupId1);
    }

    function test_AccountsByGroupId() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupTokenJoin));
        setupUser(user2, joinAmount, address(groupTokenJoin));

        vm.prank(user1);
        groupTokenJoin.join(groupId1, joinAmount);

        vm.prank(user2);
        groupTokenJoin.join(groupId1, joinAmount);

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
        groupTokenJoin.join(groupId1, joinAmount);

        uint256 currentRound = verify.currentRound();
        assertEq(groupTokenJoin.groupIdByAccountByRound(user1, currentRound), groupId1);
    }

    function test_TotalJoinedAmountByGroupIdByRound() public {
        uint256 joinAmount1 = 10e18;
        uint256 joinAmount2 = 20e18;
        setupUser(user1, joinAmount1, address(groupTokenJoin));
        setupUser(user2, joinAmount2, address(groupTokenJoin));

        vm.prank(user1);
        groupTokenJoin.join(groupId1, joinAmount1);

        vm.prank(user2);
        groupTokenJoin.join(groupId1, joinAmount2);

        uint256 currentRound = verify.currentRound();
        assertEq(
            groupTokenJoin.totalJoinedAmountByGroupIdByRound(groupId1, currentRound),
            joinAmount1 + joinAmount2
        );
    }

    function test_TotalJoinedAmountByRound() public {
        uint256 joinAmount1 = 10e18;
        uint256 joinAmount2 = 20e18;
        setupUser(user1, joinAmount1, address(groupTokenJoin));
        setupUser(user2, joinAmount2, address(groupTokenJoin));

        vm.prank(user1);
        groupTokenJoin.join(groupId1, joinAmount1);

        vm.prank(user2);
        groupTokenJoin.join(groupId2, joinAmount2);

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
        groupTokenJoin.join(groupId1, joinAmount);

        address[] memory accounts = groupTokenJoin.getAccounts();
        assertEq(accounts.length, 1);
        assertEq(accounts[0], user1);
    }

    function test_AccountsUpdatedOnExit() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupTokenJoin));

        vm.prank(user1);
        groupTokenJoin.join(groupId1, joinAmount);

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
        groupTokenJoin.join(groupId1, joinAmount);

        vm.prank(user2);
        groupTokenJoin.join(groupId1, joinAmount);

        vm.prank(user3);
        groupTokenJoin.join(groupId1, joinAmount);

        assertEq(groupTokenJoin.totalJoinedAmount(), joinAmount * 3);
        assertEq(groupTokenJoin.accountsByGroupIdCount(groupId1), 3);
    }

    function test_UsersJoinDifferentGroups() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupTokenJoin));
        setupUser(user2, joinAmount, address(groupTokenJoin));

        vm.prank(user1);
        groupTokenJoin.join(groupId1, joinAmount);

        vm.prank(user2);
        groupTokenJoin.join(groupId2, joinAmount);

        assertEq(groupTokenJoin.accountsByGroupIdCount(groupId1), 1);
        assertEq(groupTokenJoin.accountsByGroupIdCount(groupId2), 1);
    }

    function test_UserExitFromMiddle() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupTokenJoin));
        setupUser(user2, joinAmount, address(groupTokenJoin));
        setupUser(user3, joinAmount, address(groupTokenJoin));

        vm.prank(user1);
        groupTokenJoin.join(groupId1, joinAmount);

        vm.prank(user2);
        groupTokenJoin.join(groupId1, joinAmount);

        vm.prank(user3);
        groupTokenJoin.join(groupId1, joinAmount);

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

