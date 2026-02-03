// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "./utils/BaseGroupTest.sol";
import {ExtensionGroupService} from "../src/ExtensionGroupService.sol";
import {ExtensionGroupAction} from "../src/ExtensionGroupAction.sol";
import {IGroupService} from "../src/interface/IGroupService.sol";
import {IGroupServiceEvents} from "../src/interface/IGroupService.sol";
import {IGroupServiceErrors} from "../src/interface/IGroupService.sol";
import {GroupManager} from "../src/GroupManager.sol";
import {GroupJoin} from "../src/GroupJoin.sol";
import {GroupVerify} from "../src/GroupVerify.sol";
import {IGroupManager} from "../src/interface/IGroupManager.sol";
import {IGroupJoin} from "../src/interface/IGroupJoin.sol";
import {IGroupVerify} from "../src/interface/IGroupVerify.sol";
import {IJoin} from "@extension/src/interface/IJoin.sol";
import {IReward} from "@extension/src/interface/IReward.sol";
import {IRewardEvents} from "@extension/src/interface/IReward.sol";
import {IRewardErrors} from "@extension/src/interface/IReward.sol";

import {IExtensionErrors} from "@extension/src/interface/IExtension.sol";
import {
    MockExtensionFactory
} from "@extension/test/mocks/MockExtensionFactory.sol";
import {
    ExtensionGroupActionFactory
} from "../src/ExtensionGroupActionFactory.sol";
import {MockERC20} from "@extension/test/mocks/MockERC20.sol";
import {MockUniswapV2Pair} from "@extension/test/mocks/MockUniswapV2Pair.sol";
import {
    RoundHistoryAddressArray
} from "@extension/src/lib/RoundHistoryAddressArray.sol";
import {
    RoundHistoryUint256Array
} from "@extension/src/lib/RoundHistoryUint256Array.sol";

/**
 * @title ExtensionGroupServiceTest
 * @notice Test suite for ExtensionGroupService
 */
