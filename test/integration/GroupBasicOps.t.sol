// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupFlowTest} from "./base/BaseGroupFlowTest.sol";
import {GroupUserParams} from "./helper/TestGroupFlowHelper.sol";
import {
    LOVE20ExtensionGroupAction
} from "../../src/LOVE20ExtensionGroupAction.sol";

/// @title GroupBasicOpsTest
/// @notice Integration tests for basic group operations: expansion, deactivation, exit/rejoin, etc.
contract GroupBasicOpsTest is BaseGroupFlowTest {
    /// @notice Test group expansion
    function test_group_expansion() public {
        // 1. Setup group action
        address extensionAddr = h.group_action_create(bobGroup1);
        bobGroup1.groupActionAddress = extensionAddr;
        uint256 actionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = actionId;
        bobGroup1.groupActionId = actionId;

        h.vote(bobGroup1.flow);
        h.next_phase();

        // Use moderate stake for activation to leave room for expansion (50M tokens)
        bobGroup1.stakeAmount = 50_000_000e18;
        h.group_activate(bobGroup1);

        // 2. Get initial capacity
        (, , uint256 initialStaked, uint256 initialCapacity, , , , , , ) = h
            .getGroupManager()
            .groupInfo(h.firstTokenAddress(), actionId, bobGroup1.groupId);

        // 3. Expand the group with small amount (10M tokens)
        uint256 additionalStake = 10_000_000e18;
        h.group_expand(bobGroup1, additionalStake);

        // 4. Verify expansion
        (, , uint256 newStaked, uint256 newCapacity, , , , , , ) = h
            .getGroupManager()
            .groupInfo(h.firstTokenAddress(), actionId, bobGroup1.groupId);

        assertEq(
            newStaked,
            initialStaked + additionalStake,
            "Staked amount mismatch"
        );
        assertTrue(newCapacity >= initialCapacity, "Capacity should increase");
    }

    /// @notice Test group deactivation
    function test_group_deactivation() public {
        // 1. Setup group action
        address extensionAddr = h.group_action_create(bobGroup1);
        bobGroup1.groupActionAddress = extensionAddr;
        uint256 actionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = actionId;
        bobGroup1.groupActionId = actionId;

        h.vote(bobGroup1.flow);
        h.next_phase();
        h.group_activate(bobGroup1);

        assertTrue(
            h.getGroupManager().isGroupActive(
                h.firstTokenAddress(),
                actionId,
                bobGroup1.groupId
            ),
            "Group should be active"
        );

        // 2. Deactivate (need to advance round first)
        h.next_phase();
        h.group_deactivate(bobGroup1);

        // 3. Verify deactivation
        assertFalse(
            h.getGroupManager().isGroupActive(
                h.firstTokenAddress(),
                actionId,
                bobGroup1.groupId
            ),
            "Group should be deactivated"
        );
    }

    /// @notice Test behavior across multiple rounds
    function test_cross_round_behavior() public {
        // 1. Setup group action
        address extensionAddr = h.group_action_create(bobGroup1);
        bobGroup1.groupActionAddress = extensionAddr;
        uint256 actionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = actionId;
        bobGroup1.groupActionId = actionId;

        h.vote(bobGroup1.flow);
        h.next_phase();
        h.group_activate(bobGroup1);

        // 2. Member joins
        GroupUserParams memory m1;
        m1.flow = member1;
        m1.joinAmount = 10e18;
        m1.groupActionAddress = bobGroup1.groupActionAddress;
        h.group_join(m1, bobGroup1);

        // 3. Round 1: Submit scores
        h.next_phase();
        uint256 round1 = h.verifyContract().currentRound();

        uint256[] memory scores1 = new uint256[](1);
        scores1[0] = 80;
        h.group_submit_score(bobGroup1, scores1);

        LOVE20ExtensionGroupAction groupAction = LOVE20ExtensionGroupAction(
            extensionAddr
        );

        // Verify round 1 score
        assertEq(
            groupAction.originScoreByAccount(round1, member1.userAddress),
            80,
            "Round 1 score mismatch"
        );

        // 4. Advance to next rounds
        h.next_phases(3);
        uint256 round2 = h.verifyContract().currentRound();

        // 5. Submit different scores in round 2
        uint256[] memory scores2 = new uint256[](1);
        scores2[0] = 90;
        h.group_submit_score(bobGroup1, scores2);

        // 6. Verify scores are round-specific
        assertEq(
            groupAction.originScoreByAccount(round1, member1.userAddress),
            80,
            "Round 1 score should remain 80"
        );
        assertEq(
            groupAction.originScoreByAccount(round2, member1.userAddress),
            90,
            "Round 2 score should be 90"
        );
    }

    /// @notice Test member exit and rejoin
    function test_member_exit_and_rejoin() public {
        // 1. Setup
        address extensionAddr = h.group_action_create(bobGroup1);
        bobGroup1.groupActionAddress = extensionAddr;
        uint256 actionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = actionId;
        bobGroup1.groupActionId = actionId;

        h.vote(bobGroup1.flow);
        h.next_phase();
        h.group_activate(bobGroup1);

        // 2. Member joins
        GroupUserParams memory m1;
        m1.flow = member1;
        m1.joinAmount = 10e18;
        m1.groupActionAddress = bobGroup1.groupActionAddress;
        h.group_join(m1, bobGroup1);

        LOVE20ExtensionGroupAction groupAction = LOVE20ExtensionGroupAction(
            extensionAddr
        );

        // Verify joined
        (uint256 joinedRound, , ) = groupAction.joinInfo(member1.userAddress);
        assertTrue(joinedRound > 0, "Should be joined");

        // 3. Member exits
        h.group_exit(m1, bobGroup1);

        // Verify exited
        (joinedRound, , ) = groupAction.joinInfo(member1.userAddress);
        assertEq(joinedRound, 0, "Should not be joined after exit");

        // 4. Member rejoins with different amount
        m1.joinAmount = 15e18;
        h.group_join(m1, bobGroup1);

        // Verify rejoined
        uint256 amount;
        (joinedRound, amount, ) = groupAction.joinInfo(member1.userAddress);
        assertTrue(joinedRound > 0, "Should be joined after rejoin");
        assertEq(amount, 15e18, "Amount should be 15e18");
    }

    /// @notice Test IExtensionJoinedValue interface
    function test_joined_value_calculation() public {
        // 1. Setup
        address extensionAddr = h.group_action_create(bobGroup1);
        bobGroup1.groupActionAddress = extensionAddr;
        uint256 actionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = actionId;
        bobGroup1.groupActionId = actionId;

        h.vote(bobGroup1.flow);
        h.next_phase();
        h.group_activate(bobGroup1);

        LOVE20ExtensionGroupAction groupAction = LOVE20ExtensionGroupAction(
            extensionAddr
        );

        // Initial joined value should be 0
        assertEq(
            groupAction.joinedValue(),
            0,
            "Initial joined value should be 0"
        );

        // 2. Members join
        GroupUserParams memory m1;
        m1.flow = member1;
        m1.joinAmount = 10e18;
        m1.groupActionAddress = bobGroup1.groupActionAddress;
        h.group_join(m1, bobGroup1);

        GroupUserParams memory m2;
        m2.flow = member2;
        m2.joinAmount = 20e18;
        m2.groupActionAddress = bobGroup1.groupActionAddress;
        h.group_join(m2, bobGroup1);

        // 3. Verify joined values
        assertEq(
            groupAction.joinedValue(),
            30e18,
            "Total joined value mismatch"
        );
        assertEq(
            groupAction.joinedValueByAccount(member1.userAddress),
            10e18,
            "Member1 joined value mismatch"
        );
        assertEq(
            groupAction.joinedValueByAccount(member2.userAddress),
            20e18,
            "Member2 joined value mismatch"
        );
        assertFalse(
            groupAction.isJoinedValueCalculated(),
            "Should not be calculated"
        );
    }
}
