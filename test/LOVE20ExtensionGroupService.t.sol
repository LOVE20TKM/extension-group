// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "./utils/BaseGroupTest.sol";
import {
    LOVE20ExtensionGroupService
} from "../src/LOVE20ExtensionGroupService.sol";
import {
    LOVE20ExtensionGroupAction
} from "../src/LOVE20ExtensionGroupAction.sol";
import {
    ILOVE20ExtensionGroupService
} from "../src/interface/ILOVE20ExtensionGroupService.sol";
import {GroupManager} from "../src/GroupManager.sol";
import {GroupJoin} from "../src/GroupJoin.sol";
import {GroupVerify} from "../src/GroupVerify.sol";
import {IGroupManager} from "../src/interface/IGroupManager.sol";
import {IGroupJoin} from "../src/interface/IGroupJoin.sol";
import {IGroupVerify} from "../src/interface/IGroupVerify.sol";
import {IJoin} from "@extension/src/interface/base/IJoin.sol";
import {
    MockExtensionFactory
} from "@extension/test/mocks/MockExtensionFactory.sol";
import {
    LOVE20ExtensionGroupActionFactory
} from "../src/LOVE20ExtensionGroupActionFactory.sol";
import {MockERC20} from "@extension/test/mocks/MockERC20.sol";
import {MockUniswapV2Pair} from "@extension/test/mocks/MockUniswapV2Pair.sol";
import {
    RoundHistoryAddressArray
} from "@extension/src/lib/RoundHistoryAddressArray.sol";
import {
    RoundHistoryUint256Array
} from "@extension/src/lib/RoundHistoryUint256Array.sol";

/**
 * @title LOVE20ExtensionGroupServiceTest
 * @notice Test suite for LOVE20ExtensionGroupService
 */
contract LOVE20ExtensionGroupServiceTest is BaseGroupTest {
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
    LOVE20ExtensionGroupService public groupService;
    LOVE20ExtensionGroupAction public groupAction;
    LOVE20ExtensionGroupActionFactory public actionFactory;
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
        // because LOVE20ExtensionGroupActionFactory constructor will initialize them
        newGroupManager = new GroupManager();
        newGroupJoin = new GroupJoin();
        newGroupVerify = new GroupVerify();

        // Deploy actionFactory with new singleton instances
        actionFactory = new LOVE20ExtensionGroupActionFactory(
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
        groupAction = LOVE20ExtensionGroupAction(groupActionAddress);

        // Deploy GroupService (use actionFactory as GROUP_ACTION_FACTORY_ADDRESS)
        token.approve(address(serviceFactory), type(uint256).max);
        groupService = new LOVE20ExtensionGroupService(
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
            address(token),
            ACTION_ID,
            groupId1,
            "Group1",
            0, // maxCapacity
            1e18, // minJoinAmount
            0,
            0
        );

        vm.prank(groupOwner2, groupOwner2);
        newGroupManager.activateGroup(
            address(token),
            ACTION_ID,
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
            address(token),
            ACTION_ID,
            groupId,
            amount,
            new string[](0)
        );

        // Advance round and setup actionIds for new round
        uint256[] memory scores = new uint256[](1);
        scores[0] = score;

        vm.prank(owner);
        newGroupVerify.verifyWithOriginScores(
            address(token),
            ACTION_ID,
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
        newGroupManager.deactivateGroup(address(token), ACTION_ID, groupId1);

        vm.prank(groupOwner1);
        vm.expectRevert(ILOVE20ExtensionGroupService.NoActiveGroups.selector);
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
        vm.expectRevert(ILOVE20ExtensionGroupService.NotGroupOwner.selector);
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
        vm.expectRevert(
            ILOVE20ExtensionGroupService.ArrayLengthMismatch.selector
        );
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
        vm.expectRevert(
            ILOVE20ExtensionGroupService.TooManyRecipients.selector
        );
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
        vm.expectRevert(ILOVE20ExtensionGroupService.ZeroAddress.selector);
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
        vm.expectRevert(ILOVE20ExtensionGroupService.ZeroBasisPoints.selector);
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
        vm.expectRevert(
            ILOVE20ExtensionGroupService.InvalidBasisPoints.selector
        );
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
        vm.expectRevert(
            ILOVE20ExtensionGroupService.RecipientCannotBeSelf.selector
        );
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

        ILOVE20ExtensionGroupService.GroupDistribution[]
            memory distributions = groupService.rewardDistributionAll(
                round,
                groupOwner1
            );

        // Should have 1 distribution (for groupId1)
        assertEq(distributions.length, 1);
        assertEq(distributions[0].actionId, ACTION_ID);
        assertEq(distributions[0].groupId, groupId1);
        assertEq(distributions[0].recipients.length, 1);
        assertEq(distributions[0].recipients[0], address(0x100));
        assertEq(distributions[0].basisPoints[0], 3e17);
    }

    // ============ IExtensionJoinedValue Tests ============

    function test_IsJoinedValueCalculated() public view {
        assertTrue(groupService.isJoinedValueCalculated());
    }

    function test_JoinedValue() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);
        setupGroupActionWithScores(groupId2, groupOwner2, user2, 20e18, 80);

        // joinedValue should return totalStaked from groupManager
        uint256 joinedVal = groupService.joinedValue();
        assertEq(
            joinedVal,
            newGroupManager.totalStaked(address(token), ACTION_ID)
        );
    }

    function test_JoinedValueByAccount() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        uint256 ownerValue = groupService.joinedValueByAccount(groupOwner1);
        assertEq(
            ownerValue,
            newGroupManager.totalStakedByActionIdByOwner(
                address(token),
                ACTION_ID,
                groupOwner1
            )
        );

        // Non-joined account
        uint256 user2Value = groupService.joinedValueByAccount(user2);
        assertEq(user2Value, 0);
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
        newGroupManager.deactivateGroup(address(token), ACTION_ID, groupId1);

        assertFalse(groupService.hasActiveGroups(groupOwner1));
    }

    function test_HasActiveGroups_MultipleGroups() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);
        setupGroupActionWithScores(groupId2, groupOwner2, user2, 20e18, 90);

        assertTrue(groupService.hasActiveGroups(groupOwner1));
        assertTrue(groupService.hasActiveGroups(groupOwner2));
    }

    // ============ votedGroupActions Tests ============

    function test_votedGroupActions_Empty() public view {
        // Use a round that has no voted actionIds
        uint256 emptyRound = 999;
        (uint256[] memory aids, address[] memory exts) = groupService
            .votedGroupActions(emptyRound);

        assertEq(exts.length, 0);
        assertEq(aids.length, 0);
    }

    function test_votedGroupActions_SingleValid() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        uint256 round = verify.currentRound();
        (uint256[] memory aids, address[] memory exts) = groupService
            .votedGroupActions(round);

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
        LOVE20ExtensionGroupAction groupAction2 = LOVE20ExtensionGroupAction(
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
            address(token),
            actionId2,
            groupId3,
            "Group3",
            0, // maxCapacity
            1e18, // minJoinAmount
            0,
            0
        );

        uint256 round = verify.currentRound();
        (uint256[] memory aids, address[] memory exts) = groupService
            .votedGroupActions(round);

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
        uint256 invalidActionId = 200;
        address invalidExtension = address(0x999);
        submit.setActionInfo(address(token), invalidActionId, invalidExtension);
        vote.setVotedActionIds(
            address(token),
            verify.currentRound(),
            invalidActionId
        );

        uint256 round = verify.currentRound();
        (uint256[] memory aids, address[] memory exts) = groupService
            .votedGroupActions(round);

        // Should only return the valid one
        assertEq(exts.length, 1);
        assertEq(aids.length, 1);
        assertEq(exts[0], address(groupAction));
        assertEq(aids[0], ACTION_ID);
    }

    function test_votedGroupActions_FiltersZeroExtension() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        // Add an actionId with zero extension address
        uint256 zeroActionId = 300;
        vote.setVotedActionIds(
            address(token),
            verify.currentRound(),
            zeroActionId
        );
        // Don't set extension, so it will be address(0)

        uint256 round = verify.currentRound();
        (uint256[] memory aids, address[] memory exts) = groupService
            .votedGroupActions(round);

        // Should only return the valid one
        assertEq(exts.length, 1);
        assertEq(aids.length, 1);
        assertEq(exts[0], address(groupAction));
        assertEq(aids[0], ACTION_ID);
    }

    function test_votedGroupActions_DifferentRounds() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        uint256 round1 = verify.currentRound();
        (uint256[] memory aids1, address[] memory exts1) = groupService
            .votedGroupActions(round1);

        assertEq(exts1.length, 1);
        assertEq(aids1.length, 1);

        // Advance to next round but don't setup actionIds for this round
        advanceRound();

        uint256 round2 = verify.currentRound();
        (uint256[] memory aids2, address[] memory exts2) = groupService
            .votedGroupActions(round2);

        // Round2 should have no valid actions (no voted actionIds in round2)
        assertEq(exts2.length, 0);
        assertEq(aids2.length, 0);

        // Round1 should still return the same result
        (
            uint256[] memory aids1Again,
            address[] memory exts1Again
        ) = groupService.votedGroupActions(round1);
        assertEq(exts1Again.length, 1);
        assertEq(aids1Again.length, 1);
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
            address(token),
            ACTION_ID,
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
 * @title LOVE20ExtensionGroupServiceStakeTokenTest
 * @notice Test suite for stakeToken conversion in LOVE20ExtensionGroupService
 */
