// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupFlowTest} from "./base/BaseGroupFlowTest.sol";
import {GroupUserParams} from "./helper/TestGroupFlowHelper.sol";
import {IGroupVerify} from "../../src/interface/IGroupVerify.sol";
import {IExtension} from "@extension/src/interface/IExtension.sol";

/// @title GroupVerifyActionIdsByVerifierIntegrationTest
/// @notice Integration tests for actionIdsByVerifier, actionIdsByVerifierCount, and actionIdsByVerifierAtIndex functions
contract GroupVerifyActionIdsByVerifierIntegrationTest is BaseGroupFlowTest {
    IGroupVerify public groupVerify;

    function setUp() public override {
        super.setUp();
        groupVerify = IGroupVerify(
            h.groupActionFactory().GROUP_VERIFY_ADDRESS()
        );
    }

    /// @notice Test actionIdsByVerifier with single extension
    function test_actionIdsByVerifier_SingleExtension() public {
        // Setup: Create extension and action
        address extensionAddr = h.group_action_create(bobGroup1);
        address tokenAddress = IExtension(extensionAddr).TOKEN_ADDRESS();
        bobGroup1.groupActionAddress = extensionAddr;
        uint256 actionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = actionId;
        bobGroup1.groupActionId = actionId;

        h.vote(bobGroup1.flow);
        h.next_phase();
        h.group_activate(bobGroup1);

        // Member joins
        GroupUserParams memory m1;
        m1.flow = member1();
        m1.joinAmount = 10e18;
        m1.groupActionAddress = extensionAddr;
        h.group_join(m1, bobGroup1);

        // Verify phase
        h.next_phase();
        uint256 round = h.verifyContract().currentRound();

        // Submit scores to verify group
        uint256[] memory scores = new uint256[](1);
        scores[0] = 100;
        h.group_submit_score(bobGroup1, scores);

        // Test actionIdsByVerifier
        uint256[] memory actionIds = groupVerify.actionIdsByVerifier(
            tokenAddress,
            round,
            bobGroup1.flow.userAddress
        );
        assertEq(actionIds.length, 1, "Should have 1 actionId");
        assertEq(actionIds[0], actionId, "ActionId should match");

        // Test actionIdsByVerifierCount
        assertEq(
            groupVerify.actionIdsByVerifierCount(
                tokenAddress,
                round,
                bobGroup1.flow.userAddress
            ),
            1,
            "Count should be 1"
        );

        // Test actionIdsByVerifierAtIndex
        assertEq(
            groupVerify.actionIdsByVerifierAtIndex(
                tokenAddress,
                round,
                bobGroup1.flow.userAddress,
                0
            ),
            actionId,
            "ActionId at index 0 should match"
        );
    }

    /// @notice Test actionIdsByVerifier with multiple extensions (different actionIds)
    function test_actionIdsByVerifier_MultipleExtensions() public {
        // Setup: Create first extension and action
        address extensionAddr1 = h.group_action_create(bobGroup1);
        address tokenAddress1 = IExtension(extensionAddr1).TOKEN_ADDRESS();
        bobGroup1.groupActionAddress = extensionAddr1;
        uint256 actionId1 = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = actionId1;
        bobGroup1.groupActionId = actionId1;

        h.vote(bobGroup1.flow);
        h.next_phase();
        h.group_activate(bobGroup1);

        // Member joins group1
        GroupUserParams memory m1;
        m1.flow = member1();
        m1.joinAmount = 10e18;
        m1.groupActionAddress = extensionAddr1;
        h.group_join(m1, bobGroup1);

        // Setup: Create second extension and action with same owner
        address extensionAddr2 = h.group_action_create(bobGroup2);
        bobGroup2.groupActionAddress = extensionAddr2;
        uint256 actionId2 = h.submit_group_action(bobGroup2);
        bobGroup2.flow.actionId = actionId2;
        bobGroup2.groupActionId = actionId2;

        h.vote(bobGroup2.flow);
        h.next_phase();
        h.group_activate(bobGroup2);

        // Member joins group2
        GroupUserParams memory m2;
        m2.flow = member2();
        m2.joinAmount = 10e18;
        m2.groupActionAddress = extensionAddr2;
        h.group_join(m2, bobGroup2);

        // Verify phase
        h.next_phase();
        uint256 round = h.verifyContract().currentRound();

        // Submit scores for both groups
        uint256[] memory scores1 = new uint256[](1);
        scores1[0] = 100;
        h.group_submit_score(bobGroup1, scores1);

        uint256[] memory scores2 = new uint256[](1);
        scores2[0] = 100;
        h.group_submit_score(bobGroup2, scores2);

        // Test actionIdsByVerifier - should have both actionIds
        uint256[] memory actionIds = groupVerify.actionIdsByVerifier(
            tokenAddress1,
            round,
            bobGroup1.flow.userAddress
        );
        assertEq(actionIds.length, 2, "Should have 2 actionIds");
        assertTrue(
            (actionIds[0] == actionId1 && actionIds[1] == actionId2) ||
                (actionIds[0] == actionId2 && actionIds[1] == actionId1),
            "ActionIds should match"
        );

        // Test actionIdsByVerifierCount
        assertEq(
            groupVerify.actionIdsByVerifierCount(
                tokenAddress1,
                round,
                bobGroup1.flow.userAddress
            ),
            2,
            "Count should be 2"
        );

        // Test actionIdsByVerifierAtIndex - verify both can be accessed
        uint256 retrievedActionId1 = groupVerify.actionIdsByVerifierAtIndex(
            tokenAddress1,
            round,
            bobGroup1.flow.userAddress,
            0
        );
        uint256 retrievedActionId2 = groupVerify.actionIdsByVerifierAtIndex(
            tokenAddress1,
            round,
            bobGroup1.flow.userAddress,
            1
        );
        assertTrue(
            (retrievedActionId1 == actionId1 &&
                retrievedActionId2 == actionId2) ||
                (retrievedActionId1 == actionId2 &&
                    retrievedActionId2 == actionId1),
            "ActionIds at indices should match"
        );
    }

    /// @notice Test actionIdsByVerifier deduplication (same verifier, same extension)
    /// @dev This test verifies that when a verifier verifies multiple groups with the same extension,
    ///      the actionId is only recorded once (deduplication)
    function test_actionIdsByVerifier_Deduplication() public {
        // Setup: Create extension and action for bobGroup1
        address extensionAddr = h.group_action_create(bobGroup1);
        address tokenAddress = IExtension(extensionAddr).TOKEN_ADDRESS();
        bobGroup1.groupActionAddress = extensionAddr;
        uint256 actionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = actionId;
        bobGroup1.groupActionId = actionId;

        h.vote(bobGroup1.flow);
        h.next_phase();
        h.group_activate(bobGroup1);

        // Member joins group1
        GroupUserParams memory m1;
        m1.flow = member1();
        m1.joinAmount = 10e18;
        m1.groupActionAddress = extensionAddr;
        h.group_join(m1, bobGroup1);

        // Setup: Create bobGroup2 with same extension (same actionId)
        // Note: bobGroup2 uses the same user (bobGroup1.flow), so same verifier
        bobGroup2.groupActionAddress = extensionAddr;
        bobGroup2.flow = bobGroup1.flow;
        bobGroup2.groupActionId = actionId;
        h.group_activate(bobGroup2);

        // Member joins group2
        GroupUserParams memory m2;
        m2.flow = member2();
        m2.joinAmount = 10e18;
        m2.groupActionAddress = extensionAddr;
        h.group_join(m2, bobGroup2);

        // Verify phase
        h.next_phase();
        uint256 round = h.verifyContract().currentRound();

        // Submit scores for group1
        uint256[] memory scores1 = new uint256[](1);
        scores1[0] = 100;
        h.group_submit_score(bobGroup1, scores1);

        // Verify actionId is recorded after first verification
        uint256[] memory actionIds1 = groupVerify.actionIdsByVerifier(
            tokenAddress,
            round,
            bobGroup1.flow.userAddress
        );
        assertEq(
            actionIds1.length,
            1,
            "Should have 1 actionId after first verification"
        );
        assertEq(actionIds1[0], actionId, "ActionId should match");

        // Submit scores for group2 (same extension, same actionId)
        uint256[] memory scores2 = new uint256[](1);
        scores2[0] = 100;
        h.group_submit_score(bobGroup2, scores2);

        // Verify actionId is still only recorded once (deduplication)
        uint256[] memory actionIds2 = groupVerify.actionIdsByVerifier(
            tokenAddress,
            round,
            bobGroup1.flow.userAddress
        );
        assertEq(
            actionIds2.length,
            1,
            "Should still have 1 actionId after second verification (deduplication)"
        );
        assertEq(actionIds2[0], actionId, "ActionId should still match");

        // Verify count is still 1
        assertEq(
            groupVerify.actionIdsByVerifierCount(
                tokenAddress,
                round,
                bobGroup1.flow.userAddress
            ),
            1,
            "Count should remain 1 (deduplication)"
        );
    }

    /// @notice Test actionIdsByVerifier with multiple verifiers
    function test_actionIdsByVerifier_MultipleVerifiers() public {
        // Setup: Create extension and action for bobGroup1
        address extensionAddr1 = h.group_action_create(bobGroup1);
        address tokenAddress1 = IExtension(extensionAddr1).TOKEN_ADDRESS();
        bobGroup1.groupActionAddress = extensionAddr1;
        uint256 actionId1 = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = actionId1;
        bobGroup1.groupActionId = actionId1;

        h.vote(bobGroup1.flow);
        h.vote(aliceGroup.flow);
        h.next_phase();
        h.group_activate(bobGroup1);

        // Member joins bobGroup1
        GroupUserParams memory m1;
        m1.flow = member1();
        m1.joinAmount = 10e18;
        m1.groupActionAddress = extensionAddr1;
        h.group_join(m1, bobGroup1);

        // Setup: Create extension and action for aliceGroup
        address extensionAddr2 = h.group_action_create(aliceGroup);
        address tokenAddress2 = IExtension(extensionAddr2).TOKEN_ADDRESS();
        aliceGroup.groupActionAddress = extensionAddr2;
        uint256 actionId2 = h.submit_group_action(aliceGroup);
        aliceGroup.flow.actionId = actionId2;
        aliceGroup.groupActionId = actionId2;

        h.vote(aliceGroup.flow);
        h.next_phase();
        h.group_activate(aliceGroup);

        // Member joins aliceGroup
        GroupUserParams memory m2;
        m2.flow = member2();
        m2.joinAmount = 10e18;
        m2.groupActionAddress = extensionAddr2;
        h.group_join(m2, aliceGroup);

        // Verify phase
        h.next_phase();
        uint256 round = h.verifyContract().currentRound();

        // Submit scores for both groups
        uint256[] memory scores1 = new uint256[](1);
        scores1[0] = 100;
        h.group_submit_score(bobGroup1, scores1);

        uint256[] memory scores2 = new uint256[](1);
        scores2[0] = 100;
        h.group_submit_score(aliceGroup, scores2);

        // Test bobGroup1's verifier
        uint256[] memory bobActionIds = groupVerify.actionIdsByVerifier(
            tokenAddress1,
            round,
            bobGroup1.flow.userAddress
        );
        assertEq(bobActionIds.length, 1, "Bob should have 1 actionId");
        assertEq(bobActionIds[0], actionId1, "Bob's actionId should match");

        // Test aliceGroup's verifier
        uint256[] memory aliceActionIds = groupVerify.actionIdsByVerifier(
            tokenAddress2,
            round,
            aliceGroup.flow.userAddress
        );
        assertEq(aliceActionIds.length, 1, "Alice should have 1 actionId");
        assertEq(aliceActionIds[0], actionId2, "Alice's actionId should match");
    }

    /// @notice Test actionIdsByVerifier consistency between functions
    function test_actionIdsByVerifier_Consistency() public {
        // Setup: Create extension and action
        address extensionAddr = h.group_action_create(bobGroup1);
        address tokenAddress = IExtension(extensionAddr).TOKEN_ADDRESS();
        bobGroup1.groupActionAddress = extensionAddr;
        uint256 actionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = actionId;
        bobGroup1.groupActionId = actionId;

        h.vote(bobGroup1.flow);
        h.next_phase();
        h.group_activate(bobGroup1);

        // Member joins
        GroupUserParams memory m1;
        m1.flow = member1();
        m1.joinAmount = 10e18;
        m1.groupActionAddress = extensionAddr;
        h.group_join(m1, bobGroup1);

        // Verify phase
        h.next_phase();
        uint256 round = h.verifyContract().currentRound();

        // Submit scores
        uint256[] memory scores = new uint256[](1);
        scores[0] = 100;
        h.group_submit_score(bobGroup1, scores);

        // Test consistency between actionIdsByVerifier and actionIdsByVerifierCount
        uint256[] memory actionIds = groupVerify.actionIdsByVerifier(
            tokenAddress,
            round,
            bobGroup1.flow.userAddress
        );
        uint256 count = groupVerify.actionIdsByVerifierCount(
            tokenAddress,
            round,
            bobGroup1.flow.userAddress
        );

        assertEq(actionIds.length, count, "Array length should match count");

        // Test consistency with actionIdsByVerifierAtIndex
        for (uint256 i = 0; i < count; i++) {
            uint256 actionIdAtIndex = groupVerify.actionIdsByVerifierAtIndex(
                tokenAddress,
                round,
                bobGroup1.flow.userAddress,
                i
            );
            assertEq(
                actionIdAtIndex,
                actionIds[i],
                "ActionId at index should match array element"
            );
        }
    }

    /// @notice Test actionIdsByVerifier returns empty array for non-verifier
    function test_actionIdsByVerifier_NonVerifier() public {
        // Setup: Create extension and action
        address extensionAddr = h.group_action_create(bobGroup1);
        address tokenAddress = IExtension(extensionAddr).TOKEN_ADDRESS();
        bobGroup1.groupActionAddress = extensionAddr;
        uint256 actionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = actionId;
        bobGroup1.groupActionId = actionId;

        h.vote(bobGroup1.flow);
        h.next_phase();
        h.group_activate(bobGroup1);

        // Member joins
        GroupUserParams memory m1;
        m1.flow = member1();
        m1.joinAmount = 10e18;
        m1.groupActionAddress = extensionAddr;
        h.group_join(m1, bobGroup1);

        // Verify phase
        h.next_phase();
        uint256 round = h.verifyContract().currentRound();

        // Submit scores
        uint256[] memory scores = new uint256[](1);
        scores[0] = 100;
        h.group_submit_score(bobGroup1, scores);

        // Test non-verifier (aliceGroup hasn't verified anything)
        uint256[] memory actionIds = groupVerify.actionIdsByVerifier(
            tokenAddress,
            round,
            aliceGroup.flow.userAddress
        );
        assertEq(actionIds.length, 0, "Non-verifier should have empty array");

        assertEq(
            groupVerify.actionIdsByVerifierCount(
                tokenAddress,
                round,
                aliceGroup.flow.userAddress
            ),
            0,
            "Non-verifier count should be 0"
        );
    }

    /// @notice Test actionIdsByVerifier with unverified group
    function test_actionIdsByVerifier_UnverifiedGroup() public {
        // Setup: Create extension and action
        address extensionAddr = h.group_action_create(bobGroup1);
        address tokenAddress = IExtension(extensionAddr).TOKEN_ADDRESS();
        bobGroup1.groupActionAddress = extensionAddr;
        uint256 actionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = actionId;
        bobGroup1.groupActionId = actionId;

        h.vote(bobGroup1.flow);
        h.next_phase();
        h.group_activate(bobGroup1);

        // Member joins
        GroupUserParams memory m1;
        m1.flow = member1();
        m1.joinAmount = 10e18;
        m1.groupActionAddress = extensionAddr;
        h.group_join(m1, bobGroup1);

        // Verify phase (but don't submit scores)
        h.next_phase();
        uint256 round = h.verifyContract().currentRound();

        // Test actionIdsByVerifier before verification
        uint256[] memory actionIds = groupVerify.actionIdsByVerifier(
            tokenAddress,
            round,
            bobGroup1.flow.userAddress
        );
        assertEq(
            actionIds.length,
            0,
            "Should have empty array before verification"
        );

        assertEq(
            groupVerify.actionIdsByVerifierCount(
                tokenAddress,
                round,
                bobGroup1.flow.userAddress
            ),
            0,
            "Count should be 0 before verification"
        );
    }
}