contract ExtensionGroupServiceTest is BaseGroupTest, IGroupServiceEvents {
    ExtensionGroupService public groupService;
    ExtensionGroupAction public groupAction;
    ExtensionGroupActionFactory public actionFactory;
    MockExtensionFactory public serviceFactory;
    GroupManager public newGroupManager;
    GroupJoin public newGroupJoin;
    GroupVerify public newGroupVerify;

    uint256 public groupId1;
    uint256 public groupId2;

    uint256 constant MAX_RECIPIENTS = 10;
    uint256 constant SERVICE_ACTION_ID = 2;

    function setUp() public {
        setUpBase();

        // Create new singleton instances for this test (not using BaseGroupTest's instances)
        // because ExtensionGroupActionFactory constructor will initialize them
        newGroupManager = new GroupManager();
        newGroupJoin = new GroupJoin();
        newGroupVerify = new GroupVerify();

        // Deploy actionFactory with new singleton instances
        actionFactory = new ExtensionGroupActionFactory(
            address(center),
            address(newGroupManager),
            address(newGroupJoin),
            address(newGroupVerify),
            address(group)
        );
        // Initialize singletons after factory is fully constructed
        IGroupManager(address(newGroupManager)).initialize(
            address(actionFactory)
        );
        IGroupJoin(address(newGroupJoin)).initialize(address(actionFactory));
        IGroupVerify(address(newGroupVerify)).initialize(
            address(actionFactory)
        );
        serviceFactory = new MockExtensionFactory(address(center));

        // Create GroupAction using factory
        token.mint(address(this), 2e18);
        token.approve(address(actionFactory), type(uint256).max);
        address groupActionAddress = actionFactory.createExtension(
            address(token), // tokenAddress
            address(token), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            ACTIVATION_MIN_GOV_RATIO
        );
        groupAction = ExtensionGroupAction(groupActionAddress);

        // Deploy GroupService (use actionFactory as GROUP_ACTION_FACTORY_ADDRESS)
        token.approve(address(serviceFactory), type(uint256).max);
        groupService = new ExtensionGroupService(
            address(serviceFactory),
            address(token),
            address(token), // groupActionTokenAddress
            address(actionFactory),
            0 // govRatioMultiplier = 0 means no cap
        );
        serviceFactory.registerExtension(address(groupService), address(token));

        // Setup group owners
        groupId1 = setupGroupOwner(groupOwner1, 10000e18, "TestGroup1");
        groupId2 = setupGroupOwner(groupOwner2, 10000e18, "TestGroup2");

        // Prepare extension init for groupAction (config already set in GroupCore constructor)
        prepareExtensionInit(address(groupAction), address(token), ACTION_ID);

        // Prepare extension init for groupService
        prepareExtensionInit(
            address(groupService),
            address(token),
            SERVICE_ACTION_ID
        );

        // Activate groups
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(newGroupManager)
        );
        setupUser(
            groupOwner2,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(newGroupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        newGroupManager.activateGroup(
            address(groupAction),
            groupId1,
            "Group1",
            0, // maxCapacity
            1e18, // minJoinAmount
            0,
            0
        );

        vm.prank(groupOwner2, groupOwner2);
        newGroupManager.activateGroup(
            address(groupAction),
            groupId2,
            "Group2",
            0, // maxCapacity
            1e18, // minJoinAmount
            0,
            0
        );
    }

    /**
     * @notice Helper to setup group action with verified scores
     */
    function setupGroupActionWithScores(
        uint256 groupId,
        address owner,
        address member,
        uint256 amount,
        uint256 score
    ) internal {
        setupUser(member, amount, address(newGroupJoin));

        vm.prank(member);
        newGroupJoin.join(
            address(groupAction),
            groupId,
            amount,
            new string[](0)
        );

        // Advance round and setup actionIds for new round
        uint256[] memory scores = new uint256[](1);
        scores[0] = score;

        vm.prank(owner);
        newGroupVerify.submitOriginScores(
            address(groupAction),
            groupId,
            0,
            scores
        );
    }

    /**
     * @notice Helper to setup actionIds for current round after advanceRound
     */
    function _setupActionIdsForCurrentRound() internal {
        uint256 currentRound = verify.currentRound();
        vote.setVotedActionIds(address(token), currentRound, ACTION_ID);
        vote.setVotedActionIds(address(token), currentRound, SERVICE_ACTION_ID);
        // Set votes for this round
        vote.setVotesNum(address(token), currentRound, 10000e18);
        vote.setVotesNumByActionId(
            address(token),
            currentRound,
            ACTION_ID,
            10000e18
        );
        vote.setVotesNumByActionId(
            address(token),
            currentRound,
            SERVICE_ACTION_ID,
            10000e18
        );
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsImmutables() public view {
        assertEq(groupService.GROUP_ACTION_TOKEN_ADDRESS(), address(token));
        assertEq(
            groupService.GROUP_ACTION_FACTORY_ADDRESS(),
            address(actionFactory)
        );
        assertEq(groupService.DEFAULT_MAX_RECIPIENTS(), MAX_RECIPIENTS);
    }

    // ============ join Tests ============

    function test_Join_Success() public {
        // Setup group action first
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        // Group owner joins service
        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // Verify joined
        assertTrue(center.accountsCount(address(token), SERVICE_ACTION_ID) > 0);
    }

    function test_Join_RevertNoActiveGroups() public {
        // groupOwner1 has no staked amount in groupAction
        // Need to deactivate the group first
        advanceRound();
        _setupActionIdsForCurrentRound();

        vm.prank(groupOwner1, groupOwner1);
        newGroupManager.deactivateGroup(address(groupAction), groupId1);

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupServiceErrors.NoActiveGroups.selector);
        groupService.join(new string[](0));
    }

    // ============ setRecipients Tests ============

    function test_SetRecipients_Success() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        address[] memory recipients = new address[](2);
        recipients[0] = address(0x100);
        recipients[1] = address(0x200);

        uint256[] memory ratios = new uint256[](2);
        ratios[0] = 3e17; // 30%
        ratios[1] = 2e17; // 20%

        vm.prank(groupOwner1);
        groupService.setRecipients(ACTION_ID, groupId1, recipients, ratios);

        uint256 round = verify.currentRound();
        (address[] memory addrs, uint256[] memory points) = groupService
            .recipients(groupOwner1, ACTION_ID, groupId1, round);

        assertEq(addrs.length, 2);
        assertEq(addrs[0], recipients[0]);
        assertEq(addrs[1], recipients[1]);
        assertEq(points[0], 3e17);
        assertEq(points[1], 2e17);
    }

    function test_SetRecipients_RevertNotGroupOwner() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // groupOwner2 also joins service
        setupGroupActionWithScores(groupId2, groupOwner2, user2, 10e18, 80);
        vm.prank(groupOwner2);
        groupService.join(new string[](0));

        address[] memory recipients = new address[](1);
        recipients[0] = address(0x100);

        uint256[] memory ratios = new uint256[](1);
        ratios[0] = 5e17;

        // groupOwner2 tries to set recipients for groupId1 (owned by groupOwner1)
        vm.prank(groupOwner2);
        vm.expectRevert(IGroupServiceErrors.NotGroupOwner.selector);
        groupService.setRecipients(ACTION_ID, groupId1, recipients, ratios);
    }

    function test_SetRecipients_RevertArrayLengthMismatch() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        address[] memory recipients = new address[](2);
        recipients[0] = address(0x100);
        recipients[1] = address(0x200);

        uint256[] memory ratios = new uint256[](1);
        ratios[0] = 5e17;

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupServiceErrors.ArrayLengthMismatch.selector);
        groupService.setRecipients(ACTION_ID, groupId1, recipients, ratios);
    }

    function test_SetRecipients_RevertTooManyRecipients() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        address[] memory recipients = new address[](MAX_RECIPIENTS + 1);
        uint256[] memory ratios = new uint256[](MAX_RECIPIENTS + 1);

        for (uint256 i = 0; i < MAX_RECIPIENTS + 1; i++) {
            recipients[i] = address(uint160(0x100 + i));
            ratios[i] = 1e16;
        }

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupServiceErrors.TooManyRecipients.selector);
        groupService.setRecipients(ACTION_ID, groupId1, recipients, ratios);
    }

    function test_SetRecipients_RevertZeroAddress() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        address[] memory recipients = new address[](1);
        recipients[0] = address(0);

        uint256[] memory ratios = new uint256[](1);
        ratios[0] = 5e17;

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupServiceErrors.ZeroAddress.selector);
        groupService.setRecipients(ACTION_ID, groupId1, recipients, ratios);
    }

    function test_SetRecipients_RevertZeroRatio() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        address[] memory recipients = new address[](1);
        recipients[0] = address(0x100);

        uint256[] memory ratios = new uint256[](1);
        ratios[0] = 0;

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupServiceErrors.ZeroRatio.selector);
        groupService.setRecipients(ACTION_ID, groupId1, recipients, ratios);
    }

    function test_SetRecipients_RevertInvalidRatio() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        address[] memory recipients = new address[](2);
        recipients[0] = address(0x100);
        recipients[1] = address(0x200);

        uint256[] memory ratios = new uint256[](2);
        ratios[0] = 6e17; // 60%
        ratios[1] = 5e17; // 50% - total > 100%

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupServiceErrors.InvalidRatio.selector);
        groupService.setRecipients(ACTION_ID, groupId1, recipients, ratios);
    }

    function test_SetRecipients_RevertRecipientCannotBeSelf() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // Try to set self as recipient
        address[] memory recipients = new address[](1);
        recipients[0] = groupOwner1; // Self

        uint256[] memory ratios = new uint256[](1);
        ratios[0] = 5e17;

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupServiceErrors.RecipientCannotBeSelf.selector);
        groupService.setRecipients(ACTION_ID, groupId1, recipients, ratios);
    }

    // ============ recipients Tests ============

    function test_Recipients_HistoryByRound() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // Set recipients in round 1
        address[] memory recipients1 = new address[](1);
        recipients1[0] = address(0x100);
        uint256[] memory ratios1 = new uint256[](1);
        ratios1[0] = 3e17;

        vm.prank(groupOwner1);
        groupService.setRecipients(ACTION_ID, groupId1, recipients1, ratios1);

        uint256 round1 = verify.currentRound();

        // Advance round and setup actionIds for new round
        advanceRound();
        _setupActionIdsForCurrentRound();
        uint256 round2 = verify.currentRound();

        // Set different recipients in round 2
        address[] memory recipients2 = new address[](1);
        recipients2[0] = address(0x200);
        uint256[] memory ratios2 = new uint256[](1);
        ratios2[0] = 4e17;

        vm.prank(groupOwner1);
        groupService.setRecipients(ACTION_ID, groupId1, recipients2, ratios2);

        // Check round 1 recipients
        (address[] memory addrs1, uint256[] memory points1) = groupService
            .recipients(groupOwner1, ACTION_ID, groupId1, round1);
        assertEq(addrs1[0], address(0x100));
        assertEq(points1[0], 3e17);

        // Check round 2 recipients
        (address[] memory addrs2, uint256[] memory points2) = groupService
            .recipients(groupOwner1, ACTION_ID, groupId1, round2);
        assertEq(addrs2[0], address(0x200));
        assertEq(points2[0], 4e17);
    }

    // ============ rewardByRecipient Tests ============

    function test_RewardByRecipient_ForRecipient() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // Set recipients (30% to recipient)
        address recipient = address(0x100);
        address[] memory recipients = new address[](1);
        recipients[0] = recipient;
        uint256[] memory ratios = new uint256[](1);
        ratios[0] = 3e17; // 30%

        vm.prank(groupOwner1);
        groupService.setRecipients(ACTION_ID, groupId1, recipients, ratios);

        // Simulate reward (this would normally be set by the reward system)
        // For testing, we check the calculation logic
        uint256 round = verify.currentRound();

        // RewardByRecipient returns 0 if no reward set
        uint256 recipientReward = groupService.rewardByRecipient(
            round,
            groupOwner1,
            ACTION_ID,
            groupId1,
            recipient
        );
        // Since no reward is set, it should be 0
        assertEq(recipientReward, 0);
    }

    function test_RewardByRecipient_ForOwner() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // Set recipients (30% distributed)
        address recipient = address(0x100);
        address[] memory recipients = new address[](1);
        recipients[0] = recipient;
        uint256[] memory ratios = new uint256[](1);
        ratios[0] = 3e17; // 30%

        vm.prank(groupOwner1);
        groupService.setRecipients(ACTION_ID, groupId1, recipients, ratios);

        uint256 round = verify.currentRound();

        // Owner gets remaining (70%)
        uint256 ownerReward = groupService.rewardByRecipient(
            round,
            groupOwner1,
            ACTION_ID,
            groupId1,
            groupOwner1
        );
        assertEq(ownerReward, 0); // No reward set
    }

    // ============ rewardDistribution Tests ============

    function test_RewardDistribution() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // Set multiple recipients
        address[] memory recipients = new address[](2);
        recipients[0] = address(0x100);
        recipients[1] = address(0x200);
        uint256[] memory ratios = new uint256[](2);
        ratios[0] = 3e17; // 30%
        ratios[1] = 2e17; // 20%

        vm.prank(groupOwner1);
        groupService.setRecipients(ACTION_ID, groupId1, recipients, ratios);

        uint256 round = verify.currentRound();

        (
            address[] memory addrs,
            uint256[] memory points,
            uint256[] memory amounts,
            uint256 ownerAmount
        ) = groupService.rewardDistribution(
                round,
                groupOwner1,
                ACTION_ID,
                groupId1
            );

        assertEq(addrs.length, 2);
        assertEq(points.length, 2);
        assertEq(amounts.length, 2);
        // With no reward, all amounts should be 0
        assertEq(amounts[0], 0);
        assertEq(amounts[1], 0);
        assertEq(ownerAmount, 0);
    }

    // ============ claimReward Tests ============

    function test_ClaimReward_MarksClaimedAndRevertsOnSecondClaim() public {
        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        uint256 targetRound = 0;
        uint256 expectedReward = 0;
        verify.setCurrentRound(1);

        (uint256 rewardBefore, , bool isMintedBefore) = groupService
            .rewardByAccount(targetRound, groupOwner1);
        assertEq(rewardBefore, expectedReward);
        assertFalse(isMintedBefore);

        vm.prank(groupOwner1);
        groupService.claimReward(targetRound);

        (uint256 rewardAfter, , bool isMintedAfter) = groupService
            .rewardByAccount(targetRound, groupOwner1);
        assertEq(rewardAfter, expectedReward);
        assertTrue(isMintedAfter);

        vm.prank(groupOwner1);
        vm.expectRevert(IRewardErrors.AlreadyClaimed.selector);
        groupService.claimReward(targetRound);
    }

    // ============ IExtensionJoinedAmount Tests ============

    function test_JoinedAmount() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);
        setupGroupActionWithScores(groupId2, groupOwner2, user2, 20e18, 80);

        // joinedAmount should return totalStaked from groupManager
        // Both groupId1 and groupId2 are activated in setUp, each stakes GROUP_ACTIVATION_STAKE_AMOUNT
        uint256 expectedStaked = GROUP_ACTIVATION_STAKE_AMOUNT * 2;
        uint256 joinedVal = groupService.joinedAmount();
        assertEq(joinedVal, expectedStaked);
    }

    function test_JoinedAmountByAccount() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // groupOwner1 activated groupId1 in setUp, which staked GROUP_ACTIVATION_STAKE_AMOUNT
        uint256 expectedStaked = GROUP_ACTIVATION_STAKE_AMOUNT;
        uint256 ownerValue = groupService.joinedAmountByAccount(groupOwner1);
        assertEq(ownerValue, expectedStaked);

        // Non-joined account
        uint256 user2Value = groupService.joinedAmountByAccount(user2);
        assertEq(user2Value, 0);
    }

    function test_JoinedAmount_IncludesAllActions_NotJustVoted() public {
        // Setup first action (ACTION_ID = 0) with voting
        // Note: groupId1 and groupId2 are already activated in ACTION_ID during setUp
        // So we have activation stake for ACTION_ID

        // Setup second action (ACTION_ID = 1) without voting
        uint256 actionId2 = 1;
        address groupAction2Address = actionFactory.createExtension(
            address(token),
            address(token),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            ACTIVATION_MIN_GOV_RATIO
        );
        submit.setActionInfo(address(token), actionId2, groupAction2Address);
        address action2Author = actionFactory.extensionCreator(
            groupAction2Address
        );
        submit.setActionAuthor(address(token), actionId2, action2Author);
        token.mint(groupAction2Address, 1e18);

        // Add actionId2 to votedActionIds (required for activation) but don't set votes
        uint256 currentRound = join.currentRound();
        vote.setVotedActionIds(address(token), currentRound, actionId2);
        // Don't call vote.setVotesNumByActionId for actionId2, so it has 0 votes

        // Create a new group for groupOwner2 to activate in action2
        uint256 groupId3 = group.mint(groupOwner2, "TestGroup3");
        setupUser(
            groupOwner2,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(newGroupManager)
        );
        vm.prank(groupOwner2);
        newGroupManager.activateGroup(
            groupAction2Address,
            groupId3,
            "Group3",
            0,
            1e18,
            0,
            0
        );

        // Verify joinedAmount includes both actions (not just voted one)
        // Note: action1 has 2 activated groups (groupId1, groupId2), action2 has 1 (groupId3)
        // Each activation stakes GROUP_ACTIVATION_STAKE_AMOUNT
        uint256 expectedStake1 = GROUP_ACTIVATION_STAKE_AMOUNT * 2; // 2 groups activated in setUp
        uint256 expectedStake2 = GROUP_ACTIVATION_STAKE_AMOUNT; // 1 group activated in this test
        uint256 expectedTotal = expectedStake1 + expectedStake2;

        uint256 joinedVal = groupService.joinedAmount();
        assertEq(
            joinedVal,
            expectedTotal,
            "joinedAmount should include all actions, not just voted ones"
        );
        assertTrue(joinedVal > 0, "joinedVal should be greater than 0");
        // Verify action2's stake is included (1 activation stake)
        assertEq(
            newGroupManager.staked(groupAction2Address),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            "action2 should have 1 activation stake"
        );
    }

    function test_JoinedAmountByAccount_IncludesAllActions_NotJustVoted()
        public
    {
        // Setup first action (ACTION_ID = 0) with voting
        // Note: groupOwner1's groupId1 is already activated in ACTION_ID during setUp

        // Setup second action (ACTION_ID = 1) without voting
        uint256 actionId2 = 1;
        address groupAction2Address = actionFactory.createExtension(
            address(token),
            address(token),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            ACTIVATION_MIN_GOV_RATIO
        );
        submit.setActionInfo(address(token), actionId2, groupAction2Address);
        address action2Author = actionFactory.extensionCreator(
            groupAction2Address
        );
        submit.setActionAuthor(address(token), actionId2, action2Author);
        token.mint(groupAction2Address, 1e18);

        // Add actionId2 to votedActionIds (required for activation) but don't set votes
        uint256 currentRound = join.currentRound();
        vote.setVotedActionIds(address(token), currentRound, actionId2);
        // Don't call vote.setVotesNumByActionId for actionId2, so it has 0 votes

        // Create a new group for groupOwner1 to activate in action2
        uint256 groupId3 = group.mint(groupOwner1, "TestGroup3");
        token.mint(groupOwner1, GROUP_ACTIVATION_STAKE_AMOUNT);
        vm.prank(groupOwner1);
        token.approve(address(newGroupManager), GROUP_ACTIVATION_STAKE_AMOUNT);
        vm.prank(groupOwner1);
        newGroupManager.activateGroup(
            groupAction2Address,
            groupId3,
            "Group3",
            0,
            1e18,
            0,
            0
        );

        // Join service
        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // Verify joinedAmountByAccount includes both actions
        // groupOwner1 has groups in both actions:
        // - groupId1 in ACTION_ID (activated in setUp): GROUP_ACTIVATION_STAKE_AMOUNT
        // - groupId3 in actionId2 (activated in this test): GROUP_ACTIVATION_STAKE_AMOUNT
        uint256 expectedStake1 = GROUP_ACTIVATION_STAKE_AMOUNT; // groupId1
        uint256 expectedStake2 = GROUP_ACTIVATION_STAKE_AMOUNT; // groupId3
        uint256 expectedTotal = expectedStake1 + expectedStake2;
        uint256 ownerValue = groupService.joinedAmountByAccount(groupOwner1);
        assertEq(
            ownerValue,
            expectedTotal,
            "joinedAmountByAccount should include all actions, not just voted ones"
        );
        // Verify groupOwner1 has stake in action2
        assertEq(
            newGroupManager.stakedByOwner(groupAction2Address, groupOwner1),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            "groupOwner1 should have stake in action2"
        );
    }

    // ============ Event Tests ============

    function test_SetRecipients_EmitsEvent() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        address[] memory recipients = new address[](1);
        recipients[0] = address(0x100);
        uint256[] memory ratios = new uint256[](1);
        ratios[0] = 3e17;

        uint256 round = verify.currentRound();

        vm.expectEmit(true, true, true, true);
        emit IGroupServiceEvents.UpdateRecipients(
            address(token),
            round,
            ACTION_ID,
            groupId1,
            groupOwner1,
            recipients,
            ratios
        );

        vm.prank(groupOwner1);
        groupService.setRecipients(ACTION_ID, groupId1, recipients, ratios);
    }

    // ============ Multiple Group Owners Tests ============

    function test_MultipleGroupOwners() public {
        // Setup both group owners with verified groups
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);
        setupGroupActionWithScores(groupId2, groupOwner2, user2, 20e18, 90);

        // Both owners join service
        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        vm.prank(groupOwner2);
        groupService.join(new string[](0));

        // Both set different recipients for their groups
        address[] memory recipients1 = new address[](1);
        recipients1[0] = address(0x100);
        uint256[] memory ratios1 = new uint256[](1);
        ratios1[0] = 3e17;

        vm.prank(groupOwner1);
        groupService.setRecipients(ACTION_ID, groupId1, recipients1, ratios1);

        address[] memory recipients2 = new address[](1);
        recipients2[0] = address(0x200);
        uint256[] memory ratios2 = new uint256[](1);
        ratios2[0] = 4e17;

        vm.prank(groupOwner2);
        groupService.setRecipients(ACTION_ID, groupId2, recipients2, ratios2);

        // Verify independent recipients
        uint256 round = verify.currentRound();

        (address[] memory addrs1, ) = groupService.recipients(
            groupOwner1,
            ACTION_ID,
            groupId1,
            round
        );
        (address[] memory addrs2, ) = groupService.recipients(
            groupOwner2,
            ACTION_ID,
            groupId2,
            round
        );

        assertEq(addrs1[0], address(0x100));
        assertEq(addrs2[0], address(0x200));
    }

    // ============ Edge Cases ============

    function test_EmptyRecipients() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // Set empty recipients (owner keeps all)
        address[] memory recipients = new address[](0);
        uint256[] memory ratios = new uint256[](0);

        vm.prank(groupOwner1);
        groupService.setRecipients(ACTION_ID, groupId1, recipients, ratios);

        uint256 round = verify.currentRound();
        (address[] memory addrs, uint256[] memory points) = groupService
            .recipients(groupOwner1, ACTION_ID, groupId1, round);

        assertEq(addrs.length, 0);
        assertEq(points.length, 0);
    }

    function test_UpdateRecipientsSameRound() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // First set
        address[] memory recipients1 = new address[](1);
        recipients1[0] = address(0x100);
        uint256[] memory ratios1 = new uint256[](1);
        ratios1[0] = 3e17;

        vm.prank(groupOwner1);
        groupService.setRecipients(ACTION_ID, groupId1, recipients1, ratios1);

        // Update in same round
        address[] memory recipients2 = new address[](1);
        recipients2[0] = address(0x200);
        uint256[] memory ratios2 = new uint256[](1);
        ratios2[0] = 5e17;

        vm.prank(groupOwner1);
        groupService.setRecipients(ACTION_ID, groupId1, recipients2, ratios2);

        uint256 round = verify.currentRound();
        (address[] memory addrs, uint256[] memory points) = groupService
            .recipients(groupOwner1, ACTION_ID, groupId1, round);

        assertEq(addrs[0], address(0x200));
        assertEq(points[0], 5e17);
    }

    function test_MaxRatios() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // 100% to recipients
        address[] memory recipients = new address[](1);
        recipients[0] = address(0x100);
        uint256[] memory ratios = new uint256[](1);
        ratios[0] = 1e18; // 100%

        vm.prank(groupOwner1);
        groupService.setRecipients(ACTION_ID, groupId1, recipients, ratios);

        uint256 round = verify.currentRound();
        (address[] memory addrs, uint256[] memory points) = groupService
            .recipients(groupOwner1, ACTION_ID, groupId1, round);

        assertEq(addrs[0], address(0x100));
        assertEq(points[0], 1e18);
    }

    // ============ hasActiveGroups Tests ============

    function test_HasActiveGroups_True() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        assertTrue(groupService.hasActiveGroups(groupOwner1));
    }

    function test_HasActiveGroups_False_NoStake() public view {
        // user3 has no stake in any group
        assertFalse(groupService.hasActiveGroups(user3));
    }

    function test_HasActiveGroups_False_AfterDeactivate() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);
        assertTrue(groupService.hasActiveGroups(groupOwner1));

        advanceRound();
        _setupActionIdsForCurrentRound();

        vm.prank(groupOwner1, groupOwner1);
        newGroupManager.deactivateGroup(address(groupAction), groupId1);

        assertFalse(groupService.hasActiveGroups(groupOwner1));
    }

    function test_HasActiveGroups_MultipleGroups() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);
        setupGroupActionWithScores(groupId2, groupOwner2, user2, 20e18, 90);

        assertTrue(groupService.hasActiveGroups(groupOwner1));
        assertTrue(groupService.hasActiveGroups(groupOwner2));
    }

    // ============ generatedActionRewardByVerifier Tests ============

    function test_GeneratedRewardByVerifier_NoReward() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        uint256 round = verify.currentRound();
        uint256 accountReward = groupService.generatedActionRewardByVerifier(
            round,
            groupOwner1
        );

        // No reward minted yet
        assertEq(accountReward, 0);
    }

    function test_GeneratedRewardByVerifier_NonJoinedVerifier() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        uint256 round = verify.currentRound();
        uint256 accountReward = groupService.generatedActionRewardByVerifier(
            round,
            user3
        );

        // user3 not joined
        assertEq(accountReward, 0);
    }

    function test_GeneratedRewardByVerifier_MultipleGroups() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);
        setupGroupActionWithScores(groupId2, groupOwner2, user2, 20e18, 90);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        vm.prank(groupOwner2);
        groupService.join(new string[](0));

        uint256 round = verify.currentRound();

        // Both should return 0 since no reward is distributed yet
        uint256 accountReward1 = groupService.generatedActionRewardByVerifier(
            round,
            groupOwner1
        );
        uint256 accountReward2 = groupService.generatedActionRewardByVerifier(
            round,
            groupOwner2
        );

        assertEq(accountReward1, 0);
        assertEq(accountReward2, 0);
    }

    // ============ generatedActionReward Tests ============

    function test_GeneratedReward_NoReward() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        uint256 round = verify.currentRound();
        uint256 totalReward = groupService.generatedActionReward(round);

        // No reward minted yet
        assertEq(totalReward, 0);
    }

    function test_GeneratedReward_SingleGroupAction() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        uint256 round = verify.currentRound();

        // Verify generatedActionReward returns total reward
        uint256 totalReward = groupService.generatedActionReward(round);
        uint256 accountReward = groupService.generatedActionRewardByVerifier(
            round,
            groupOwner1
        );

        // accountReward should be <= totalReward
        assertTrue(accountReward <= totalReward);
    }

    function test_GeneratedReward_MultipleGroupActions() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);
        setupGroupActionWithScores(groupId2, groupOwner2, user2, 20e18, 90);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        vm.prank(groupOwner2);
        groupService.join(new string[](0));

        uint256 round = verify.currentRound();

        // generatedActionReward should return the same value regardless of verifier
        uint256 totalReward = groupService.generatedActionReward(round);
        uint256 accountReward1 = groupService.generatedActionRewardByVerifier(
            round,
            groupOwner1
        );
        uint256 accountReward2 = groupService.generatedActionRewardByVerifier(
            round,
            groupOwner2
        );

        // totalReward should be >= any accountReward
        assertTrue(totalReward >= accountReward1);
        assertTrue(totalReward >= accountReward2);
    }

    function test_GeneratedReward_ConsistencyWithMultipleVerifiers() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);
        setupGroupActionWithScores(groupId2, groupOwner2, user2, 20e18, 90);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        vm.prank(groupOwner2);
        groupService.join(new string[](0));

        uint256 round = verify.currentRound();

        // generatedActionReward should be consistent regardless of which verifier we query
        uint256 totalReward = groupService.generatedActionReward(round);
        uint256 accountRewardByOwner1 = groupService
            .generatedActionRewardByVerifier(round, groupOwner1);
        uint256 accountRewardByOwner2 = groupService
            .generatedActionRewardByVerifier(round, groupOwner2);
        uint256 accountRewardByUser3 = groupService
            .generatedActionRewardByVerifier(round, user3);

        // totalReward should be >= any accountReward
        assertTrue(totalReward >= accountRewardByOwner1);
        assertTrue(totalReward >= accountRewardByOwner2);
        assertTrue(totalReward >= accountRewardByUser3);
    }

    // ============ Different Groups Same Owner Tests ============

    function test_DifferentGroupsDifferentRecipients() public {
        // Mint additional group for groupOwner1
        token.mint(groupOwner1, 10000e18);
        vm.prank(groupOwner1);
        token.approve(address(group), type(uint256).max);
        uint256 groupId3 = group.mint(groupOwner1, "TestGroup3");

        // Activate groupId3
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(newGroupManager)
        );
        vm.prank(groupOwner1, groupOwner1);
        newGroupManager.activateGroup(
            address(groupAction),
            groupId3,
            "Group3",
            0,
            1e18,
            0,
            0
        );

        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // Set different recipients for different groups
        address[] memory recipients1 = new address[](1);
        recipients1[0] = address(0x100);
        uint256[] memory ratios1 = new uint256[](1);
        ratios1[0] = 3e17;

        address[] memory recipients3 = new address[](1);
        recipients3[0] = address(0x300);
        uint256[] memory ratios3 = new uint256[](1);
        ratios3[0] = 5e17;

        vm.prank(groupOwner1);
        groupService.setRecipients(ACTION_ID, groupId1, recipients1, ratios1);

        vm.prank(groupOwner1);
        groupService.setRecipients(ACTION_ID, groupId3, recipients3, ratios3);

        uint256 round = verify.currentRound();

        // Verify different recipients for different groups
        (address[] memory addrs1, uint256[] memory points1) = groupService
            .recipients(groupOwner1, ACTION_ID, groupId1, round);
        (address[] memory addrs3, uint256[] memory points3) = groupService
            .recipients(groupOwner1, ACTION_ID, groupId3, round);

        assertEq(addrs1[0], address(0x100));
        assertEq(points1[0], 3e17);
        assertEq(addrs3[0], address(0x300));
        assertEq(points3[0], 5e17);
    }

    // ============ _calculateReward Join Validation Tests ============

    function test_RewardByAccount_ReturnsZero_WhenNotJoinedInRound() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        uint256 round = verify.currentRound();

        // user3 has not joined the service in this round
        (uint256 reward, , bool claimed) = groupService.rewardByAccount(
            round,
            user3
        );
        assertEq(reward, 0, "Reward should be 0 for non-joined account");
        assertFalse(claimed, "Should not be claimed");
    }

    function test_RewardByAccount_ReturnsZero_WhenExitedInRound() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        // Join in round 0
        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // Advance to next round
        advanceRound();
        _setupActionIdsForCurrentRound();
        uint256 round1 = verify.currentRound();

        // Exit in round1
        vm.prank(groupOwner1);
        groupService.exit();

        // groupOwner1 joined in round0, but exited in round1
        // Check reward for round1 (should return 0 because exited in round1)
        (uint256 reward, , bool claimed) = groupService.rewardByAccount(
            round1,
            groupOwner1
        );
        assertEq(reward, 0, "Reward should be 0 when exited in target round");
        assertFalse(claimed, "Should not be claimed");
    }

    function test_RewardByAccount_Works_WhenJoinedInPreviousRound() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        // Join in round 0
        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // Advance to next round (account remains joined, doesn't need to rejoin)
        advanceRound();
        _setupActionIdsForCurrentRound();
        uint256 round1 = verify.currentRound();

        // Setup verify data for round1 (needed for reward calculation)
        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;
        vm.prank(groupOwner1);
        newGroupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            0,
            scores
        );

        // Set rewards for round1
        uint256 serviceReward = 1000e18;
        uint256 actionReward = 1000e18;
        mint.setActionReward(
            address(token),
            round1,
            SERVICE_ACTION_ID,
            serviceReward
        );
        mint.setActionReward(address(token), round1, ACTION_ID, actionReward);

        // Verify account is still joined in round1
        assertTrue(
            center.isAccountJoinedByRound(
                address(token),
                SERVICE_ACTION_ID,
                groupOwner1,
                round1
            ),
            "Account should be joined in round1 (joined in round0)"
        );

        // groupOwner1 joined in round0, and remains joined in round1
        // Check reward for round1
        (uint256 reward, , bool claimed) = groupService.rewardByAccount(
            round1,
            groupOwner1
        );

        // Calculate expected reward
        // Formula: reward = (totalServiceReward * generatedByVerifier) / totalActionReward
        // Since groupOwner1 is the only verifier and has all the action reward:
        // - totalServiceReward = serviceReward
        // - totalActionReward = actionReward
        // - generatedByVerifier = actionReward (all reward goes to groupOwner1)
        // - reward = (serviceReward * actionReward) / actionReward = serviceReward
        uint256 expectedReward = serviceReward;
        assertEq(reward, expectedReward, "Reward should match expected value");
        assertFalse(claimed, "Should not be claimed yet");

        // Compare with a non-joined account to verify the difference
        (uint256 nonJoinedReward, , ) = groupService.rewardByAccount(
            round1,
            user3
        );
        // Non-joined account should return 0 because isAccountJoinedByRound check fails
        assertEq(
            nonJoinedReward,
            0,
            "Non-joined account reward should be 0 (join check fails)"
        );
    }

    function test_RewardByAccount_Works_WhenJoinedInRound() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        uint256 round = verify.currentRound();

        // Join in the same round
        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // Should be able to query reward (even if 0, should not revert)
        (, , bool claimed) = groupService.rewardByAccount(round, groupOwner1);
        // Reward may be 0 if no reward is set, but should not revert
        assertFalse(claimed, "Should not be claimed yet");
        // The actual reward value depends on reward distribution, but the key is
        // that it doesn't revert when account is joined in the round
    }

    function test_RewardByAccount_MultipleRounds_JoinValidation() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        // Round 0: groupOwner1 joins
        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // Advance to round 1
        advanceRound();
        _setupActionIdsForCurrentRound();
        uint256 round1 = verify.currentRound();

        // Round 1: groupOwner1 exits (so not joined in round1)
        vm.prank(groupOwner1);
        groupService.exit();

        // Advance to round 2
        advanceRound();
        _setupActionIdsForCurrentRound();

        // Round 2: groupOwner1 joins again
        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // Verify rewards for each round
        (uint256 reward1, , ) = groupService.rewardByAccount(
            round1,
            groupOwner1
        );

        // Round 0: joined, should be able to query (may be 0 if no reward)
        // Round 1: not joined (exited), should return 0
        assertEq(
            reward1,
            0,
            "Round1 reward should be 0 (not joined in round1)"
        );
        // Round 2: joined, should be able to query (may be 0 if no reward)
        // The key validation is that round1 returns 0 due to join check
    }

    // ============ burnRewardIfNeeded Tests ============

    function test_BurnInfo_NoReward() public view {
        uint256 round = verify.currentRound();
        (uint256 burnAmount, bool burned) = groupService.burnInfo(round);
        assertEq(burnAmount, 0);
        assertFalse(burned);
    }

    function test_BurnInfo_WithUnparticipatedReward() public {
        // Setup: two service providers join
        vm.prank(groupOwner1);
        groupService.join(new string[](0));
        vm.prank(groupOwner2);
        groupService.join(new string[](0));

        uint256 round = verify.currentRound();
        advanceRound();
        _setupActionIdsForCurrentRound();

        // Setup action reward for group action
        uint256 totalActionReward = 50e18;
        mint.setActionReward(
            address(token),
            round,
            ACTION_ID,
            totalActionReward
        );

        // Setup service reward
        uint256 totalServiceReward = 100e18;
        mint.setActionReward(
            address(token),
            round,
            SERVICE_ACTION_ID,
            totalServiceReward
        );

        // Only groupOwner1 participates in action (generates action reward)
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        // Calculate expected burn amount
        (uint256 participatedReward, , ) = groupService.rewardByAccount(
            round,
            groupOwner1
        );
        uint256 expectedBurnAmount = totalServiceReward - participatedReward;

        (uint256 burnAmount, bool burned) = groupService.burnInfo(round);
        assertEq(burnAmount, expectedBurnAmount, "Burn amount should match");
        assertFalse(burned, "Should not be burned yet");
    }

    function test_BurnUnparticipatedReward_Success() public {
        // Setup: two service providers join
        vm.prank(groupOwner1);
        groupService.join(new string[](0));
        vm.prank(groupOwner2);
        groupService.join(new string[](0));

        uint256 round = verify.currentRound();
        advanceRound();
        _setupActionIdsForCurrentRound();

        // Setup action reward for group action
        uint256 totalActionReward = 50e18;
        mint.setActionReward(
            address(token),
            round,
            ACTION_ID,
            totalActionReward
        );

        // Setup service reward
        uint256 totalServiceReward = 100e18;
        mint.setActionReward(
            address(token),
            round,
            SERVICE_ACTION_ID,
            totalServiceReward
        );

        // Only groupOwner1 participates in action
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        // Mint tokens to contract for burning
        token.mint(address(groupService), totalServiceReward);

        // Calculate expected values
        (uint256 participatedReward, , ) = groupService.rewardByAccount(
            round,
            groupOwner1
        );
        uint256 expectedBurnAmount = totalServiceReward - participatedReward;

        uint256 tokenBalanceBefore = token.balanceOf(address(groupService));

        // Burn unparticipated reward
        groupService.burnRewardIfNeeded(round);

        // Verify burn info
        (uint256 burnAmount, bool burned) = groupService.burnInfo(round);
        assertEq(burnAmount, expectedBurnAmount, "Burn amount should match");
        assertTrue(burned, "Should be burned");

        // Verify token was burned (balance decreased)
        uint256 tokenBalanceAfter = token.balanceOf(address(groupService));
        assertEq(
            tokenBalanceAfter,
            tokenBalanceBefore - expectedBurnAmount,
            "Token should be burned"
        );
    }

    function test_BurnUnparticipatedReward_AllParticipated() public {
        // Setup: one service provider joins and participates
        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        uint256 round = verify.currentRound();
        advanceRound();
        _setupActionIdsForCurrentRound();

        // Setup action reward for group action
        uint256 totalActionReward = 50e18;
        mint.setActionReward(
            address(token),
            round,
            ACTION_ID,
            totalActionReward
        );

        // Setup service reward
        uint256 totalServiceReward = 100e18;
        mint.setActionReward(
            address(token),
            round,
            SERVICE_ACTION_ID,
            totalServiceReward
        );

        // groupOwner1 participates in action
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        // Calculate expected participated reward
        (uint256 participatedReward, , ) = groupService.rewardByAccount(
            round,
            groupOwner1
        );

        // Calculate expected burn amount
        // If no action reward was generated (generatedReward == 0), participatedReward will be 0
        // In that case, all service reward should be burned
        // If action reward was generated, participatedReward should be > 0, and burnAmount should be < totalServiceReward
        uint256 expectedBurnAmount = totalServiceReward - participatedReward;

        // Mint tokens to contract
        token.mint(address(groupService), totalServiceReward);

        uint256 tokenBalanceBefore = token.balanceOf(address(groupService));

        // Try to burn
        groupService.burnRewardIfNeeded(round);

        // Verify burn info
        (uint256 burnAmount, bool burned) = groupService.burnInfo(round);
        assertEq(
            burnAmount,
            expectedBurnAmount,
            "Burn amount should match expected"
        );

        // Verify token was burned (if expectedBurnAmount > 0)
        if (expectedBurnAmount > 0) {
            assertTrue(burned, "Should be burned when burnAmount > 0");
            uint256 tokenBalanceAfter = token.balanceOf(address(groupService));
            assertEq(
                tokenBalanceAfter,
                tokenBalanceBefore - expectedBurnAmount,
                "Token should be burned"
            );
        } else {
            // If expectedBurnAmount is 0, no burn should occur
            assertFalse(burned, "Should not be burned when burnAmount is 0");
            uint256 tokenBalanceAfter = token.balanceOf(address(groupService));
            assertEq(
                tokenBalanceAfter,
                tokenBalanceBefore,
                "Token balance should not change when burnAmount is 0"
            );
        }
    }

    function test_BurnUnparticipatedReward_RevertRoundNotFinished() public {
        uint256 currentRound = verify.currentRound();
        vm.expectRevert(
            abi.encodeWithSelector(
                IExtensionErrors.RoundNotFinished.selector,
                currentRound
            )
        );
        groupService.burnRewardIfNeeded(currentRound);
    }

    function test_BurnUnparticipatedReward_AlreadyBurned() public {
        // Setup: two service providers join
        vm.prank(groupOwner1);
        groupService.join(new string[](0));
        vm.prank(groupOwner2);
        groupService.join(new string[](0));

        uint256 round = verify.currentRound();
        advanceRound();
        _setupActionIdsForCurrentRound();

        // Setup action reward
        uint256 totalServiceReward = 100e18;
        mint.setActionReward(
            address(token),
            round,
            SERVICE_ACTION_ID,
            totalServiceReward
        );

        // Only groupOwner1 participates
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        // Mint tokens to contract for burning
        token.mint(address(groupService), totalServiceReward);

        // Burn first time
        groupService.burnRewardIfNeeded(round);

        // Try to burn again (should return early)
        uint256 tokenBalanceBefore = token.balanceOf(address(groupService));
        groupService.burnRewardIfNeeded(round);
        uint256 tokenBalanceAfter = token.balanceOf(address(groupService));

        // Verify no additional burn
        assertEq(
            tokenBalanceAfter,
            tokenBalanceBefore,
            "No additional burn on second call"
        );
    }

    function test_BurnUnparticipatedReward_MultipleParticipants() public {
        // Setup: three service providers join
        // First setup groups for all three
        uint256 groupId3 = setupGroupOwner(user3, 10000e18, "TestGroup3");

        // Setup user3 with stake
        setupUser(
            user3,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(newGroupManager)
        );

        // Activate group for user3
        vm.prank(user3, user3);
        newGroupManager.activateGroup(
            address(groupAction),
            groupId3,
            "Group3",
            0,
            1e18,
            0,
            0
        );

        vm.prank(groupOwner1);
        groupService.join(new string[](0));
        vm.prank(groupOwner2);
        groupService.join(new string[](0));
        vm.prank(user3);
        groupService.join(new string[](0));

        uint256 round = verify.currentRound();
        advanceRound();
        _setupActionIdsForCurrentRound();

        // Setup action reward for group action
        uint256 totalActionReward = 150e18;
        mint.setActionReward(
            address(token),
            round,
            ACTION_ID,
            totalActionReward
        );

        // Setup service reward
        uint256 totalServiceReward = 300e18;
        mint.setActionReward(
            address(token),
            round,
            SERVICE_ACTION_ID,
            totalServiceReward
        );

        // Setup groups for groupOwner1 and groupOwner2
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);
        setupGroupActionWithScores(groupId2, groupOwner2, user2, 20e18, 90);

        // Mint tokens to contract for burning
        token.mint(address(groupService), totalServiceReward);

        // Calculate expected burn amount
        (uint256 participatedReward1, , ) = groupService.rewardByAccount(
            round,
            groupOwner1
        );
        (uint256 participatedReward2, , ) = groupService.rewardByAccount(
            round,
            groupOwner2
        );
        uint256 totalParticipatedReward = participatedReward1 +
            participatedReward2;
        uint256 expectedBurnAmount = totalServiceReward -
            totalParticipatedReward;

        // Burn unparticipated reward
        groupService.burnRewardIfNeeded(round);

        // Verify burn info
        (uint256 burnAmount, bool burned) = groupService.burnInfo(round);
        assertEq(burnAmount, expectedBurnAmount, "Burn amount should match");
        assertTrue(burned, "Should be burned");
    }
}

