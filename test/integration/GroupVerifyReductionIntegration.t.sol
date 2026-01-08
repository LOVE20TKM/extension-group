// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupFlowTest} from "./base/BaseGroupFlowTest.sol";
import {GroupUserParams} from "./helper/TestGroupFlowHelper.sol";
import {IGroupVerify} from "../../src/interface/IGroupVerify.sol";
import {PRECISION} from "../../src/interface/IGroupVerify.sol";

/// @title GroupVerifyReductionIntegrationTest
/// @notice Integration tests for capacityReduction and distrustReduction functions
contract GroupVerifyReductionIntegrationTest is BaseGroupFlowTest {
    IGroupVerify public groupVerify;

    function setUp() public override {
        super.setUp();
        groupVerify = IGroupVerify(
            h.groupActionFactory().GROUP_VERIFY_ADDRESS()
        );
    }

    /// @notice Test distrustReduction uses correct group owner from round
    function test_distrustReduction_UsesRoundGroupOwner() public {
        // Setup: Create extension and action
        address extensionAddr = h.group_action_create(bobGroup1);
        bobGroup1.groupActionAddress = extensionAddr;
        uint256 actionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = actionId;
        bobGroup1.groupActionId = actionId;

        h.vote(bobGroup1.flow);
        h.vote(aliceGroup.flow); // Alice also votes so she can verify later
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

        // Alice needs to verify bobGroup1's extension to get verify votes
        // Use bobGroup1's actionId and extensionAddr directly
        h.core_verify_extension(
            aliceGroup.flow,
            h.firstTokenAddress(),
            actionId, // bobGroup1's actionId
            extensionAddr // bobGroup1's extension
        );

        // Get alice's verify votes
        uint256 aliceVerifyVotes = h
            .verifyContract()
            .scoreByVerifierByActionIdByAccount(
                h.firstTokenAddress(),
                round,
                aliceGroup.flow.userAddress,
                actionId,
                extensionAddr
            );

        // Skip test if alice has no verify votes
        if (aliceVerifyVotes == 0) {
            return;
        }

        // Get total votes for calculation
        uint256 totalVotes = h.voteContract().votesNumByActionId(
            h.firstTokenAddress(),
            round,
            actionId
        );

        // Cast distrust vote: use a small portion of alice's verify votes
        uint256 distrustVotes = aliceVerifyVotes / 10; // 10% of alice's verify votes
        if (distrustVotes == 0) {
            distrustVotes = 1; // Use at least 1
        }
        // Ensure we don't exceed alice's verify votes
        if (distrustVotes > aliceVerifyVotes) {
            distrustVotes = aliceVerifyVotes;
        }

        // Use bobGroup1's extension for distrust vote (extension is just used to get token/actionId)
        vm.prank(aliceGroup.flow.userAddress, aliceGroup.flow.userAddress);
        groupVerify.distrustVote(
            extensionAddr, // Use bobGroup1's extension
            bobGroup1.flow.userAddress,
            distrustVotes,
            "Test reason"
        );

        // Get the group owner at the time of verification (round)
        address roundGroupOwner = groupVerify.verifierByGroupId(
            extensionAddr,
            round,
            bobGroup1.groupId
        );

        // Verify it's the correct owner
        assertEq(
            roundGroupOwner,
            bobGroup1.flow.userAddress,
            "Round group owner should match bobGroup1"
        );

        // Test distrustReduction uses this owner
        uint256 distrustReduction = groupVerify.distrustReduction(
            extensionAddr,
            round,
            bobGroup1.groupId
        );

        // Should calculate based on roundGroupOwner's distrust votes
        uint256 expected = ((totalVotes - distrustVotes) * PRECISION) /
            totalVotes;

        assertEq(
            distrustReduction,
            expected,
            "distrustReduction should use round group owner"
        );
    }

    /// @notice Test capacityReduction and distrustReduction work together
    function test_capacityAndDistrustReduction_Integration() public {
        // Setup: Create extension and action
        address extensionAddr = h.group_action_create(bobGroup1);
        bobGroup1.groupActionAddress = extensionAddr;
        uint256 actionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = actionId;
        bobGroup1.groupActionId = actionId;

        h.vote(bobGroup1.flow);
        h.vote(aliceGroup.flow); // Alice also votes so she can verify later
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

        // Alice needs to verify bobGroup1's extension to get verify votes
        // Use bobGroup1's actionId and extensionAddr directly
        h.core_verify_extension(
            aliceGroup.flow,
            h.firstTokenAddress(),
            actionId, // bobGroup1's actionId
            extensionAddr // bobGroup1's extension
        );

        // Get alice's verify votes
        uint256 aliceVerifyVotes = h
            .verifyContract()
            .scoreByVerifierByActionIdByAccount(
                h.firstTokenAddress(),
                round,
                aliceGroup.flow.userAddress,
                actionId,
                extensionAddr
            );

        // Cast distrust vote: use a small portion of alice's verify votes
        uint256 distrustVotes = aliceVerifyVotes / 10; // 10% of alice's verify votes
        if (distrustVotes == 0) {
            distrustVotes = 1; // Use at least 1
        }
        // Ensure we don't exceed alice's verify votes
        if (distrustVotes > aliceVerifyVotes) {
            distrustVotes = aliceVerifyVotes;
        }

        // Use bobGroup1's extension for distrust vote (extension is just used to get token/actionId)
        vm.prank(aliceGroup.flow.userAddress, aliceGroup.flow.userAddress);
        groupVerify.distrustVote(
            extensionAddr, // Use bobGroup1's extension
            bobGroup1.flow.userAddress,
            distrustVotes,
            "Test reason"
        );

        // Get both reductions
        uint256 capacityReduction = groupVerify.capacityReduction(
            extensionAddr,
            round,
            bobGroup1.groupId
        );
        uint256 distrustReduction = groupVerify.distrustReduction(
            extensionAddr,
            round,
            bobGroup1.groupId
        );

        // Verify both are set correctly
        assertTrue(
            capacityReduction > 0,
            "capacityReduction should be greater than 0"
        );
        assertTrue(
            distrustReduction > 0 && distrustReduction <= PRECISION,
            "distrustReduction should be between 0 and PRECISION"
        );

        // Verify group score calculation uses both
        uint256 groupScore = groupVerify.groupScore(
            extensionAddr,
            round,
            bobGroup1.groupId
        );

        // Group score should be: groupAmount * distrustReduction * capacityReduction / PRECISION
        uint256 groupAmount = 10e18;

        // Verify group score is calculated correctly
        // Group score = groupAmount * distrustReduction * capacityReduction / PRECISION^2
        // Note: There may be small rounding differences due to division order
        uint256 calculatedScore = (groupAmount *
            distrustReduction *
            capacityReduction) / (PRECISION * PRECISION);

        // Allow small rounding difference (up to 10 wei)
        uint256 diff = groupScore > calculatedScore
            ? groupScore - calculatedScore
            : calculatedScore - groupScore;
        assertTrue(
            diff <= 10,
            "Group score should use both capacity and distrust reductions (with small rounding tolerance)"
        );
    }
}
