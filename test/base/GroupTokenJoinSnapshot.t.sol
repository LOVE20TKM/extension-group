// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "../utils/BaseGroupTest.sol";
import {
    GroupTokenJoinSnapshot
} from "../../src/base/GroupTokenJoinSnapshot.sol";
import {GroupTokenJoin} from "../../src/base/GroupTokenJoin.sol";
import {GroupCore} from "../../src/base/GroupCore.sol";
import {IGroupSnapshot} from "../../src/interface/base/IGroupSnapshot.sol";
import {ILOVE20GroupManager} from "../../src/interface/ILOVE20GroupManager.sol";
import {ExtensionAccounts} from "@extension/src/base/ExtensionAccounts.sol";

/**
 * @title MockGroupTokenJoinSnapshot
 * @notice Concrete implementation for testing
 */
contract MockGroupTokenJoinSnapshot is
    GroupTokenJoinSnapshot,
    ExtensionAccounts
{
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

    function _addAccount(
        address account
    ) internal override(ExtensionAccounts, GroupTokenJoin) {
        ExtensionAccounts._addAccount(account);
    }

    function _removeAccount(
        address account
    ) internal override(ExtensionAccounts, GroupTokenJoin) {
        ExtensionAccounts._removeAccount(account);
    }

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

    // Expose internal function for testing
    function triggerSnapshot(uint256 groupId) external {
        _snapshotIfNeeded(groupId);
    }
}

/**
 * @title GroupTokenJoinSnapshotTest
 * @notice Test suite for GroupTokenJoinSnapshot
 */
