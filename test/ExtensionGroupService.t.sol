// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "./utils/BaseGroupTest.sol";
import {ExtensionGroupService} from "../src/ExtensionGroupService.sol";
import {ExtensionGroupAction} from "../src/ExtensionGroupAction.sol";
import {IGroupService} from "../src/interface/IGroupService.sol";
import {GroupManager} from "../src/GroupManager.sol";
import {GroupJoin} from "../src/GroupJoin.sol";
import {GroupVerify} from "../src/GroupVerify.sol";
import {IGroupManager} from "../src/interface/IGroupManager.sol";
import {IGroupJoin} from "../src/interface/IGroupJoin.sol";
import {IGroupVerify} from "../src/interface/IGroupVerify.sol";
import {IJoin} from "@extension/src/interface/IJoin.sol";
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
contract ExtensionGroupServiceTest is BaseGroupTest {
    // Re-declare event for testing (updated with groupId)
    event RecipientsUpdate(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        uint256 indexed groupId,
        address account,
        address[] recipients,
        uint256[] basisPoints
    );
    ExtensionGroupService public groupService;
    ExtensionGroupAction public groupAction;
    ExtensionGroupActionFactory public actionFactory;
    MockExtensionFactory public serviceFactory;
    GroupManager public newGroupManager;
    GroupJoin public newGroupJoin;
    GroupVerify public newGroupVerify;

    uint256 public groupId1;
    uint256 public groupId2;

    uint256 constant MAX_RECIPIENTS = 100;
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
            address(token), // stakeTokenAddress
            address(token), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );
        groupAction = ExtensionGroupAction(groupActionAddress);

        // Deploy GroupService (use actionFactory as GROUP_ACTION_FACTORY_ADDRESS)
        token.approve(address(serviceFactory), type(uint256).max);
        groupService = new ExtensionGroupService(
            address(serviceFactory),
            address(token),
            address(token), // groupActionTokenAddress
            address(actionFactory)
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
        vm.expectRevert(IGroupService.NoActiveGroups.selector);
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

        uint256[] memory basisPoints = new uint256[](2);
        basisPoints[0] = 3e17; // 30%
        basisPoints[1] = 2e17; // 20%

        vm.prank(groupOwner1);
        groupService.setRecipients(
            ACTION_ID,
            groupId1,
            recipients,
            basisPoints
        );

        uint256 round = verify.currentRound();
        (address[] memory addrs, uint256[] memory points) = groupService
            .recipients(groupOwner1, ACTION_ID, groupId1, round);

        assertEq(addrs.length, 2);
        assertEq(addrs[0], recipients[0]);
        assertEq(addrs[1], recipients[1]);
        assertEq(points[0], 3e17);
        assertEq(points[1], 2e17);
    }

    function test_SetRecipients_RevertNotJoined() public {
        address[] memory recipients = new address[](1);
        recipients[0] = address(0x100);

        uint256[] memory basisPoints = new uint256[](1);
        basisPoints[0] = 5e17;

        vm.prank(groupOwner1);
        vm.expectRevert(IJoin.NotJoined.selector);
        groupService.setRecipients(
            ACTION_ID,
            groupId1,
            recipients,
            basisPoints
        );
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

        uint256[] memory basisPoints = new uint256[](1);
        basisPoints[0] = 5e17;

        // groupOwner2 tries to set recipients for groupId1 (owned by groupOwner1)
        vm.prank(groupOwner2);
        vm.expectRevert(IGroupService.NotGroupOwner.selector);
        groupService.setRecipients(
            ACTION_ID,
            groupId1,
            recipients,
            basisPoints
        );
    }

    function test_SetRecipients_RevertArrayLengthMismatch() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        address[] memory recipients = new address[](2);
        recipients[0] = address(0x100);
        recipients[1] = address(0x200);

        uint256[] memory basisPoints = new uint256[](1);
        basisPoints[0] = 5e17;

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupService.ArrayLengthMismatch.selector);
        groupService.setRecipients(
            ACTION_ID,
            groupId1,
            recipients,
            basisPoints
        );
    }

    function test_SetRecipients_RevertTooManyRecipients() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        address[] memory recipients = new address[](MAX_RECIPIENTS + 1);
        uint256[] memory basisPoints = new uint256[](MAX_RECIPIENTS + 1);

        for (uint256 i = 0; i < MAX_RECIPIENTS + 1; i++) {
            recipients[i] = address(uint160(0x100 + i));
            basisPoints[i] = 1e16;
        }

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupService.TooManyRecipients.selector);
        groupService.setRecipients(
            ACTION_ID,
            groupId1,
            recipients,
            basisPoints
        );
    }

    function test_SetRecipients_RevertZeroAddress() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        address[] memory recipients = new address[](1);
        recipients[0] = address(0);

        uint256[] memory basisPoints = new uint256[](1);
        basisPoints[0] = 5e17;

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupService.ZeroAddress.selector);
        groupService.setRecipients(
            ACTION_ID,
            groupId1,
            recipients,
            basisPoints
        );
    }

    function test_SetRecipients_RevertZeroBasisPoints() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        address[] memory recipients = new address[](1);
        recipients[0] = address(0x100);

        uint256[] memory basisPoints = new uint256[](1);
        basisPoints[0] = 0;

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupService.ZeroBasisPoints.selector);
        groupService.setRecipients(
            ACTION_ID,
            groupId1,
            recipients,
            basisPoints
        );
    }

    function test_SetRecipients_RevertInvalidBasisPoints() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        address[] memory recipients = new address[](2);
        recipients[0] = address(0x100);
        recipients[1] = address(0x200);

        uint256[] memory basisPoints = new uint256[](2);
        basisPoints[0] = 6e17; // 60%
        basisPoints[1] = 5e17; // 50% - total > 100%

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupService.InvalidBasisPoints.selector);
        groupService.setRecipients(
            ACTION_ID,
            groupId1,
            recipients,
            basisPoints
        );
    }

    function test_SetRecipients_RevertRecipientCannotBeSelf() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // Try to set self as recipient
        address[] memory recipients = new address[](1);
        recipients[0] = groupOwner1; // Self

        uint256[] memory basisPoints = new uint256[](1);
        basisPoints[0] = 5e17;

        vm.prank(groupOwner1);
        vm.expectRevert(IGroupService.RecipientCannotBeSelf.selector);
        groupService.setRecipients(
            ACTION_ID,
            groupId1,
            recipients,
            basisPoints
        );
    }

    // ============ recipients Tests ============

    function test_Recipients_HistoryByRound() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // Set recipients in round 1
        address[] memory recipients1 = new address[](1);
        recipients1[0] = address(0x100);
        uint256[] memory basisPoints1 = new uint256[](1);
        basisPoints1[0] = 3e17;

        vm.prank(groupOwner1);
        groupService.setRecipients(
            ACTION_ID,
            groupId1,
            recipients1,
            basisPoints1
        );

        uint256 round1 = verify.currentRound();

        // Advance round and setup actionIds for new round
        advanceRound();
        _setupActionIdsForCurrentRound();
        uint256 round2 = verify.currentRound();

        // Set different recipients in round 2
        address[] memory recipients2 = new address[](1);
        recipients2[0] = address(0x200);
        uint256[] memory basisPoints2 = new uint256[](1);
        basisPoints2[0] = 4e17;

        vm.prank(groupOwner1);
        groupService.setRecipients(
            ACTION_ID,
            groupId1,
            recipients2,
            basisPoints2
        );

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

    function test_RecipientsLatest() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        address[] memory recipients = new address[](1);
        recipients[0] = address(0x100);
        uint256[] memory basisPoints = new uint256[](1);
        basisPoints[0] = 3e17;

        vm.prank(groupOwner1);
        groupService.setRecipients(
            ACTION_ID,
            groupId1,
            recipients,
            basisPoints
        );

        (address[] memory addrs, uint256[] memory points) = groupService
            .recipientsLatest(groupOwner1, ACTION_ID, groupId1);
        assertEq(addrs.length, 1);
        assertEq(addrs[0], address(0x100));
        assertEq(points[0], 3e17);
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
        uint256[] memory basisPoints = new uint256[](1);
        basisPoints[0] = 3e17; // 30%

        vm.prank(groupOwner1);
        groupService.setRecipients(
            ACTION_ID,
            groupId1,
            recipients,
            basisPoints
        );

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
        uint256[] memory basisPoints = new uint256[](1);
        basisPoints[0] = 3e17; // 30%

        vm.prank(groupOwner1);
        groupService.setRecipients(
            ACTION_ID,
            groupId1,
            recipients,
            basisPoints
        );

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
        uint256[] memory basisPoints = new uint256[](2);
        basisPoints[0] = 3e17; // 30%
        basisPoints[1] = 2e17; // 20%

        vm.prank(groupOwner1);
        groupService.setRecipients(
            ACTION_ID,
            groupId1,
            recipients,
            basisPoints
        );

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

    // ============ rewardDistributionAll Tests ============

    function test_RewardDistributionAll() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // Set recipients for groupId1
        address[] memory recipients = new address[](1);
        recipients[0] = address(0x100);
        uint256[] memory basisPoints = new uint256[](1);
        basisPoints[0] = 3e17;

        vm.prank(groupOwner1);
        groupService.setRecipients(
            ACTION_ID,
            groupId1,
            recipients,
            basisPoints
        );

        uint256 round = verify.currentRound();

        IGroupService.GroupDistribution[] memory distributions = groupService
            .rewardDistributionAll(round, groupOwner1);

        // Should have 1 distribution (for groupId1)
        assertEq(distributions.length, 1);
        assertEq(distributions[0].actionId, ACTION_ID);
        assertEq(distributions[0].groupId, groupId1);
        assertEq(distributions[0].recipients.length, 1);
        assertEq(distributions[0].recipients[0], address(0x100));
        assertEq(distributions[0].basisPoints[0], 3e17);
    }

    // ============ IExtensionJoinedValue Tests ============

    function test_isJoinedValueConverted() public view {
        assertTrue(groupService.isJoinedValueConverted());
    }

    function test_JoinedValue() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);
        setupGroupActionWithScores(groupId2, groupOwner2, user2, 20e18, 80);

        // joinedValue should return totalStaked from groupManager
        uint256 joinedVal = groupService.joinedValue();
        assertEq(joinedVal, newGroupManager.totalStaked(address(groupAction)));
    }

    function test_JoinedValueByAccount() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        uint256 ownerValue = groupService.joinedValueByAccount(groupOwner1);
        assertEq(
            ownerValue,
            newGroupManager.totalStakedByOwner(
                address(groupAction),
                groupOwner1
            )
        );

        // Non-joined account
        uint256 user2Value = groupService.joinedValueByAccount(user2);
        assertEq(user2Value, 0);
    }

    function test_JoinedValue_IncludesAllActions_NotJustVoted() public {
        // Setup first action (ACTION_ID = 0) with voting
        // Note: groupId1 and groupId2 are already activated in ACTION_ID during setUp
        // So we have activation stake for ACTION_ID

        // Setup second action (ACTION_ID = 1) without voting
        uint256 actionId2 = 1;
        address groupAction2Address = actionFactory.createExtension(
            address(token),
            address(token),
            address(token),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );
        submit.setActionInfo(address(token), actionId2, groupAction2Address);
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

        // Verify joinedValue includes both actions (not just voted one)
        // Note: action1 has 2 activated groups (groupId1, groupId2), action2 has 1 (groupId3)
        uint256 joinedVal = groupService.joinedValue();
        uint256 expectedTotal = newGroupManager.totalStaked(
            address(groupAction)
        ) + newGroupManager.totalStaked(groupAction2Address);
        assertEq(
            joinedVal,
            expectedTotal,
            "joinedValue should include all actions, not just voted ones"
        );
        assertTrue(joinedVal > 0, "joinedVal should be greater than 0");
        // Verify action2's stake is included (1 activation stake)
        assertEq(
            newGroupManager.totalStaked(groupAction2Address),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            "action2 should have 1 activation stake"
        );
    }

    function test_JoinedValueByAccount_IncludesAllActions_NotJustVoted()
        public
    {
        // Setup first action (ACTION_ID = 0) with voting
        // Note: groupOwner1's groupId1 is already activated in ACTION_ID during setUp

        // Setup second action (ACTION_ID = 1) without voting
        uint256 actionId2 = 1;
        address groupAction2Address = actionFactory.createExtension(
            address(token),
            address(token),
            address(token),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );
        submit.setActionInfo(address(token), actionId2, groupAction2Address);
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

        // Verify joinedValueByAccount includes both actions
        uint256 ownerValue = groupService.joinedValueByAccount(groupOwner1);
        uint256 expectedTotal = newGroupManager.totalStakedByOwner(
            address(groupAction),
            groupOwner1
        ) +
            newGroupManager.totalStakedByOwner(
                groupAction2Address,
                groupOwner1
            );
        assertEq(
            ownerValue,
            expectedTotal,
            "joinedValueByAccount should include all actions, not just voted ones"
        );
        // Verify groupOwner1 has stake in action2
        assertEq(
            newGroupManager.totalStakedByOwner(
                groupAction2Address,
                groupOwner1
            ),
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
        uint256[] memory basisPoints = new uint256[](1);
        basisPoints[0] = 3e17;

        uint256 round = verify.currentRound();

        vm.expectEmit(true, true, true, true);
        emit RecipientsUpdate(
            address(token),
            round,
            ACTION_ID,
            groupId1,
            groupOwner1,
            recipients,
            basisPoints
        );

        vm.prank(groupOwner1);
        groupService.setRecipients(
            ACTION_ID,
            groupId1,
            recipients,
            basisPoints
        );
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
        uint256[] memory basisPoints1 = new uint256[](1);
        basisPoints1[0] = 3e17;

        vm.prank(groupOwner1);
        groupService.setRecipients(
            ACTION_ID,
            groupId1,
            recipients1,
            basisPoints1
        );

        address[] memory recipients2 = new address[](1);
        recipients2[0] = address(0x200);
        uint256[] memory basisPoints2 = new uint256[](1);
        basisPoints2[0] = 4e17;

        vm.prank(groupOwner2);
        groupService.setRecipients(
            ACTION_ID,
            groupId2,
            recipients2,
            basisPoints2
        );

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
        uint256[] memory basisPoints = new uint256[](0);

        vm.prank(groupOwner1);
        groupService.setRecipients(
            ACTION_ID,
            groupId1,
            recipients,
            basisPoints
        );

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
        uint256[] memory basisPoints1 = new uint256[](1);
        basisPoints1[0] = 3e17;

        vm.prank(groupOwner1);
        groupService.setRecipients(
            ACTION_ID,
            groupId1,
            recipients1,
            basisPoints1
        );

        // Update in same round
        address[] memory recipients2 = new address[](1);
        recipients2[0] = address(0x200);
        uint256[] memory basisPoints2 = new uint256[](1);
        basisPoints2[0] = 5e17;

        vm.prank(groupOwner1);
        groupService.setRecipients(
            ACTION_ID,
            groupId1,
            recipients2,
            basisPoints2
        );

        uint256 round = verify.currentRound();
        (address[] memory addrs, uint256[] memory points) = groupService
            .recipients(groupOwner1, ACTION_ID, groupId1, round);

        assertEq(addrs[0], address(0x200));
        assertEq(points[0], 5e17);
    }

    function test_MaxBasisPoints() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // 100% to recipients
        address[] memory recipients = new address[](1);
        recipients[0] = address(0x100);
        uint256[] memory basisPoints = new uint256[](1);
        basisPoints[0] = 1e18; // 100%

        vm.prank(groupOwner1);
        groupService.setRecipients(
            ACTION_ID,
            groupId1,
            recipients,
            basisPoints
        );

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

    // ============ votedGroupActions Tests ============
    // Note: votedGroupActions is now implemented in ExtensionGroupActionFactory
    // It gets extension from submit.actionInfo.whiteListAddress and checks
    // if the extension exists in Factory using _isExtension mapping

    function test_votedGroupActions_Empty() public view {
        // Use a round that has no voted actionIds
        uint256 emptyRound = 999;
        (uint256[] memory aids, address[] memory exts) = actionFactory
            .votedGroupActions(address(token), emptyRound);

        assertEq(exts.length, 0);
        assertEq(aids.length, 0);
    }

    function test_votedGroupActions_SingleValid() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        uint256 round = verify.currentRound();
        (uint256[] memory aids, address[] memory exts) = actionFactory
            .votedGroupActions(address(token), round);

        assertEq(exts.length, 1);
        assertEq(aids.length, 1);
        assertEq(exts[0], address(groupAction));
        assertEq(aids[0], ACTION_ID);
    }

    function test_votedGroupActions_MultipleValid() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);
        setupGroupActionWithScores(groupId2, groupOwner2, user2, 20e18, 90);

        // Create another group action with different actionId using factory
        token.mint(address(this), 1e18);
        token.approve(address(actionFactory), type(uint256).max);
        address groupAction2Address = actionFactory.createExtension(
            address(token), // tokenAddress
            address(token), // stakeTokenAddress
            address(token), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );
        ExtensionGroupAction groupAction2 = ExtensionGroupAction(
            groupAction2Address
        );

        uint256 actionId2 = 100;
        // Prepare extension init for groupAction2 (this sets votedActionIds)
        prepareExtensionInit(address(groupAction2), address(token), actionId2);

        // Create and activate a group for groupAction2
        uint256 groupId3 = setupGroupOwner(groupOwner1, 10000e18, "TestGroup3");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(newGroupManager)
        );
        vm.prank(groupOwner1, groupOwner1);
        newGroupManager.activateGroup(
            address(groupAction2),
            groupId3,
            "Group3",
            0, // maxCapacity
            1e18, // minJoinAmount
            0,
            0
        );

        uint256 round = verify.currentRound();
        (uint256[] memory aids, address[] memory exts) = actionFactory
            .votedGroupActions(address(token), round);

        assertEq(exts.length, 2);
        assertEq(aids.length, 2);
        // Both should be valid
        assertTrue(
            (exts[0] == address(groupAction) && aids[0] == ACTION_ID) ||
                (exts[0] == address(groupAction2) && aids[0] == actionId2)
        );
        assertTrue(
            (exts[1] == address(groupAction) && aids[1] == ACTION_ID) ||
                (exts[1] == address(groupAction2) && aids[1] == actionId2)
        );
        assertTrue(exts[0] != exts[1]);
    }

    function test_votedGroupActions_FiltersInvalidExtension() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        // Add an actionId with extension not registered in factory
        // The implementation now gets extension from submit.actionInfo.whiteListAddress
        // and checks if it exists in Factory using _isExtension mapping
        // Use address(token) as invalid extension - it's not registered in Factory
        uint256 invalidActionId = 200;
        address invalidExtension = address(token);
        submit.setActionInfo(address(token), invalidActionId, invalidExtension);
        vote.setVotedActionIds(
            address(token),
            verify.currentRound(),
            invalidActionId
        );

        uint256 round = verify.currentRound();
        (uint256[] memory aids, address[] memory exts) = actionFactory
            .votedGroupActions(address(token), round);

        // Should only return the valid one (registered in Factory)
        assertEq(exts.length, 1);
        assertEq(aids.length, 1);
        assertEq(exts[0], address(groupAction));
        assertEq(aids[0], ACTION_ID);
    }

    function test_votedGroupActions_FiltersZeroExtension() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        // Add an actionId with zero extension address (whiteListAddress = address(0))
        // The implementation checks if ext != address(0) before checking Factory
        uint256 zeroActionId = 300;
        submit.setActionInfo(address(token), zeroActionId, address(0));
        vote.setVotedActionIds(
            address(token),
            verify.currentRound(),
            zeroActionId
        );

        uint256 round = verify.currentRound();
        (uint256[] memory aids, address[] memory exts) = actionFactory
            .votedGroupActions(address(token), round);

        // Should only return the valid one (non-zero extension registered in Factory)
        assertEq(exts.length, 1);
        assertEq(aids.length, 1);
        assertEq(exts[0], address(groupAction));
        assertEq(aids[0], ACTION_ID);
    }

    function test_votedGroupActions_DifferentRounds() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        uint256 round1 = verify.currentRound();
        (uint256[] memory aids1, address[] memory exts1) = actionFactory
            .votedGroupActions(address(token), round1);

        assertEq(exts1.length, 1);
        assertEq(aids1.length, 1);

        // Advance to next round but don't setup actionIds for this round
        advanceRound();

        uint256 round2 = verify.currentRound();
        (uint256[] memory aids2, address[] memory exts2) = actionFactory
            .votedGroupActions(address(token), round2);

        // Round2 should have no valid actions (no voted actionIds in round2)
        assertEq(exts2.length, 0);
        assertEq(aids2.length, 0);

        // Round1 should still return the same result
        (
            uint256[] memory aids1Again,
            address[] memory exts1Again
        ) = actionFactory.votedGroupActions(address(token), round1);
        assertEq(exts1Again.length, 1);
        assertEq(aids1Again.length, 1);
    }

    function test_votedGroupActions_WorksBeforeCenterRegistration() public {
        // Test that votedGroupActions works even when action is not registered in Center
        // This is the key improvement: it gets extension from submit.actionInfo.whiteListAddress
        // instead of center.extension(), so it works before Center registration

        // Create a new extension through Factory
        token.mint(address(this), 1e18);
        token.approve(address(actionFactory), type(uint256).max);
        address newExtension = actionFactory.createExtension(
            address(token),
            address(token),
            address(token),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        // Set actionInfo with whiteListAddress pointing to the extension
        // But don't register it in Center (don't call center.registerActionIfNeeded)
        uint256 newActionId = 500;
        submit.setActionInfo(address(token), newActionId, newExtension);
        vote.setVotedActionIds(
            address(token),
            verify.currentRound(),
            newActionId
        );

        // Verify that votedGroupActions can find it even though it's not in Center
        uint256 round = verify.currentRound();
        (uint256[] memory aids, address[] memory exts) = actionFactory
            .votedGroupActions(address(token), round);

        // Should include the new extension because it's in Factory and whiteListAddress is set
        bool found = false;
        for (uint256 i; i < exts.length; ) {
            if (exts[i] == newExtension && aids[i] == newActionId) {
                found = true;
                break;
            }
            unchecked {
                ++i;
            }
        }
        assertTrue(
            found,
            "New extension should be found via submit.actionInfo"
        );
    }

    // ============ generatedRewardByVerifier Tests ============

    function test_GeneratedRewardByVerifier_NoReward() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        uint256 round = verify.currentRound();
        (uint256 accountReward, uint256 totalReward) = groupService
            .generatedRewardByVerifier(round, groupOwner1);

        // No reward minted yet
        assertEq(accountReward, 0);
        assertEq(totalReward, 0);
    }

    function test_GeneratedRewardByVerifier_NonJoinedVerifier() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        uint256 round = verify.currentRound();
        (uint256 accountReward, uint256 totalReward) = groupService
            .generatedRewardByVerifier(round, user3);

        // user3 not joined
        assertEq(accountReward, 0);
        assertEq(totalReward, 0);
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
        (uint256 accountReward1, uint256 totalReward1) = groupService
            .generatedRewardByVerifier(round, groupOwner1);
        (uint256 accountReward2, uint256 totalReward2) = groupService
            .generatedRewardByVerifier(round, groupOwner2);

        assertEq(accountReward1, 0);
        assertEq(totalReward1, 0);
        assertEq(accountReward2, 0);
        assertEq(totalReward2, 0);
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
        uint256[] memory basisPoints1 = new uint256[](1);
        basisPoints1[0] = 3e17;

        address[] memory recipients3 = new address[](1);
        recipients3[0] = address(0x300);
        uint256[] memory basisPoints3 = new uint256[](1);
        basisPoints3[0] = 5e17;

        vm.prank(groupOwner1);
        groupService.setRecipients(
            ACTION_ID,
            groupId1,
            recipients1,
            basisPoints1
        );

        vm.prank(groupOwner1);
        groupService.setRecipients(
            ACTION_ID,
            groupId3,
            recipients3,
            basisPoints3
        );

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
}