contract LOVE20ExtensionGroupServiceStakeTokenTest is BaseGroupTest {
    LOVE20ExtensionGroupActionFactory public actionFactory;
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
        // because LOVE20ExtensionGroupActionFactory constructor will initialize them
        newGroupManager = new GroupManager();
        newGroupJoin = new GroupJoin();
        newGroupVerify = new GroupVerify();

        // Deploy actionFactory with new singleton instances
        actionFactory = new LOVE20ExtensionGroupActionFactory(
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
            LOVE20ExtensionGroupAction groupAction,
            LOVE20ExtensionGroupService groupService
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
        groupAction = LOVE20ExtensionGroupAction(groupActionAddress);

        // Deploy GroupService
        token.approve(address(serviceFactory), type(uint256).max);
        groupService = new LOVE20ExtensionGroupService(
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
            ,
            LOVE20ExtensionGroupService groupService
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
            address(token),
            100,
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
            address(token),
            100, // Use actionId 100 that was set up in _setupGroupActionAndService
            groupId1,
            50e18,
            new string[](0)
        );

        // Owner joins service
        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // Verify joinedValue equals total staked (no conversion)
        uint256 totalStaked = newGroupManager.totalStaked(address(token), 100);
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
            ,
            LOVE20ExtensionGroupService groupService
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
            address(token),
            200,
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
        uint256 lpStaked = newGroupManager.totalStaked(address(token), 200);
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
            ,
            LOVE20ExtensionGroupService groupService
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
            address(token),
            300,
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
        uint256 staked = newGroupManager.totalStaked(address(token), 300);
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
            ,
            LOVE20ExtensionGroupService groupService
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
            address(token),
            400,
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
            ,
            LOVE20ExtensionGroupService groupService
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
            address(token),
            500,
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