contract GroupTokenJoinSnapshotTest is BaseGroupTest {
    MockGroupTokenJoinSnapshot public snapshotContract;

    uint256 public groupId1;
    uint256 public groupId2;

    function setUp() public {
        setUpBase();

        snapshotContract = new MockGroupTokenJoinSnapshot(
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

        registerFactory(address(token), address(mockFactory));
        token.mint(address(this), 1e18);
        token.approve(address(mockFactory), type(uint256).max);
        mockFactory.registerExtension(
            address(snapshotContract),
            address(token)
        );

        groupId1 = setupGroupOwner(groupOwner1, 10000e18, "TestGroup1");
        groupId2 = setupGroupOwner(groupOwner2, 10000e18, "TestGroup2");

        prepareExtensionInit(
            address(snapshotContract),
            address(token),
            ACTION_ID
        );

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
            0
        );
    }

    // ============ snapshotIfNeeded Tests ============

    function test_SnapshotIfNeeded_CreatesSnapshot() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(snapshotContract));

        vm.prank(user1);
        snapshotContract.join(groupId1, joinAmount, new string[](0));

        // Advance round to get fresh snapshot
        advanceRound();
        uint256 round = verify.currentRound();

        // Trigger snapshot - now captures user1
        snapshotContract.triggerSnapshot(groupId1);

        // Verify snapshot data
        address[] memory accounts = snapshotContract.snapshotAccountsByGroupId(
            round,
            groupId1
        );
        assertEq(accounts.length, 1);
        assertEq(accounts[0], user1);

        assertEq(
            snapshotContract.snapshotAmountByAccount(round, user1),
            joinAmount
        );
        assertEq(
            snapshotContract.snapshotAmountByGroupId(round, groupId1),
            joinAmount
        );
        assertEq(snapshotContract.snapshotAmount(round), joinAmount);
    }

    function test_SnapshotIfNeeded_DoesNotDuplicateSnapshot() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(snapshotContract));

        vm.prank(user1);
        snapshotContract.join(groupId1, joinAmount, new string[](0));

        uint256 round = verify.currentRound();

        // Trigger snapshot twice
        snapshotContract.triggerSnapshot(groupId1);
        snapshotContract.triggerSnapshot(groupId1);

        // Should still only have one snapshot
        uint256[] memory groupIds = snapshotContract.snapshotGroupIds(round);
        assertEq(groupIds.length, 1);
    }

    function test_SnapshotIfNeeded_SkipsInactiveGroup() public {
        advanceRound();

        vm.prank(groupOwner1, groupOwner1);
        groupManager.deactivateGroup(address(token), ACTION_ID, groupId1);

        uint256 round = verify.currentRound();

        // Trigger snapshot on inactive group
        snapshotContract.triggerSnapshot(groupId1);

        // Should not create snapshot
        uint256[] memory groupIds = snapshotContract.snapshotGroupIds(round);
        assertEq(groupIds.length, 0);
    }

    // ============ Snapshot on Join Tests ============

    function test_SnapshotCreatedOnJoin() public {
        uint256 joinAmount1 = 10e18;
        uint256 joinAmount2 = 20e18;
        setupUser(user1, joinAmount1, address(snapshotContract));
        setupUser(user2, joinAmount2, address(snapshotContract));

        vm.prank(user1);
        snapshotContract.join(groupId1, joinAmount1, new string[](0));

        uint256 round = verify.currentRound();

        // First join triggers snapshot BEFORE user1 is added
        // Snapshot captures empty state
        address[] memory accountsAfterFirst = snapshotContract
            .snapshotAccountsByGroupId(round, groupId1);
        assertEq(accountsAfterFirst.length, 0);

        // Second join sees existing snapshot, doesn't create new one
        vm.prank(user2);
        snapshotContract.join(groupId1, joinAmount2, new string[](0));

        // Snapshot still shows empty (captured before first join)
        address[] memory accounts = snapshotContract.snapshotAccountsByGroupId(
            round,
            groupId1
        );
        assertEq(accounts.length, 0);
    }

    // ============ Snapshot on Exit Tests ============

    function test_SnapshotCreatedOnExit() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(snapshotContract));

        // First join creates snapshot with empty state
        vm.prank(user1);
        snapshotContract.join(groupId1, joinAmount, new string[](0));

        // Advance round so we get a new snapshot on exit
        advanceRound();

        uint256 round = verify.currentRound();

        // Exit triggers new snapshot which captures user1
        vm.prank(user1);
        snapshotContract.exit();

        // Snapshot should capture state before exit (with user1)
        address[] memory accounts = snapshotContract.snapshotAccountsByGroupId(
            round,
            groupId1
        );
        assertEq(accounts.length, 1);
        assertEq(accounts[0], user1);
        assertEq(
            snapshotContract.snapshotAmountByAccount(round, user1),
            joinAmount
        );
    }

    // ============ View Functions Tests ============

    function test_SnapshotAccountsByGroupId() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(snapshotContract));
        setupUser(user2, joinAmount, address(snapshotContract));

        vm.prank(user1);
        snapshotContract.join(groupId1, joinAmount, new string[](0));

        vm.prank(user2);
        snapshotContract.join(groupId1, joinAmount, new string[](0));

        // Advance round and trigger new snapshot to capture current state
        advanceRound();
        snapshotContract.triggerSnapshot(groupId1);

        uint256 round = verify.currentRound();
        address[] memory accounts = snapshotContract.snapshotAccountsByGroupId(
            round,
            groupId1
        );
        assertEq(accounts.length, 2);
        assertEq(
            snapshotContract.snapshotAccountsByGroupIdCount(round, groupId1),
            2
        );
    }

    function test_SnapshotAccountsByGroupIdAtIndex() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(snapshotContract));

        vm.prank(user1);
        snapshotContract.join(groupId1, joinAmount, new string[](0));

        // Advance round and trigger new snapshot
        advanceRound();
        snapshotContract.triggerSnapshot(groupId1);

        uint256 round = verify.currentRound();
        assertEq(
            snapshotContract.snapshotAccountsByGroupIdAtIndex(
                round,
                groupId1,
                0
            ),
            user1
        );
    }

    function test_SnapshotAmountByAccount() public {
        uint256 joinAmount = 15e18;
        setupUser(user1, joinAmount, address(snapshotContract));

        vm.prank(user1);
        snapshotContract.join(groupId1, joinAmount, new string[](0));

        // Advance round and trigger new snapshot
        advanceRound();
        snapshotContract.triggerSnapshot(groupId1);

        uint256 round = verify.currentRound();
        assertEq(
            snapshotContract.snapshotAmountByAccount(round, user1),
            joinAmount
        );
    }

    function test_SnapshotAmountByGroupId() public {
        uint256 joinAmount1 = 10e18;
        uint256 joinAmount2 = 20e18;
        setupUser(user1, joinAmount1, address(snapshotContract));
        setupUser(user2, joinAmount2, address(snapshotContract));

        vm.prank(user1);
        snapshotContract.join(groupId1, joinAmount1, new string[](0));

        vm.prank(user2);
        snapshotContract.join(groupId1, joinAmount2, new string[](0));

        // Advance round and trigger new snapshot
        advanceRound();
        snapshotContract.triggerSnapshot(groupId1);

        uint256 round = verify.currentRound();
        assertEq(
            snapshotContract.snapshotAmountByGroupId(round, groupId1),
            joinAmount1 + joinAmount2
        );
    }

    function test_SnapshotAmount() public {
        uint256 joinAmount1 = 10e18;
        uint256 joinAmount2 = 20e18;
        setupUser(user1, joinAmount1, address(snapshotContract));
        setupUser(user2, joinAmount2, address(snapshotContract));

        vm.prank(user1);
        snapshotContract.join(groupId1, joinAmount1, new string[](0));

        vm.prank(user2);
        snapshotContract.join(groupId2, joinAmount2, new string[](0));

        // Advance round and trigger new snapshots
        advanceRound();
        snapshotContract.triggerSnapshot(groupId1);
        snapshotContract.triggerSnapshot(groupId2);

        uint256 round = verify.currentRound();
        assertEq(
            snapshotContract.snapshotAmount(round),
            joinAmount1 + joinAmount2
        );
    }

    function test_SnapshotGroupIds() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(snapshotContract));
        setupUser(user2, joinAmount, address(snapshotContract));

        vm.prank(user1);
        snapshotContract.join(groupId1, joinAmount, new string[](0));

        vm.prank(user2);
        snapshotContract.join(groupId2, joinAmount, new string[](0));

        snapshotContract.triggerSnapshot(groupId1);
        snapshotContract.triggerSnapshot(groupId2);

        uint256 round = verify.currentRound();
        uint256[] memory groupIds = snapshotContract.snapshotGroupIds(round);
        assertEq(groupIds.length, 2);
        assertEq(snapshotContract.snapshotGroupIdsCount(round), 2);
    }

    function test_SnapshotGroupIdsAtIndex() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(snapshotContract));

        vm.prank(user1);
        snapshotContract.join(groupId1, joinAmount, new string[](0));

        snapshotContract.triggerSnapshot(groupId1);

        uint256 round = verify.currentRound();
        assertEq(snapshotContract.snapshotGroupIdsAtIndex(round, 0), groupId1);
    }

    // ============ Cross-Round Tests ============

    function test_SnapshotPerRound() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(snapshotContract));

        vm.prank(user1);
        snapshotContract.join(groupId1, joinAmount, new string[](0));

        uint256 round1 = verify.currentRound();
        snapshotContract.triggerSnapshot(groupId1);

        // Advance round
        advanceRound();
        uint256 round2 = verify.currentRound();

        // New snapshot in new round
        snapshotContract.triggerSnapshot(groupId1);

        // Both rounds should have snapshots
        assertEq(snapshotContract.snapshotGroupIdsCount(round1), 1);
        assertEq(snapshotContract.snapshotGroupIdsCount(round2), 1);
    }

    // ============ Event Tests ============

    // Re-declare event for testing (must match interface definition exactly)
    event SnapshotCreate(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        uint256 groupId
    );

    function test_SnapshotCreate_EmitsEvent() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(snapshotContract));

        vm.prank(user1);
        snapshotContract.join(groupId1, joinAmount, new string[](0));

        // Advance round to allow new snapshot
        advanceRound();
        // Setup actionId for new round
        vote.setVotedActionIds(
            address(token),
            verify.currentRound(),
            ACTION_ID
        );
        uint256 round = verify.currentRound();

        vm.expectEmit(true, true, true, true);
        emit SnapshotCreate(address(token), round, ACTION_ID, groupId1);

        snapshotContract.triggerSnapshot(groupId1);
    }
}
