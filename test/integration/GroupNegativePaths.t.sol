// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupFlowTest} from "./base/BaseGroupFlowTest.sol";
import {GroupUserParams} from "./helper/TestGroupFlowHelper.sol";
import {IGroupVerify, IGroupVerifyErrors} from "../../src/interface/IGroupVerify.sol";
import {IGroupJoin, IGroupJoinErrors} from "../../src/interface/IGroupJoin.sol";
import {IGroupManager, IGroupManagerErrors} from "../../src/interface/IGroupManager.sol";
import {IRewardErrors} from "@extension/src/interface/IReward.sol";

/// @title GroupNegativePathsTest
/// @notice Integration tests for negative paths: double claims, unauthorized access, and invalid operations
contract GroupNegativePathsTest is BaseGroupFlowTest {
    /// @dev Common setup: create group action, submit, vote, advance phase, activate
    function _setupAndActivateGroupAction(
        GroupUserParams storage gup
    ) internal returns (address extensionAddr, uint256 actionId) {
        extensionAddr = h.group_action_create(gup);
        gup.groupActionAddress = extensionAddr;
        actionId = h.submit_group_action(gup);
        gup.flow.actionId = actionId;
        gup.groupActionId = actionId;

        h.vote(gup.flow);
        h.next_phase();
        h.group_activate(gup);
    }

    // ============ Test 1: Double Claim Reward Reverts ============

    /// @notice After claiming action reward once, claiming again for the same round should revert
    function test_doubleClaimReward_Reverts() public {
        // 1. Setup: create extension, vote, activate
        (address extensionAddr, uint256 actionId) = _setupAndActivateGroupAction(bobGroup1);

        // 2. Member joins
        GroupUserParams memory m1;
        m1.flow = member1();
        m1.joinAmount = 10e18;
        m1.groupActionAddress = extensionAddr;
        h.group_join(m1, bobGroup1);

        // 3. Advance to verify phase and submit scores
        h.next_phase();
        uint256 verifyRound = h.verifyContract().currentRound();

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;
        h.group_submit_score(bobGroup1, scores);

        // 4. Core verify the extension so rewards are generated
        h.core_verify_extension(
            bobGroup1.flow,
            h.firstTokenAddress(),
            actionId,
            extensionAddr
        );

        // 5. Advance past the verify round so the round is claimable
        h.next_phases(3);

        // 6. First claim should succeed
        h.group_action_claim_reward(m1, bobGroup1, verifyRound);

        // 7. Second claim for the same round should revert with AlreadyClaimed
        vm.expectRevert(IRewardErrors.AlreadyClaimed.selector);
        h.group_action_claim_reward(m1, bobGroup1, verifyRound);
    }

    // ============ Test 2: Non-Owner Submit Scores Reverts ============

    /// @notice A non-owner/non-delegate user cannot submit scores for a group
    function test_nonOwnerSubmitScores_Reverts() public {
        // 1. Setup: create extension, vote, activate
        (address extensionAddr, ) = _setupAndActivateGroupAction(bobGroup1);

        // 2. Member joins
        GroupUserParams memory m1;
        m1.flow = member1();
        m1.joinAmount = 10e18;
        m1.groupActionAddress = extensionAddr;
        h.group_join(m1, bobGroup1);

        // 3. Advance to verify phase
        h.next_phase();

        // 4. Random user (member2) tries to submit scores - should revert with NotVerifier
        address randomUser = member2().userAddress;
        IGroupVerify groupVerify = IGroupVerify(h.groupActionFactory().GROUP_VERIFY_ADDRESS());

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.expectRevert(IGroupVerifyErrors.NotVerifier.selector);
        vm.prank(randomUser, randomUser);
        groupVerify.submitOriginScores(extensionAddr, bobGroup1.groupId, 0, scores);
    }

    // ============ Test 3: Operations After Deactivation Reverts ============

    /// @notice Joining a deactivated group should revert
    function test_operationsAfterDeactivation_Reverts() public {
        // 1. Setup: create extension, vote, activate
        (address extensionAddr, ) = _setupAndActivateGroupAction(bobGroup1);

        // 2. Advance phase so we can deactivate (cannot deactivate in activated round)
        h.next_phase();
        h.group_deactivate(bobGroup1);

        // 3. Try to join the deactivated group - should revert with CannotJoinInactiveGroup
        address memberAddr = member1().userAddress;
        uint256 joinAmount = 10e18;

        IGroupJoin groupJoin = IGroupJoin(h.groupActionFactory().GROUP_JOIN_ADDRESS());

        vm.expectRevert(IGroupJoinErrors.CannotJoinInactiveGroup.selector);
        vm.prank(memberAddr, memberAddr);
        groupJoin.join(extensionAddr, bobGroup1.groupId, joinAmount, new string[](0));
    }

    // ============ Test 4: Non-Owner Deactivate Group Reverts ============

    /// @notice A non-owner cannot deactivate another user's group
    function test_nonOwnerDeactivateGroup_Reverts() public {
        // 1. Setup: create extension, vote, activate bob's group
        (address extensionAddr, ) = _setupAndActivateGroupAction(bobGroup1);

        // 2. Advance phase so deactivation is allowed (past activation round)
        h.next_phase();

        // 3. Cache GroupManager ref before vm.expectRevert (getGroupManager is an external call)
        IGroupManager groupManager = IGroupManager(address(h.getGroupManager()));

        // 4. Alice tries to deactivate bob's group - should revert with OnlyGroupOwner
        vm.expectRevert(IGroupManagerErrors.OnlyGroupOwner.selector);
        vm.prank(aliceGroup.flow.userAddress, aliceGroup.flow.userAddress);
        groupManager.deactivateGroup(extensionAddr, bobGroup1.groupId);
    }
}
