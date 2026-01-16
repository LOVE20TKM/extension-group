// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "./utils/BaseGroupTest.sol";
import {ExtensionGroupAction} from "../src/ExtensionGroupAction.sol";
import {IGroupJoin} from "../src/interface/IGroupJoin.sol";

contract GroupJoinTest is BaseGroupTest {
    ExtensionGroupAction public groupAction;
    uint256 public groupId1;
    uint256 public groupId2;

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

    function test_IsAccountInRangeByRound() public {
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

    function test_Join_RevertOnZeroAmount() public {
        setupUser(user1, 1e18, address(groupJoin));
        uint256 joinAmount = 0;

        vm.prank(user1);
        vm.expectRevert(IGroupJoin.JoinAmountZero.selector);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );
    }

    function test_Join_RevertOnAlreadyInOtherGroup() public {
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
        vm.expectRevert(IGroupJoin.AlreadyInOtherGroup.selector);
        groupJoin.join(
            address(groupAction),
            groupId2,
            joinAmount,
            new string[](0)
        );
    }

    function test_Join_RevertOnDeactivatedGroup() public {
        advanceRound();
        vm.prank(groupOwner1);
        groupManager.deactivateGroup(address(groupAction), groupId1);

        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));

        vm.prank(user1);
        vm.expectRevert(IGroupJoin.CannotJoinInactiveGroup.selector);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );
    }

    function test_Join_RevertOnBelowMinimum() public {
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
        vm.expectRevert(IGroupJoin.AmountBelowMinimum.selector);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );
    }

    function test_Join_RevertOnGroupMaxJoinAmount() public {
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
        vm.expectRevert(IGroupJoin.AmountExceedsAccountCap.selector);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );
    }

    function test_Join_RevertOnGroupAccountsFull() public {
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
        vm.expectRevert(IGroupJoin.GroupAccountsFull.selector);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );
    }

    function test_Join_RevertOnGroupCapacityExceeded() public {
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
        vm.expectRevert(IGroupJoin.GroupCapacityExceeded.selector);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount2,
            new string[](0)
        );
    }

    function test_Join_RevertOnOwnerCapacityExceeded() public {
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
        vm.expectRevert(IGroupJoin.OwnerCapacityExceeded.selector);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );
    }

    function test_Join_RevertOnExtensionAccountCap() public {
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
        vm.expectRevert(IGroupJoin.AmountExceedsAccountCap.selector);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );
    }

    function test_Exit_RevertOnNotJoined() public {
        vm.prank(user1);
        vm.expectRevert(IGroupJoin.NotJoinedAction.selector);
        groupJoin.exit(address(groupAction));
    }

    function test_JoinInfo_ReturnsLatestValues() public {
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

    function test_RoundHistory_JoinAndIncreaseAmount() public {
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

    function test_RoundHistory_ExitUpdates() public {
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

    function test_TrialJoin_UsesProviderEscrowAndExitRefundsProvider() public {
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

        (address inUseAccount, uint256 inUseAmount) = groupJoin
            .trialAccountsInUseByProviderAtIndex(
                address(groupAction),
                groupId1,
                provider,
                0
            );
        assertEq(inUseAccount, user1, "in-use account should be user1");
        assertEq(inUseAmount, trialAmount, "in-use amount should match");

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

    function test_TrialJoin_RevertOnJoinAfterTrial() public {
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
        vm.expectRevert(IGroupJoin.TrialJoinLocked.selector);
        groupJoin.join(address(groupAction), groupId1, 1e18, new string[](0));
    }

    function test_ExitOnBehalf_ByProvider() public {
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
        groupJoin.trialWaitingListAdd(
            address(groupAction),
            groupId1,
            trialAccounts,
            trialAmounts
        );
    }

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