/**
 * @title ExtensionGroupServiceStakeTokenTest
 * @notice Test suite for token conversion in ExtensionGroupService (stakeToken is now TOKEN_ADDRESS)
 */
contract ExtensionGroupServiceStakeTokenTest is BaseGroupTest {
    ExtensionGroupActionFactory public actionFactory;
    MockExtensionFactory public serviceFactory;
    GroupManager public newGroupManager;
    GroupJoin public newGroupJoin;
    GroupVerify public newGroupVerify;

    MockERC20 public otherToken;

    uint256 public groupId1;

    uint256 constant MAX_RECIPIENTS = 10;

    function setUp() public {
        setUpBase();

        // Deploy additional token for testing
        otherToken = new MockERC20();

        // Create new singleton instances for this test (not using BaseGroupTest's instances)
        // because ExtensionGroupActionFactory constructor will initialize them
        newGroupManager = new GroupManager();
        newGroupJoin = new GroupJoin();
        newGroupVerify = new GroupVerify();

        // Deploy actionFactory with new singleton instances
        actionFactory = new ExtensionGroupActionFactory(
            address(center),
            address(newGroupManager),
            address(newGroupJoin),
            address(newGroupVerify),
            address(group)
        );
        // Initialize singletons after factory is fully constructed
        IGroupManager(address(newGroupManager)).initialize(
            address(actionFactory)
        );
        IGroupJoin(address(newGroupJoin)).initialize(address(actionFactory));
        IGroupVerify(address(newGroupVerify)).initialize(
            address(actionFactory)
        );
        serviceFactory = new MockExtensionFactory(address(center));

        // Setup group owner
        groupId1 = setupGroupOwner(groupOwner1, 10000e18, "TestGroup1");

        // Prepare token approvals
        token.mint(address(this), 100e18);
        token.approve(address(actionFactory), type(uint256).max);
        token.approve(address(serviceFactory), type(uint256).max);
    }

    // ============ Helper Functions ============

    function _setupGroupActionAndService(
        uint256 stakeAmount,
        uint256 actionId,
        uint256 serviceActionId,
        uint256 testRound
    )
        internal
        returns (
            ExtensionGroupAction groupAction,
            ExtensionGroupService groupService
        )
    {
        // Set unique round for this test to avoid action conflicts
        verify.setCurrentRound(testRound);
        join.setCurrentRound(testRound);

        // Create GroupAction using factory
        if (token.balanceOf(address(this)) < 2e18) {
            token.mint(address(this), 2e18);
        }
        token.approve(address(actionFactory), type(uint256).max);
        address groupActionAddress = actionFactory.createExtension(
            address(token), // tokenAddress
            address(token), // joinTokenAddress
            stakeAmount,
            MAX_JOIN_AMOUNT_RATIO,
            ACTIVATION_MIN_GOV_RATIO
        );
        groupAction = ExtensionGroupAction(groupActionAddress);

        // Deploy GroupService
        token.approve(address(serviceFactory), type(uint256).max);
        groupService = new ExtensionGroupService(
            address(serviceFactory),
            address(token),
            address(token),
            address(actionFactory),
            0 // govRatioMultiplier = 0 means no cap
        );
        serviceFactory.registerExtension(address(groupService), address(token));

        // Prepare extension init
        submit.setActionInfo(address(token), actionId, address(groupAction));
        submit.setActionInfo(
            address(token),
            serviceActionId,
            address(groupService)
        );

        // Set action authors to match extension creators
        address actionAuthor = actionFactory.extensionCreator(
            address(groupAction)
        );
        submit.setActionAuthor(address(token), actionId, actionAuthor);
        address serviceAuthor = serviceFactory.extensionCreator(
            address(groupService)
        );
        submit.setActionAuthor(address(token), serviceActionId, serviceAuthor);

        // Set voted actionIds for this round
        vote.setVotedActionIds(address(token), testRound, actionId);
        vote.setVotedActionIds(address(token), testRound, serviceActionId);
        // Set votes for this round
        vote.setVotesNum(address(token), testRound, 10000e18);
        vote.setVotesNumByActionId(
            address(token),
            testRound,
            actionId,
            10000e18
        );
        vote.setVotesNumByActionId(
            address(token),
            testRound,
            serviceActionId,
            10000e18
        );

        token.mint(address(groupAction), 1e18);
        token.mint(address(groupService), 1e18);
    }

    // ============ Token Conversion Tests ============

    /// @notice Test joinedAmount when stakeToken equals tokenAddress (no conversion needed, stakeToken is now always TOKEN_ADDRESS)
    function test_JoinedAmount_StakeTokenEqualsTokenAddress() public {
        uint256 stakeAmount = 1000e18;

        (
            ExtensionGroupAction groupAction,
            ExtensionGroupService groupService
        ) = _setupGroupActionAndService(stakeAmount, 100, 101, 10);

        // Setup user and activate group
        setupUser(groupOwner1, stakeAmount, address(newGroupManager));

        vm.prank(groupOwner1, groupOwner1);
        newGroupManager.activateGroup(
            address(groupAction),
            groupId1,
            "Group1",
            0,
            1e18,
            0,
            0
        );

        // User joins group
        setupUser(user1, 100e18, address(newGroupJoin));
        vm.prank(user1);
        newGroupJoin.join(
            address(groupAction),
            groupId1,
            50e18,
            new string[](0)
        );

        // Owner joins service
        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // Verify joinedAmount equals total staked (no conversion)
        // Only groupId1 is activated in this test, which stakes GROUP_ACTIVATION_STAKE_AMOUNT
        uint256 expectedStaked = GROUP_ACTIVATION_STAKE_AMOUNT;
        uint256 joinedVal = groupService.joinedAmount();
        assertEq(
            joinedVal,
            expectedStaked,
            "JoinedAmount should equal totalStaked"
        );
    }

    /// @notice Test joinedAmount with token as stakeToken (stakeToken must be TOKEN_ADDRESS now)
    function test_JoinedAmount_WithToken() public {
        uint256 stakeAmount = 100e18;

        (
            ExtensionGroupAction groupAction,
            ExtensionGroupService groupService
        ) = _setupGroupActionAndService(stakeAmount, 200, 201, 20);

        // Setup: mint and approve token for newGroupManager
        token.mint(groupOwner1, 200e18);
        vm.prank(groupOwner1);
        token.approve(address(newGroupManager), type(uint256).max);

        // Activate group with token stake
        vm.prank(groupOwner1, groupOwner1);
        newGroupManager.activateGroup(
            address(groupAction),
            groupId1,
            "TokenGroup",
            0,
            1e18,
            0,
            0
        );

        // Owner joins service
        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // Since stakeToken is TOKEN_ADDRESS and targetTokenAddress is also TOKEN_ADDRESS,
        // no conversion is needed
        // Only groupId1 is activated, which stakes stakeAmount (set in _setupGroupActionAndService)
        uint256 expectedStaked = stakeAmount; // 100e18
        uint256 joinedVal = groupService.joinedAmount();
        assertEq(
            joinedVal,
            expectedStaked,
            "JoinedAmount should equal staked amount (no conversion needed)"
        );
    }
}
