// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupFlowTest} from "./base/BaseGroupFlowTest.sol";
import {GroupUserParams} from "./helper/TestGroupFlowHelper.sol";
import {
    LOVE20ExtensionGroupAction
} from "../../src/LOVE20ExtensionGroupAction.sol";
import {IGroupJoin} from "../../src/interface/IGroupJoin.sol";
import {IGroupVerify} from "../../src/interface/IGroupVerify.sol";

/// @title GroupBasicOpsTest
/// @notice Integration tests for basic group operations: deactivation, exit/rejoin, etc.
contract GroupBasicOpsTest is BaseGroupFlowTest {
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
        m1.flow = member1();
        m1.joinAmount = 10e18;
        m1.groupActionAddress = bobGroup1.groupActionAddress;
        h.group_join(m1, bobGroup1);

        // 3. Round 1: Submit scores
        h.next_phase();
        uint256 round1 = h.verifyContract().currentRound();

        uint256[] memory scores1 = new uint256[](1);
        scores1[0] = 80;
        h.group_submit_score(bobGroup1, scores1);

        // Verify round 1 score
        IGroupVerify groupVerify = IGroupVerify(
            h.groupActionFactory().GROUP_VERIFY_ADDRESS()
        );
        assertEq(
            groupVerify.originScoreByAccount(
                bobGroup1.flow.tokenAddress,
                bobGroup1.groupActionId,
                round1,
                member1().userAddress
            ),
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
            groupVerify.originScoreByAccount(
                bobGroup1.flow.tokenAddress,
                bobGroup1.groupActionId,
                round1,
                member1().userAddress
            ),
            80,
            "Round 1 score should remain 80"
        );
        assertEq(
            groupVerify.originScoreByAccount(
                bobGroup1.flow.tokenAddress,
                bobGroup1.groupActionId,
                round2,
                member1().userAddress
            ),
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
        m1.flow = member1();
        m1.joinAmount = 10e18;
        m1.groupActionAddress = bobGroup1.groupActionAddress;
        h.group_join(m1, bobGroup1);

        // Verify joined
        IGroupJoin groupJoin = IGroupJoin(
            h.groupActionFactory().GROUP_JOIN_ADDRESS()
        );
        (uint256 joinedRound, , ) = groupJoin.joinInfo(
            bobGroup1.flow.tokenAddress,
            bobGroup1.groupActionId,
            member1().userAddress
        );
        assertTrue(joinedRound > 0, "Should be joined");

        // 3. Member exits
        h.group_exit(m1, bobGroup1);

        // Verify exited
        (joinedRound, , ) = groupJoin.joinInfo(
            bobGroup1.flow.tokenAddress,
            bobGroup1.groupActionId,
            member1().userAddress
        );
        assertEq(joinedRound, 0, "Should not be joined after exit");

        // 4. Member rejoins with different amount
        m1.joinAmount = 15e18;
        h.group_join(m1, bobGroup1);

        // Verify rejoined
        uint256 amount;
        (joinedRound, amount, ) = groupJoin.joinInfo(
            bobGroup1.flow.tokenAddress,
            bobGroup1.groupActionId,
            member1().userAddress
        );
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
        m1.flow = member1();
        m1.joinAmount = 10e18;
        m1.groupActionAddress = bobGroup1.groupActionAddress;
        h.group_join(m1, bobGroup1);

        GroupUserParams memory m2;
        m2.flow = member2();
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
            groupAction.joinedValueByAccount(member1().userAddress),
            10e18,
            "Member1 joined value mismatch"
        );
        assertEq(
            groupAction.joinedValueByAccount(member2().userAddress),
            20e18,
            "Member2 joined value mismatch"
        );
        assertFalse(
            groupAction.isJoinedValueCalculated(),
            "Should not be calculated when joinToken == tokenAddress"
        );
    }

    // ============ Extension Activation Tracking Tests ============

    /// @notice Test actionIdsByGroupId with single extension
    function test_actionIdsByGroupId_SingleExtension() public {
        // 1. Setup group action
        address extensionAddr = h.group_action_create(bobGroup1);
        bobGroup1.groupActionAddress = extensionAddr;
        uint256 actionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = actionId;
        bobGroup1.groupActionId = actionId;

        h.vote(bobGroup1.flow);
        h.next_phase();
        h.group_activate(bobGroup1);

        // 2. Verify actionId is tracked for this groupId
        uint256[] memory actionIds_ = h.getGroupManager().actionIdsByGroupId(
            address(h.groupActionFactory()),
            h.firstTokenAddress(),
            bobGroup1.groupId
        );
        assertEq(actionIds_.length, 1, "Should have 1 actionId");
        assertEq(actionIds_[0], actionId, "ActionId should match");

        // 3. Verify count
        assertEq(
            h.getGroupManager().actionIdsByGroupIdCount(
                address(h.groupActionFactory()),
                h.firstTokenAddress(),
                bobGroup1.groupId
            ),
            1,
            "Count should be 1"
        );

        // 4. Verify at index
        assertEq(
            h.getGroupManager().actionIdsByGroupIdAtIndex(
                address(h.groupActionFactory()),
                h.firstTokenAddress(),
                bobGroup1.groupId,
                0
            ),
            actionId,
            "ActionId at index 0 should match"
        );
    }

    /// @notice Test actionIdsByGroupId with multiple extensions
    function test_actionIdsByGroupId_MultipleExtensions() public {
        // 1. Setup first group action
        address extensionAddr1 = h.group_action_create(bobGroup1);
        bobGroup1.groupActionAddress = extensionAddr1;
        uint256 actionId1 = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = actionId1;
        bobGroup1.groupActionId = actionId1;

        h.vote(bobGroup1.flow);
        h.next_phase();
        h.group_activate(bobGroup1);

        // 2. Setup second group action (different actionId) activating same groupId
        // Create a new action but activate it with bobGroup1's groupId
        address extensionAddr2 = h.group_action_create(bobGroup2);
        bobGroup2.groupActionAddress = extensionAddr2;
        uint256 actionId2 = h.submit_group_action(bobGroup2);
        bobGroup2.flow.actionId = actionId2;
        bobGroup2.groupActionId = actionId2;

        h.vote(bobGroup2.flow);
        h.next_phase();
        // Activate with bobGroup1's groupId to test multiple extensions for same groupId
        uint256 sharedGroupId = bobGroup1.groupId;
        bobGroup2.groupId = sharedGroupId;
        h.group_activate(bobGroup2);

        // 3. Verify both actionIds are tracked for this groupId
        uint256[] memory actionIds_ = h.getGroupManager().actionIdsByGroupId(
            address(h.groupActionFactory()),
            h.firstTokenAddress(),
            sharedGroupId
        );
        assertEq(actionIds_.length, 2, "Should have 2 actionIds");
        assertTrue(
            (actionIds_[0] == actionId1 && actionIds_[1] == actionId2) ||
                (actionIds_[0] == actionId2 && actionIds_[1] == actionId1),
            "Both actionIds should be present"
        );
    }

    /// @notice Test actionIdsByGroupId after deactivate
    function test_actionIdsByGroupId_AfterDeactivate() public {
        // 1. Setup and activate
        address extensionAddr = h.group_action_create(bobGroup1);
        bobGroup1.groupActionAddress = extensionAddr;
        uint256 actionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = actionId;
        bobGroup1.groupActionId = actionId;

        h.vote(bobGroup1.flow);
        h.next_phase();
        h.group_activate(bobGroup1);

        // 2. Verify actionId is tracked
        assertEq(
            h.getGroupManager().actionIdsByGroupIdCount(
                address(h.groupActionFactory()),
                h.firstTokenAddress(),
                bobGroup1.groupId
            ),
            1,
            "Should have 1 actionId before deactivate"
        );

        // 3. Deactivate
        h.next_phase();
        h.group_deactivate(bobGroup1);

        // 4. Verify actionId is removed
        assertEq(
            h.getGroupManager().actionIdsByGroupIdCount(
                address(h.groupActionFactory()),
                h.firstTokenAddress(),
                bobGroup1.groupId
            ),
            0,
            "Should have 0 actionIds after deactivate"
        );
        uint256[] memory actionIds_ = h.getGroupManager().actionIdsByGroupId(
            address(h.groupActionFactory()),
            h.firstTokenAddress(),
            bobGroup1.groupId
        );
        assertEq(actionIds_.length, 0, "ActionIds array should be empty");
    }

    /// @notice Test actionIds with single extension
    function test_actionIds_SingleExtension() public {
        // 1. Setup and activate
        address extensionAddr = h.group_action_create(bobGroup1);
        bobGroup1.groupActionAddress = extensionAddr;
        uint256 actionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = actionId;
        bobGroup1.groupActionId = actionId;

        h.vote(bobGroup1.flow);
        h.next_phase();
        h.group_activate(bobGroup1);

        // 2. Verify actionId is tracked
        uint256[] memory actionIds_ = h.getGroupManager().actionIds(
            address(h.groupActionFactory()),
            h.firstTokenAddress()
        );
        assertEq(actionIds_.length, 1, "Should have 1 actionId");
        assertEq(actionIds_[0], actionId, "ActionId should match");

        // 3. Verify count
        assertEq(
            h.getGroupManager().actionIdsCount(
                address(h.groupActionFactory()),
                h.firstTokenAddress()
            ),
            1,
            "Count should be 1"
        );

        // 4. Verify at index
        assertEq(
            h.getGroupManager().actionIdsAtIndex(
                address(h.groupActionFactory()),
                h.firstTokenAddress(),
                0
            ),
            actionId,
            "ActionId at index 0 should match"
        );
    }

    /// @notice Test actionIds with multiple extensions
    function test_actionIds_MultipleExtensions() public {
        // 1. Setup and activate first extension
        address extensionAddr1 = h.group_action_create(bobGroup1);
        bobGroup1.groupActionAddress = extensionAddr1;
        uint256 actionId1 = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = actionId1;
        bobGroup1.groupActionId = actionId1;

        h.vote(bobGroup1.flow);
        h.next_phase();
        h.group_activate(bobGroup1);

        // 2. Setup and activate second extension
        address extensionAddr2 = h.group_action_create(bobGroup2);
        bobGroup2.groupActionAddress = extensionAddr2;
        uint256 actionId2 = h.submit_group_action(bobGroup2);
        bobGroup2.flow.actionId = actionId2;
        bobGroup2.groupActionId = actionId2;

        h.vote(bobGroup2.flow);
        h.next_phase();
        h.group_activate(bobGroup2);

        // 3. Verify both actionIds are tracked
        uint256[] memory actionIds_ = h.getGroupManager().actionIds(
            address(h.groupActionFactory()),
            h.firstTokenAddress()
        );
        assertEq(actionIds_.length, 2, "Should have 2 actionIds");
        assertTrue(
            (actionIds_[0] == actionId1 && actionIds_[1] == actionId2) ||
                (actionIds_[0] == actionId2 && actionIds_[1] == actionId1),
            "Both actionIds should be present"
        );
    }

    /// @notice Test actionIds after all deactivated
    function test_actionIds_AfterAllDeactivated() public {
        // 1. Setup and activate
        address extensionAddr = h.group_action_create(bobGroup1);
        bobGroup1.groupActionAddress = extensionAddr;
        uint256 actionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = actionId;
        bobGroup1.groupActionId = actionId;

        h.vote(bobGroup1.flow);
        h.next_phase();
        h.group_activate(bobGroup1);

        // 2. Verify actionId is tracked
        assertEq(
            h.getGroupManager().actionIdsCount(
                address(h.groupActionFactory()),
                h.firstTokenAddress()
            ),
            1,
            "Should have 1 actionId before deactivate"
        );

        // 3. Deactivate
        h.next_phase();
        h.group_deactivate(bobGroup1);

        // 4. Verify actionId is removed
        assertEq(
            h.getGroupManager().actionIdsCount(
                address(h.groupActionFactory()),
                h.firstTokenAddress()
            ),
            0,
            "Should have 0 actionIds after deactivate"
        );
        uint256[] memory actionIds_ = h.getGroupManager().actionIds(
            address(h.groupActionFactory()),
            h.firstTokenAddress()
        );
        assertEq(actionIds_.length, 0, "ActionIds array should be empty");
    }

    /// @notice Test complex scenario with multiple extensions and groupIds
    function test_ExtensionTracking_ComplexScenario() public {
        // 1. Setup first extension with group1
        address extensionAddr1 = h.group_action_create(bobGroup1);
        bobGroup1.groupActionAddress = extensionAddr1;
        uint256 actionId1 = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = actionId1;
        bobGroup1.groupActionId = actionId1;

        h.vote(bobGroup1.flow);
        h.next_phase();
        h.group_activate(bobGroup1);

        // 2. Setup second extension with group2
        address extensionAddr2 = h.group_action_create(bobGroup2);
        bobGroup2.groupActionAddress = extensionAddr2;
        uint256 actionId2 = h.submit_group_action(bobGroup2);
        bobGroup2.flow.actionId = actionId2;
        bobGroup2.groupActionId = actionId2;

        h.vote(bobGroup2.flow);
        h.next_phase();
        h.group_activate(bobGroup2);

        // 3. Verify both actionIds are tracked globally
        assertEq(
            h.getGroupManager().actionIdsCount(
                address(h.groupActionFactory()),
                h.firstTokenAddress()
            ),
            2,
            "Should have 2 actionIds globally"
        );

        // 4. Verify each groupId has its actionId
        assertEq(
            h.getGroupManager().actionIdsByGroupIdCount(
                address(h.groupActionFactory()),
                h.firstTokenAddress(),
                bobGroup1.groupId
            ),
            1,
            "Group1 should have 1 actionId"
        );
        assertEq(
            h.getGroupManager().actionIdsByGroupIdCount(
                address(h.groupActionFactory()),
                h.firstTokenAddress(),
                bobGroup2.groupId
            ),
            1,
            "Group2 should have 1 actionId"
        );

        // 5. Deactivate group1
        h.next_phase();
        h.group_deactivate(bobGroup1);

        // 6. Verify group1 has no actionIds, but actionId1 still tracked globally (if it has other groups)
        assertEq(
            h.getGroupManager().actionIdsByGroupIdCount(
                address(h.groupActionFactory()),
                h.firstTokenAddress(),
                bobGroup1.groupId
            ),
            0,
            "Group1 should have 0 actionIds after deactivate"
        );
        // ActionId1 should be removed from global set since it has no more active groups
        assertEq(
            h.getGroupManager().actionIdsCount(
                address(h.groupActionFactory()),
                h.firstTokenAddress()
            ),
            1,
            "Should have 1 actionId globally after group1 deactivated"
        );

        // 7. Deactivate group2
        h.next_phase();
        h.group_deactivate(bobGroup2);

        // 8. Verify all actionIds removed
        assertEq(
            h.getGroupManager().actionIdsCount(
                address(h.groupActionFactory()),
                h.firstTokenAddress()
            ),
            0,
            "Should have 0 actionIds globally after all deactivated"
        );
        assertEq(
            h.getGroupManager().actionIdsByGroupIdCount(
                address(h.groupActionFactory()),
                h.firstTokenAddress(),
                bobGroup2.groupId
            ),
            0,
            "Group2 should have 0 actionIds after deactivate"
        );
    }
}