/**
 * @title ExtensionGroupServiceStakeTokenTest
 * @notice Test suite for stakeToken conversion in ExtensionGroupService
 */
contract ExtensionGroupServiceStakeTokenTest is BaseGroupTest {
    ExtensionGroupActionFactory public actionFactory;
    MockExtensionFactory public serviceFactory;
    GroupManager public newGroupManager;
    GroupJoin public newGroupJoin;
    GroupVerify public newGroupVerify;

    MockERC20 public otherToken;

    uint256 public groupId1;

    uint256 constant MAX_RECIPIENTS = 100;

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
        address stakeTokenAddress,
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

        // Create GroupAction using factory with specified stakeToken
        if (token.balanceOf(address(this)) < 2e18) {
            token.mint(address(this), 2e18);
        }
        token.approve(address(actionFactory), type(uint256).max);
        address groupActionAddress = actionFactory.createExtension(
            address(token), // tokenAddress
            stakeTokenAddress, // stakeTokenAddress
            address(token), // joinTokenAddress
            stakeAmount,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );
        groupAction = ExtensionGroupAction(groupActionAddress);

        // Deploy GroupService
        token.approve(address(serviceFactory), type(uint256).max);
        groupService = new ExtensionGroupService(
            address(serviceFactory),
            address(token),
            address(token),
            address(actionFactory)
        );
        serviceFactory.registerExtension(address(groupService), address(token));

        // Prepare extension init
        submit.setActionInfo(address(token), actionId, address(groupAction));
        submit.setActionInfo(
            address(token),
            serviceActionId,
            address(groupService)
        );

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

    // ============ StakeToken Conversion Tests ============

    /// @notice Test joinedValue when stakeToken equals tokenAddress (no conversion needed)
    function test_JoinedValue_StakeTokenEqualsTokenAddress() public {
        uint256 stakeAmount = 1000e18;

        (
            ExtensionGroupAction groupAction,
            ExtensionGroupService groupService
        ) = _setupGroupActionAndService(
                address(token),
                stakeAmount,
                100,
                101,
                10
            );

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

        // Verify joinedValue equals total staked (no conversion)
        uint256 totalStaked = newGroupManager.totalStaked(address(groupAction));
        uint256 joinedVal = groupService.joinedValue();
        assertEq(
            joinedVal,
            totalStaked,
            "JoinedValue should equal totalStaked"
        );
    }

    /// @notice Test joinedValue with LP token as stakeToken
    function test_JoinedValue_WithLPToken() public {
        // Create LP pair for token/otherToken
        address lpToken = uniswapFactory.createPair(
            address(token),
            address(otherToken)
        );

        // Set LP reserves: 1000 token (token0), 2000 otherToken (token1)
        MockUniswapV2Pair(lpToken).setReserves(1000e18, 2000e18);

        // Mint LP tokens to simulate totalSupply (100 LP total)
        MockUniswapV2Pair(lpToken).mint(address(this), 100e18);

        uint256 lpStakeAmount = 10e18;

        (
            ExtensionGroupAction groupAction,
            ExtensionGroupService groupService
        ) = _setupGroupActionAndService(lpToken, lpStakeAmount, 200, 201, 20);

        // Setup: mint and approve LP tokens for newGroupManager
        MockUniswapV2Pair(lpToken).mint(groupOwner1, 20e18);
        vm.prank(groupOwner1);
        MockUniswapV2Pair(lpToken).approve(
            address(newGroupManager),
            type(uint256).max
        );

        // Activate group with LP token stake
        vm.prank(groupOwner1, groupOwner1);
        newGroupManager.activateGroup(
            address(groupAction),
            groupId1,
            "LPGroup",
            0,
            1e18,
            0,
            0
        );

        // Owner joins service
        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // Calculate expected value:
        // LP staked = 10e18
        // LP totalSupply = 120e18 (100 minted to test contract + 20 to groupOwner1)
        // token reserve = 1000e18 (token is token0)
        // LP value = (tokenReserve * lpAmount * 2) / totalSupply
        //          = (1000e18 * 10e18 * 2) / 120e18 = 166.67e18
        uint256 lpStaked = newGroupManager.totalStaked(address(groupAction));
        assertEq(lpStaked, lpStakeAmount, "LP staked should be 10e18");

        uint256 joinedVal = groupService.joinedValue();
        uint256 lpTotalSupply = 120e18; // 100 + 20 minted
        uint256 expectedValue = (1000e18 * lpStakeAmount * 2) / lpTotalSupply;
        assertEq(
            joinedVal,
            expectedValue,
            "JoinedValue should be LP converted value"
        );
    }

    /// @notice Test joinedValue with token that has Uniswap pair to tokenAddress
    function test_JoinedValue_WithUniswapPair() public {
        // Create pair for token/otherToken
        address pairAddr = uniswapFactory.createPair(
            address(token),
            address(otherToken)
        );

        // Set reserves: 1000 token, 500 otherToken (1:0.5 ratio)
        // price: 1 otherToken = 2 token
        MockUniswapV2Pair(pairAddr).setReserves(1000e18, 500e18);

        uint256 stakeAmount = 100e18;

        (
            ExtensionGroupAction groupAction,
            ExtensionGroupService groupService
        ) = _setupGroupActionAndService(
                address(otherToken),
                stakeAmount,
                300,
                301,
                30
            );

        // Setup: mint and approve otherToken for newGroupManager
        otherToken.mint(groupOwner1, 200e18);
        vm.prank(groupOwner1);
        otherToken.approve(address(newGroupManager), type(uint256).max);

        // Activate group with otherToken stake
        vm.prank(groupOwner1, groupOwner1);
        newGroupManager.activateGroup(
            address(groupAction),
            groupId1,
            "OtherTokenGroup",
            0,
            1e18,
            0,
            0
        );

        // Owner joins service
        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // Calculate expected value:
        // otherToken staked = 100e18
        // reserves: 1000 token, 500 otherToken
        // converted value = (100e18 * 1000e18) / 500e18 = 200e18
        uint256 staked = newGroupManager.totalStaked(address(groupAction));
        assertEq(staked, stakeAmount, "OtherToken staked should be 100e18");

        uint256 joinedVal = groupService.joinedValue();
        uint256 expectedValue = (stakeAmount * 1000e18) / 500e18;
        assertEq(
            joinedVal,
            expectedValue,
            "JoinedValue should be converted via Uniswap"
        );
    }

    /// @notice Test joinedValue returns 0 when no Uniswap pair exists
    function test_JoinedValue_NoPairReturnsZero() public {
        uint256 stakeAmount = 100e18;

        // Deploy without creating Uniswap pair
        (
            ExtensionGroupAction groupAction,
            ExtensionGroupService groupService
        ) = _setupGroupActionAndService(
                address(otherToken),
                stakeAmount,
                400,
                401,
                40
            );

        // Setup: mint and approve otherToken for newGroupManager
        otherToken.mint(groupOwner1, 200e18);
        vm.prank(groupOwner1);
        otherToken.approve(address(newGroupManager), type(uint256).max);

        // Activate group with otherToken stake
        vm.prank(groupOwner1, groupOwner1);
        newGroupManager.activateGroup(
            address(groupAction),
            groupId1,
            "NoPairGroup",
            0,
            1e18,
            0,
            0
        );

        // Owner joins service
        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // joinedValue should return 0 (no pair exists)
        uint256 joinedVal = groupService.joinedValue();
        assertEq(joinedVal, 0, "JoinedValue should be 0 when no pair exists");
    }

    /// @notice Test LP token detection - non-LP token should use Uniswap conversion
    function test_LPTokenDetection_NonLPToken() public {
        // Create pair for conversion
        address pairAddr = uniswapFactory.createPair(
            address(token),
            address(otherToken)
        );
        MockUniswapV2Pair(pairAddr).setReserves(1000e18, 500e18);

        uint256 stakeAmount = 100e18;

        (
            ExtensionGroupAction groupAction,
            ExtensionGroupService groupService
        ) = _setupGroupActionAndService(
                address(otherToken),
                stakeAmount,
                500,
                501,
                50
            );

        // Mint enough tokens for activation stake (stakeAmount is 100e18, but we need more for safety)
        otherToken.mint(groupOwner1, stakeAmount * 3); // 300e18 to be safe
        vm.prank(groupOwner1);
        otherToken.approve(address(newGroupManager), type(uint256).max);

        vm.prank(groupOwner1, groupOwner1);
        newGroupManager.activateGroup(
            address(groupAction),
            groupId1,
            "NonLPGroup",
            0,
            1e18,
            0,
            0
        );

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // Verify it uses Uniswap conversion (not LP conversion)
        // Uniswap conversion: (amount * tokenReserve) / otherReserve
        uint256 expectedUniswap = (stakeAmount * 1000e18) / 500e18; // 200e18

        uint256 joinedVal = groupService.joinedValue();
        assertEq(
            joinedVal,
            expectedUniswap,
            "Should use Uniswap conversion for non-LP token"
        );
    }
}
