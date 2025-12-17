// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "./utils/BaseGroupTest.sol";
import {
    LOVE20ExtensionGroupService
} from "../src/LOVE20ExtensionGroupService.sol";
import {
    LOVE20ExtensionGroupAction
} from "../src/LOVE20ExtensionGroupAction.sol";
import {LOVE20GroupDistrust} from "../src/LOVE20GroupDistrust.sol";
import {
    ILOVE20ExtensionGroupService
} from "../src/interface/ILOVE20ExtensionGroupService.sol";
import {ILOVE20GroupManager} from "../src/interface/ILOVE20GroupManager.sol";
import {IJoin} from "@extension/src/interface/base/IJoin.sol";
import {
    MockExtensionFactory
} from "@extension/test/mocks/MockExtensionFactory.sol";

/**
 * @title LOVE20ExtensionGroupServiceTest
 * @notice Test suite for LOVE20ExtensionGroupService
 */
contract LOVE20ExtensionGroupServiceTest is BaseGroupTest {
    // Re-declare event for testing
    event RecipientsUpdate(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        address indexed account,
        address[] recipients,
        uint256[] basisPoints
    );
    LOVE20ExtensionGroupService public groupService;
    LOVE20ExtensionGroupAction public groupAction;
    LOVE20GroupDistrust public groupDistrust;
    MockExtensionFactory public actionFactory;
    MockExtensionFactory public serviceFactory;

    uint256 public groupId1;
    uint256 public groupId2;

    uint256 constant MAX_RECIPIENTS = 10;
    uint256 constant SERVICE_ACTION_ID = 2;

    function setUp() public {
        setUpBase();

        // Deploy separate factories for actions and services
        actionFactory = new MockExtensionFactory(address(center));
        serviceFactory = new MockExtensionFactory(address(center));

        // Deploy GroupDistrust singleton
        groupDistrust = new LOVE20GroupDistrust(
            address(center),
            address(verify),
            address(group)
        );

        // Deploy GroupAction first (as dependency)
        groupAction = new LOVE20ExtensionGroupAction(
            address(actionFactory),
            address(token),
            address(groupManager),
            address(groupDistrust),
            address(token),
            MIN_GOV_VOTE_RATIO_BPS,
            CAPACITY_MULTIPLIER,
            STAKING_MULTIPLIER,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            MIN_JOIN_AMOUNT
        );

        // Deploy GroupService (use actionFactory as GROUP_ACTION_FACTORY_ADDRESS)
        groupService = new LOVE20ExtensionGroupService(
            address(serviceFactory),
            address(token),
            address(token), // groupActionTokenAddress
            address(actionFactory),
            MAX_RECIPIENTS
        );

        // Register extensions to their respective factories
        token.mint(address(this), 2e18);
        token.approve(address(actionFactory), type(uint256).max);
        token.approve(address(serviceFactory), type(uint256).max);
        actionFactory.registerExtension(address(groupAction), address(token));
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
        setupUser(member, amount, address(groupAction));

        vm.prank(member);
        groupAction.join(groupId, amount, new string[](0));

        // Advance round and setup actionIds for new round
        uint256[] memory scores = new uint256[](1);
        scores[0] = score;

        vm.prank(owner);
        groupAction.submitOriginScore(groupId, 0, scores);
    }

    /**
     * @notice Helper to setup actionIds for current round after advanceRound
     */
    function _setupActionIdsForCurrentRound() internal {
        uint256 currentRound = verify.currentRound();
        vote.setVotedActionIds(address(token), currentRound, ACTION_ID);
        vote.setVotedActionIds(address(token), currentRound, SERVICE_ACTION_ID);
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsImmutables() public view {
        assertEq(groupService.GROUP_ACTION_TOKEN_ADDRESS(), address(token));
        assertEq(
            groupService.GROUP_ACTION_FACTORY_ADDRESS(),
            address(actionFactory)
        );
        assertEq(groupService.MAX_RECIPIENTS(), MAX_RECIPIENTS);
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
        groupManager.deactivateGroup(address(token), ACTION_ID, groupId1);

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
        basisPoints[0] = 3000; // 30%
        basisPoints[1] = 2000; // 20%

        vm.prank(groupOwner1);
        groupService.setRecipients(recipients, basisPoints);

        uint256 round = verify.currentRound();
        (address[] memory addrs, uint256[] memory points) = groupService
            .recipients(groupOwner1, round);

        assertEq(addrs.length, 2);
        assertEq(addrs[0], recipients[0]);
        assertEq(addrs[1], recipients[1]);
        assertEq(points[0], 3000);
        assertEq(points[1], 2000);
    }

    function test_SetRecipients_RevertNotJoined() public {
        address[] memory recipients = new address[](1);
        recipients[0] = address(0x100);

        uint256[] memory basisPoints = new uint256[](1);
        basisPoints[0] = 5000;

        vm.prank(groupOwner1);
        vm.expectRevert(IJoin.NotJoined.selector);
        groupService.setRecipients(recipients, basisPoints);
    }

    function test_SetRecipients_RevertArrayLengthMismatch() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        address[] memory recipients = new address[](2);
        recipients[0] = address(0x100);
        recipients[1] = address(0x200);

        uint256[] memory basisPoints = new uint256[](1);
        basisPoints[0] = 5000;

        vm.prank(groupOwner1);
        vm.expectRevert(
            ILOVE20ExtensionGroupService.ArrayLengthMismatch.selector
        );
        groupService.setRecipients(recipients, basisPoints);
    }

    function test_SetRecipients_RevertTooManyRecipients() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        address[] memory recipients = new address[](MAX_RECIPIENTS + 1);
        uint256[] memory basisPoints = new uint256[](MAX_RECIPIENTS + 1);

        for (uint256 i = 0; i < MAX_RECIPIENTS + 1; i++) {
            recipients[i] = address(uint160(0x100 + i));
            basisPoints[i] = 100;
        }

        vm.prank(groupOwner1);
        vm.expectRevert(
            ILOVE20ExtensionGroupService.TooManyRecipients.selector
        );
        groupService.setRecipients(recipients, basisPoints);
    }

    function test_SetRecipients_RevertZeroAddress() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        address[] memory recipients = new address[](1);
        recipients[0] = address(0);

        uint256[] memory basisPoints = new uint256[](1);
        basisPoints[0] = 5000;

        vm.prank(groupOwner1);
        vm.expectRevert(ILOVE20ExtensionGroupService.ZeroAddress.selector);
        groupService.setRecipients(recipients, basisPoints);
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
        groupService.setRecipients(recipients, basisPoints);
    }

    function test_SetRecipients_RevertInvalidBasisPoints() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        address[] memory recipients = new address[](2);
        recipients[0] = address(0x100);
        recipients[1] = address(0x200);

        uint256[] memory basisPoints = new uint256[](2);
        basisPoints[0] = 6000; // 60%
        basisPoints[1] = 5000; // 50% - total > 100%

        vm.prank(groupOwner1);
        vm.expectRevert(
            ILOVE20ExtensionGroupService.InvalidBasisPoints.selector
        );
        groupService.setRecipients(recipients, basisPoints);
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
        basisPoints1[0] = 3000;

        vm.prank(groupOwner1);
        groupService.setRecipients(recipients1, basisPoints1);

        uint256 round1 = verify.currentRound();

        // Advance round and setup actionIds for new round
        advanceRound();
        _setupActionIdsForCurrentRound();
        uint256 round2 = verify.currentRound();

        // Set different recipients in round 2
        address[] memory recipients2 = new address[](1);
        recipients2[0] = address(0x200);
        uint256[] memory basisPoints2 = new uint256[](1);
        basisPoints2[0] = 4000;

        vm.prank(groupOwner1);
        groupService.setRecipients(recipients2, basisPoints2);

        // Check round 1 recipients
        (address[] memory addrs1, uint256[] memory points1) = groupService
            .recipients(groupOwner1, round1);
        assertEq(addrs1[0], address(0x100));
        assertEq(points1[0], 3000);

        // Check round 2 recipients
        (address[] memory addrs2, uint256[] memory points2) = groupService
            .recipients(groupOwner1, round2);
        assertEq(addrs2[0], address(0x200));
        assertEq(points2[0], 4000);
    }

    function test_RecipientsLatest() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        address[] memory recipients = new address[](1);
        recipients[0] = address(0x100);
        uint256[] memory basisPoints = new uint256[](1);
        basisPoints[0] = 3000;

        vm.prank(groupOwner1);
        groupService.setRecipients(recipients, basisPoints);

        (address[] memory addrs, uint256[] memory points) = groupService
            .recipientsLatest(groupOwner1);
        assertEq(addrs.length, 1);
        assertEq(addrs[0], address(0x100));
        assertEq(points[0], 3000);
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
        basisPoints[0] = 3000; // 30%

        vm.prank(groupOwner1);
        groupService.setRecipients(recipients, basisPoints);

        // Simulate reward (this would normally be set by the reward system)
        // For testing, we check the calculation logic
        uint256 round = verify.currentRound();

        // RewardByRecipient returns 0 if no reward set
        uint256 recipientReward = groupService.rewardByRecipient(
            round,
            groupOwner1,
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
        basisPoints[0] = 3000; // 30%

        vm.prank(groupOwner1);
        groupService.setRecipients(recipients, basisPoints);

        uint256 round = verify.currentRound();

        // Owner gets remaining (70%)
        uint256 ownerReward = groupService.rewardByRecipient(
            round,
            groupOwner1,
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
        basisPoints[0] = 3000; // 30%
        basisPoints[1] = 2000; // 20%

        vm.prank(groupOwner1);
        groupService.setRecipients(recipients, basisPoints);

        uint256 round = verify.currentRound();

        (
            address[] memory addrs,
            uint256[] memory points,
            uint256[] memory amounts,
            uint256 ownerAmount
        ) = groupService.rewardDistribution(round, groupOwner1);

        assertEq(addrs.length, 2);
        assertEq(points.length, 2);
        assertEq(amounts.length, 2);
        // With no reward, all amounts should be 0
        assertEq(amounts[0], 0);
        assertEq(amounts[1], 0);
        assertEq(ownerAmount, 0);
    }

    // ============ IExtensionJoinedValue Tests ============

    function test_IsJoinedValueCalculated() public view {
        assertFalse(groupService.isJoinedValueCalculated());
    }

    function test_JoinedValue() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);
        setupGroupActionWithScores(groupId2, groupOwner2, user2, 20e18, 80);

        // joinedValue should return totalStaked from groupManager
        uint256 joinedVal = groupService.joinedValue();
        assertEq(
            joinedVal,
            groupManager.totalStaked(address(token), ACTION_ID)
        );
    }

    function test_JoinedValueByAccount() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        uint256 ownerValue = groupService.joinedValueByAccount(groupOwner1);
        assertEq(
            ownerValue,
            groupManager.totalStakedByOwner(
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
        basisPoints[0] = 3000;

        uint256 round = verify.currentRound();

        vm.expectEmit(true, true, true, true);
        emit RecipientsUpdate(
            address(token),
            round,
            SERVICE_ACTION_ID,
            groupOwner1,
            recipients,
            basisPoints
        );

        vm.prank(groupOwner1);
        groupService.setRecipients(recipients, basisPoints);
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

        // Both set different recipients
        address[] memory recipients1 = new address[](1);
        recipients1[0] = address(0x100);
        uint256[] memory basisPoints1 = new uint256[](1);
        basisPoints1[0] = 3000;

        vm.prank(groupOwner1);
        groupService.setRecipients(recipients1, basisPoints1);

        address[] memory recipients2 = new address[](1);
        recipients2[0] = address(0x200);
        uint256[] memory basisPoints2 = new uint256[](1);
        basisPoints2[0] = 4000;

        vm.prank(groupOwner2);
        groupService.setRecipients(recipients2, basisPoints2);

        // Verify independent recipients
        uint256 round = verify.currentRound();

        (address[] memory addrs1, ) = groupService.recipients(
            groupOwner1,
            round
        );
        (address[] memory addrs2, ) = groupService.recipients(
            groupOwner2,
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
        groupService.setRecipients(recipients, basisPoints);

        uint256 round = verify.currentRound();
        (address[] memory addrs, uint256[] memory points) = groupService
            .recipients(groupOwner1, round);

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
        basisPoints1[0] = 3000;

        vm.prank(groupOwner1);
        groupService.setRecipients(recipients1, basisPoints1);

        // Update in same round
        address[] memory recipients2 = new address[](1);
        recipients2[0] = address(0x200);
        uint256[] memory basisPoints2 = new uint256[](1);
        basisPoints2[0] = 5000;

        vm.prank(groupOwner1);
        groupService.setRecipients(recipients2, basisPoints2);

        uint256 round = verify.currentRound();
        (address[] memory addrs, uint256[] memory points) = groupService
            .recipients(groupOwner1, round);

        assertEq(addrs[0], address(0x200));
        assertEq(points[0], 5000);
    }

    function test_MaxBasisPoints() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        vm.prank(groupOwner1);
        groupService.join(new string[](0));

        // 100% to recipients
        address[] memory recipients = new address[](1);
        recipients[0] = address(0x100);
        uint256[] memory basisPoints = new uint256[](1);
        basisPoints[0] = 10000; // 100%

        vm.prank(groupOwner1);
        groupService.setRecipients(recipients, basisPoints);

        uint256 round = verify.currentRound();
        (address[] memory addrs, uint256[] memory points) = groupService
            .recipients(groupOwner1, round);

        assertEq(addrs[0], address(0x100));
        assertEq(points[0], 10000);
    }

    // ============ hasActiveGroups Tests ============

    function test_HasActiveGroups_True() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);

        assertTrue(groupService.hasActiveGroups(groupOwner1));
    }

    function test_HasActiveGroups_False_NoStake() public {
        // user3 has no stake in any group
        assertFalse(groupService.hasActiveGroups(user3));
    }

    function test_HasActiveGroups_False_AfterDeactivate() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);
        assertTrue(groupService.hasActiveGroups(groupOwner1));

        advanceRound();
        _setupActionIdsForCurrentRound();

        vm.prank(groupOwner1, groupOwner1);
        groupManager.deactivateGroup(address(token), ACTION_ID, groupId1);

        assertFalse(groupService.hasActiveGroups(groupOwner1));
    }

    function test_HasActiveGroups_MultipleGroups() public {
        setupGroupActionWithScores(groupId1, groupOwner1, user1, 10e18, 80);
        setupGroupActionWithScores(groupId2, groupOwner2, user2, 20e18, 90);

        assertTrue(groupService.hasActiveGroups(groupOwner1));
        assertTrue(groupService.hasActiveGroups(groupOwner2));
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
}
