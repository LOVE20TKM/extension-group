// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseGroupFlowTest} from "./base/BaseGroupFlowTest.sol";
import {GroupUserParams} from "./helper/TestGroupFlowHelper.sol";
import {ExtensionGroupAction} from "../../src/ExtensionGroupAction.sol";
import {ExtensionGroupService} from "../../src/ExtensionGroupService.sol";
import {IGroupService} from "../../src/interface/IGroupService.sol";

/// @title GroupServiceFlowTest
/// @notice Integration test for complete group service flow with reward claiming
contract GroupServiceFlowTest is BaseGroupFlowTest {
    /// @notice Test full group service flow with reward claiming
    function test_full_group_service_flow() public {
        // === Vote Phase: Both actions need different submitters ===
        // 1. Bob creates and submits group action
        bobGroup1.groupActionAddress = h.group_action_create(bobGroup1);
        bobGroup1.groupActionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = bobGroup1.groupActionId;
        h.vote(bobGroup1.flow);

        // 2. Alice creates and submits group service (same token)
        aliceGroup.groupServiceAddress = h.group_service_create(
            aliceGroup,
            h.firstTokenAddress()
        );
        aliceGroup.groupServiceActionId = h.submit_group_service_action(
            aliceGroup
        );
        aliceGroup.flow.actionId = aliceGroup.groupServiceActionId;
        h.vote(aliceGroup.flow);

        // === Join Phase: Activate and join ===
        h.next_phase();
        h.group_activate(bobGroup1);

        // Member joins the group
        GroupUserParams memory m1;
        m1.flow = member1();
        m1.joinAmount = 10e18;
        m1.groupActionAddress = bobGroup1.groupActionAddress;
        h.group_join(m1, bobGroup1);

        // Bob joins aliceGroup's service (bobGroup1 has active group)
        bobGroup1.groupServiceAddress = aliceGroup.groupServiceAddress;
        bobGroup1.groupServiceActionId = aliceGroup.groupServiceActionId;
        h.group_service_join(bobGroup1);

        // Verify joinedAmount after join
        ExtensionGroupService gs = ExtensionGroupService(
            aliceGroup.groupServiceAddress
        );
        uint256 joinedVal = gs.joinedAmount();
        uint256 expectedJoinedVal = h.getGroupManager().staked(
            bobGroup1.groupActionAddress
        );
        assertEq(
            joinedVal,
            expectedJoinedVal,
            "joinedAmount should match totalStaked from groupManager"
        );

        // Verify joinedAmountByAccount for Bob
        uint256 bobJoinedVal = gs.joinedAmountByAccount(
            bobGroup1.flow.userAddress
        );
        uint256 expectedBobJoinedVal = h.getGroupManager().stakedByOwner(
            bobGroup1.groupActionAddress,
            bobGroup1.flow.userAddress
        );
        assertEq(
            bobJoinedVal,
            expectedBobJoinedVal,
            "joinedAmountByAccount for Bob should match"
        );

        // Bob sets recipients for his service reward distribution
        _setServiceRecipients();

        // === Verify Phase ===
        h.next_phase();
        uint256 verifyRound = h.verifyContract().currentRound();

        // Submit group scores
        _submitGroupScoreForService();

        // Core verify for group action (bobGroup1 verifies)
        h.core_verify_extension(bobGroup1, bobGroup1.groupActionAddress);

        // Alice verifies service extension
        _coreVerifyService();

        // === Claim Phase ===
        h.next_phase();

        // Group service provider (bobGroup1) claims from aliceGroup's service
        _verifyServiceRewardClaim(verifyRound);

        // Group action participant (m1) claims
        _verifyActionRewardClaim(m1, verifyRound);
    }

    function _setServiceRecipients() internal {
        address[] memory recipients = new address[](2);
        recipients[0] = member2().userAddress;
        recipients[1] = member3().userAddress;
        uint256[] memory ratios = new uint256[](2);
        ratios[0] = 5e17; // 50%
        ratios[1] = 3e17; // 30%
        bobGroup1.recipients = recipients;
        bobGroup1.ratios = ratios;
        h.group_service_set_recipients(bobGroup1);
    }

    function _submitGroupScoreForService() internal {
        uint256[] memory scores = new uint256[](1);
        scores[0] = 100;
        h.group_submit_score(bobGroup1, scores);
    }

    function _coreVerifyService() internal {
        h.core_verify_extension(
            aliceGroup.flow,
            h.firstTokenAddress(),
            aliceGroup.groupServiceActionId,
            aliceGroup.groupServiceAddress
        );
    }

    function _verifyServiceRewardClaim(uint256 verifyRound) internal {
        ExtensionGroupService gs = ExtensionGroupService(
            aliceGroup.groupServiceAddress
        );
        ExtensionGroupAction ga = ExtensionGroupAction(
            bobGroup1.groupActionAddress
        );

        // 1. Get expected Group Action reward from mint contract
        (uint256 expectedGAReward, ) = h
            .mintContract()
            .actionRewardByActionIdByAccount(
                h.firstTokenAddress(),
                verifyRound,
                bobGroup1.groupActionId,
                bobGroup1.groupActionAddress
            );
        assertTrue(expectedGAReward > 0, "Expected GA reward > 0");
        assertEq(
            ga.reward(verifyRound),
            expectedGAReward,
            "GA reward matches mint"
        );

        // 2. Get expected Service reward from mint contract
        (uint256 expectedServiceReward, ) = h
            .mintContract()
            .actionRewardByActionIdByAccount(
                h.firstTokenAddress(),
                verifyRound,
                aliceGroup.groupServiceActionId,
                aliceGroup.groupServiceAddress
            );
        assertTrue(expectedServiceReward > 0, "Expected Service reward > 0");
        assertEq(
            gs.reward(verifyRound),
            expectedServiceReward,
            "Service reward matches mint"
        );

        // 3. Calculate expected bobGroup1's service reward
        // bobGroup1 is only provider with only group action, so he gets 100%
        uint256 bobGroup1GeneratedReward = ga.generatedActionRewardByVerifier(
            verifyRound,
            bobGroup1.flow.userAddress
        );
        assertEq(
            bobGroup1GeneratedReward,
            expectedGAReward,
            "Bob generated all"
        );

        uint256 expectedBobTotal = (expectedServiceReward *
            bobGroup1GeneratedReward) / expectedGAReward;
        assertEq(expectedBobTotal, expectedServiceReward, "Bob gets 100%");

        // 4. Verify extension contract calculation matches
        (uint256 contractValue, bool alreadyClaimed) = gs.rewardByAccount(
            verifyRound,
            bobGroup1.flow.userAddress
        );
        assertFalse(alreadyClaimed, "Should not be claimed yet");
        assertEq(contractValue, expectedBobTotal, "Contract matches formula");

        // 5. Verify recipients and distribution
        _verifyServiceRecipientsConfig(gs, verifyRound, expectedBobTotal);

        // 6. Claim and verify transfers
        _claimAndVerifyServiceTransfers(gs, verifyRound, expectedBobTotal);
    }

    function _verifyServiceRecipientsConfig(
        ExtensionGroupService gs,
        uint256 verifyRound,
        uint256 expectedTotal
    ) internal {
        // Verify recipients configuration
        (address[] memory addrs, uint256[] memory ratios) = gs.recipients(
            bobGroup1.flow.userAddress,
            bobGroup1.groupActionId,
            bobGroup1.groupId,
            verifyRound
        );
        assertEq(addrs.length, 2, "Should have 2 recipients");
        assertEq(addrs[0], member2().userAddress, "Recipient 0 = member2");
        assertEq(addrs[1], member3().userAddress, "Recipient 1 = member3");
        assertEq(ratios[0], 5e17, "Recipient 0 = 50%");
        assertEq(ratios[1], 3e17, "Recipient 1 = 30%");

        // Calculate expected amounts
        uint256 expectedM2 = (expectedTotal * 5e17) / 1e18;
        uint256 expectedM3 = (expectedTotal * 3e17) / 1e18;
        uint256 expectedBob = expectedTotal - expectedM2 - expectedM3;

        // Verify rewardByRecipient
        assertEq(
            gs.rewardByRecipient(
                verifyRound,
                bobGroup1.flow.userAddress,
                bobGroup1.groupActionId,
                bobGroup1.groupId,
                member2().userAddress
            ),
            expectedM2,
            "rewardByRecipient m2"
        );
        assertEq(
            gs.rewardByRecipient(
                verifyRound,
                bobGroup1.flow.userAddress,
                bobGroup1.groupActionId,
                bobGroup1.groupId,
                member3().userAddress
            ),
            expectedM3,
            "rewardByRecipient m3"
        );
        assertEq(
            gs.rewardByRecipient(
                verifyRound,
                bobGroup1.flow.userAddress,
                bobGroup1.groupActionId,
                bobGroup1.groupId,
                bobGroup1.flow.userAddress
            ),
            expectedBob,
            "rewardByRecipient bobGroup1"
        );

        // Verify rewardDistribution
        (
            address[] memory distAddrs,
            uint256[] memory distRatios,
            uint256[] memory distAmounts,
            uint256 ownerAmt
        ) = gs.rewardDistribution(
                verifyRound,
                bobGroup1.flow.userAddress,
                bobGroup1.groupActionId,
                bobGroup1.groupId
            );

        assertEq(distAddrs.length, 2, "Distribution has 2 recipients");
        assertEq(distAmounts[0], expectedM2, "Distribution amt 0");
        assertEq(distAmounts[1], expectedM3, "Distribution amt 1");
        assertEq(ownerAmt, expectedBob, "Owner amount");
        assertEq(distRatios[0], 5e17, "Distribution ratios 0");
        assertEq(distRatios[1], 3e17, "Distribution ratios 1");
    }

    function _claimAndVerifyServiceTransfers(
        ExtensionGroupService gs,
        uint256 verifyRound,
        uint256 expectedTotal
    ) internal {
        // Calculate expected amounts
        uint256 expectedM2 = (expectedTotal * 5e17) / 1e18;
        uint256 expectedM3 = (expectedTotal * 3e17) / 1e18;
        uint256 expectedBob = expectedTotal - expectedM2 - expectedM3;

        // Record balances
        uint256 bobGroup1Bal = IERC20(h.firstTokenAddress()).balanceOf(
            bobGroup1.flow.userAddress
        );
        uint256 m2Bal = IERC20(h.firstTokenAddress()).balanceOf(
            member2().userAddress
        );
        uint256 m3Bal = IERC20(h.firstTokenAddress()).balanceOf(
            member3().userAddress
        );

        // Claim
        uint256 claimed = h.group_service_claim_reward(bobGroup1, verifyRound);
        assertEq(claimed, expectedTotal, "Claimed amount mismatch");

        // Verify claimed status
        (, bool isClaimed) = gs.rewardByAccount(
            verifyRound,
            bobGroup1.flow.userAddress
        );
        assertTrue(isClaimed, "Should be marked as claimed");

        // Verify token transfers
        assertEq(
            IERC20(h.firstTokenAddress()).balanceOf(member2().userAddress) -
                m2Bal,
            expectedM2,
            "Member2 transfer"
        );
        assertEq(
            IERC20(h.firstTokenAddress()).balanceOf(member3().userAddress) -
                m3Bal,
            expectedM3,
            "Member3 transfer"
        );
        assertEq(
            IERC20(h.firstTokenAddress()).balanceOf(
                bobGroup1.flow.userAddress
            ) - bobGroup1Bal,
            expectedBob,
            "Bob transfer"
        );

        // Verify total
        assertEq(
            expectedM2 + expectedM3 + expectedBob,
            claimed,
            "Total = claimed"
        );
    }

    function _verifyActionRewardClaim(
        GroupUserParams memory m1,
        uint256 verifyRound
    ) internal {
        ExtensionGroupAction ga = ExtensionGroupAction(
            bobGroup1.groupActionAddress
        );

        // Get total reward and verify > 0
        uint256 totalReward = ga.reward(verifyRound);
        assertTrue(totalReward > 0, "Action total reward should be > 0");

        // Calculate expected reward for m1
        // m1: score=100, joinAmount=10e18 => accountScore = 1000e18
        // Only m1 in this test, so m1 gets all group reward
        uint256 m1AccountScore = 100 * 10e18;
        uint256 groupTotalScore = m1AccountScore;
        uint256 expectedM1Reward = (totalReward * m1AccountScore) /
            groupTotalScore;

        // Verify expected reward before claiming
        (uint256 m1Expected, ) = ga.rewardByAccount(
            verifyRound,
            m1.flow.userAddress
        );
        assertEq(m1Expected, expectedM1Reward, "M1 expected reward mismatch");
        assertEq(m1Expected, totalReward, "M1 should get all action reward");

        // Claim and verify
        uint256 balBefore = IERC20(h.firstTokenAddress()).balanceOf(
            m1.flow.userAddress
        );
        uint256 reward = h.group_action_claim_reward(
            m1,
            bobGroup1,
            verifyRound
        );

        assertEq(
            reward,
            expectedM1Reward,
            "Claimed reward should match expected"
        );
        assertEq(
            IERC20(h.firstTokenAddress()).balanceOf(m1.flow.userAddress),
            balBefore + reward,
            "Member1 balance should increase by exact reward"
        );

        // Verify claimed status
        (, bool claimed) = ga.rewardByAccount(verifyRound, m1.flow.userAddress);
        assertTrue(claimed, "Member1 action reward should be claimed");
    }

    /// @notice Test multi-group scenario with different recipients per group
    function test_multi_group_different_recipients() public {
        // === Vote Phase ===
        // Bob creates and submits group action
        bobGroup1.groupActionAddress = h.group_action_create(bobGroup1);
        bobGroup1.groupActionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = bobGroup1.groupActionId;
        h.vote(bobGroup1.flow);

        // Alice creates and submits group service
        aliceGroup.groupServiceAddress = h.group_service_create(
            aliceGroup,
            h.firstTokenAddress()
        );
        aliceGroup.groupServiceActionId = h.submit_group_service_action(
            aliceGroup
        );
        aliceGroup.flow.actionId = aliceGroup.groupServiceActionId;
        h.vote(aliceGroup.flow);

        // === Join Phase ===
        h.next_phase();

        // Activate both groups for Bob
        h.group_activate(bobGroup1);
        bobGroup2.groupActionAddress = bobGroup1.groupActionAddress;
        bobGroup2.groupActionId = bobGroup1.groupActionId;
        h.group_activate(bobGroup2);

        // Members join different groups
        GroupUserParams memory m1;
        m1.flow = member1();
        m1.joinAmount = 10e18;
        m1.groupActionAddress = bobGroup1.groupActionAddress;
        h.group_join(m1, bobGroup1);

        GroupUserParams memory m2;
        m2.flow = member2();
        m2.joinAmount = 20e18;
        m2.groupActionAddress = bobGroup1.groupActionAddress;
        h.group_join(m2, bobGroup2);

        // Bob joins service
        bobGroup1.groupServiceAddress = aliceGroup.groupServiceAddress;
        bobGroup1.groupServiceActionId = aliceGroup.groupServiceActionId;
        bobGroup2.groupServiceAddress = aliceGroup.groupServiceAddress;
        bobGroup2.groupServiceActionId = aliceGroup.groupServiceActionId;
        h.group_service_join(bobGroup1);

        // Verify joinedAmount after join (should include both groups)
        uint256 joinedVal = ExtensionGroupService(
            aliceGroup.groupServiceAddress
        ).joinedAmount();
        uint256 expectedJoinedVal = h.getGroupManager().staked(
            bobGroup1.groupActionAddress
        );
        assertEq(
            joinedVal,
            expectedJoinedVal,
            "joinedAmount should match totalStaked from groupManager"
        );

        // Verify joinedAmountByAccount for Bob (should include both groups)
        uint256 bobJoinedVal = ExtensionGroupService(
            aliceGroup.groupServiceAddress
        ).joinedAmountByAccount(bobGroup1.flow.userAddress);
        uint256 expectedBobJoinedVal = h.getGroupManager().stakedByOwner(
            bobGroup1.groupActionAddress,
            bobGroup1.flow.userAddress
        );
        assertEq(
            bobJoinedVal,
            expectedBobJoinedVal,
            "joinedAmountByAccount for Bob should match"
        );

        // Set different recipients for different groups
        // Group1: 30% to member3, 20% to member4
        address[] memory recipients1 = new address[](2);
        recipients1[0] = member3().userAddress;
        recipients1[1] = member4().userAddress;
        uint256[] memory ratios1 = new uint256[](2);
        ratios1[0] = 3e17;
        ratios1[1] = 2e17;
        bobGroup1.recipients = recipients1;
        bobGroup1.ratios = ratios1;
        h.group_service_set_recipients(bobGroup1);

        // Group2: 60% to member5
        address[] memory recipients2 = new address[](1);
        recipients2[0] = member5().userAddress;
        uint256[] memory ratios2 = new uint256[](1);
        ratios2[0] = 6e17;
        bobGroup2.recipients = recipients2;
        bobGroup2.ratios = ratios2;
        h.group_service_set_recipients(bobGroup2);

        // === Verify Phase ===
        h.next_phase();
        uint256 verifyRound = h.verifyContract().currentRound();

        // Submit scores for both groups
        uint256[] memory scores1 = new uint256[](1);
        scores1[0] = 100;
        h.group_submit_score(bobGroup1, scores1);

        uint256[] memory scores2 = new uint256[](1);
        scores2[0] = 100;
        h.group_submit_score(bobGroup2, scores2);

        // Core verify
        h.core_verify_extension(bobGroup1, bobGroup1.groupActionAddress);
        h.core_verify_extension(
            aliceGroup.flow,
            h.firstTokenAddress(),
            aliceGroup.groupServiceActionId,
            aliceGroup.groupServiceAddress
        );

        // === Claim Phase ===
        h.next_phase();

        // Record balances before claim
        uint256 m3Bal = IERC20(h.firstTokenAddress()).balanceOf(
            member3().userAddress
        );
        uint256 m4Bal = IERC20(h.firstTokenAddress()).balanceOf(
            member4().userAddress
        );
        uint256 m5Bal = IERC20(h.firstTokenAddress()).balanceOf(
            member5().userAddress
        );

        // Claim
        uint256 totalClaimed = h.group_service_claim_reward(
            bobGroup1,
            verifyRound
        );
        assertTrue(totalClaimed > 0, "Should claim some reward");

        // Verify transfers directly using rewardByRecipient
        // Group1 reward: 30% to m3, 20% to m4, 50% to bob
        // Group2 reward: 60% to m5, 40% to bob
        address serviceAddr = aliceGroup.groupServiceAddress;
        _verifyRecipientBalance(
            serviceAddr,
            verifyRound,
            member3().userAddress,
            m3Bal,
            bobGroup1.flow.userAddress,
            bobGroup1.groupActionId,
            bobGroup1.groupId,
            "Member3 should receive group1 30%"
        );
        _verifyRecipientBalance(
            serviceAddr,
            verifyRound,
            member4().userAddress,
            m4Bal,
            bobGroup1.flow.userAddress,
            bobGroup1.groupActionId,
            bobGroup1.groupId,
            "Member4 should receive group1 20%"
        );
        _verifyRecipientBalance(
            serviceAddr,
            verifyRound,
            member5().userAddress,
            m5Bal,
            bobGroup1.flow.userAddress,
            bobGroup2.groupActionId,
            bobGroup2.groupId,
            "Member5 should receive group2 60%"
        );
    }

    function _verifyRecipientBalance(
        address serviceAddr,
        uint256 round,
        address recipient,
        uint256 balanceBefore,
        address groupOwner,
        uint256 actionId,
        uint256 groupId,
        string memory message
    ) internal view {
        assertEq(
            IERC20(h.firstTokenAddress()).balanceOf(recipient) - balanceBefore,
            ExtensionGroupService(serviceAddr).rewardByRecipient(
                round,
                groupOwner,
                actionId,
                groupId,
                recipient
            ),
            message
        );
    }

    /// @notice Test joinedAmount includes all actions, not just voted ones
    function test_joinedAmount_includes_all_actions_not_just_voted() public {
        // 1. Create and submit first group action by bob (with voting)
        bobGroup1.groupActionAddress = h.group_action_create(bobGroup1);
        bobGroup1.groupActionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = bobGroup1.groupActionId;
        h.vote(bobGroup1.flow);

        // 2. Create and submit second group action by alice (with voting - needed for activation)
        aliceGroup.groupActionAddress = h.group_action_create(aliceGroup);
        aliceGroup.groupActionId = h.submit_group_action(aliceGroup);
        aliceGroup.flow.actionId = aliceGroup.groupActionId;
        h.vote(aliceGroup.flow); // Vote for alice's action too

        // 3. Activate both group actions in join phase
        h.next_phase();
        h.group_activate(bobGroup1);
        h.group_activate(aliceGroup);

        // 4. Move to next vote phase so bob can submit group service
        h.next_phase(); // Verify phase
        h.next_phase(); // Back to vote phase

        // 5. Re-submit and vote for both actions in this round
        // Note: This creates new actionIds, but groups are still linked to original actionIds
        bobGroup1.groupActionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = bobGroup1.groupActionId;
        h.vote(bobGroup1.flow);

        // 6. Alice submits and votes for group service (using her staked governance)
        aliceGroup.groupServiceAddress = h.group_service_create(
            aliceGroup,
            h.firstTokenAddress()
        );
        aliceGroup.groupServiceActionId = h.submit_group_service_action(
            aliceGroup
        );
        aliceGroup.flow.actionId = aliceGroup.groupServiceActionId;
        h.vote(aliceGroup.flow);

        // 7. Move to join phase and bob joins service
        h.next_phase();
        bobGroup1.groupServiceAddress = aliceGroup.groupServiceAddress;
        bobGroup1.groupServiceActionId = aliceGroup.groupServiceActionId;
        h.group_service_join(bobGroup1);

        // 8. Verify joinedAmount includes both actions
        ExtensionGroupService gs = ExtensionGroupService(
            aliceGroup.groupServiceAddress
        );
        uint256 joinedVal = gs.joinedAmount();
        // Use original actionIds for expected value calculation since groups were activated with those
        uint256 expectedJoinedVal = h.getGroupManager().staked(
            bobGroup1.groupActionAddress
        ) + h.getGroupManager().staked(aliceGroup.groupActionAddress);
        assertEq(
            joinedVal,
            expectedJoinedVal,
            "joinedAmount should include all actions (both have groups activated)"
        );
        assertTrue(joinedVal > 0, "joinedAmount should be greater than 0");
    }

    /// @notice Test joinedAmountByAccount includes all actions, not just voted ones
    function test_joinedAmountByAccount_includes_all_actions_not_just_voted()
        public
    {
        // 1. Create and submit first group action by bob (with voting)
        bobGroup1.groupActionAddress = h.group_action_create(bobGroup1);
        bobGroup1.groupActionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = bobGroup1.groupActionId;
        h.vote(bobGroup1.flow);

        // 2. Create and submit second group action by alice (with voting - needed for activation)
        aliceGroup.groupActionAddress = h.group_action_create(aliceGroup);
        aliceGroup.groupActionId = h.submit_group_action(aliceGroup);
        aliceGroup.flow.actionId = aliceGroup.groupActionId;
        h.vote(aliceGroup.flow);

        // 3. Activate both group actions and bob's second group in alice's action
        h.next_phase();
        h.group_activate(bobGroup1);
        h.group_activate(aliceGroup);

        // Bob also activates his second group (bobGroup2) in alice's action
        // This way bob has groups in both actions
        bobGroup2.groupActionAddress = aliceGroup.groupActionAddress;
        bobGroup2.groupActionId = aliceGroup.groupActionId;
        h.group_activate(bobGroup2);

        // 4. Move to next vote phase so alice can submit group service
        h.next_phase(); // Verify phase
        h.next_phase(); // Back to vote phase

        // 5. Re-submit and vote for bob's action in this round
        // Note: This creates a new actionId, but groups are still linked to original actionId
        bobGroup1.groupActionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = bobGroup1.groupActionId;
        h.vote(bobGroup1.flow);

        // 6. Alice submits and votes for group service
        aliceGroup.groupServiceAddress = h.group_service_create(
            aliceGroup,
            h.firstTokenAddress()
        );
        aliceGroup.groupServiceActionId = h.submit_group_service_action(
            aliceGroup
        );
        aliceGroup.flow.actionId = aliceGroup.groupServiceActionId;
        h.vote(aliceGroup.flow);

        // 7. Move to join phase and bob joins service
        h.next_phase();
        bobGroup1.groupServiceAddress = aliceGroup.groupServiceAddress;
        bobGroup1.groupServiceActionId = aliceGroup.groupServiceActionId;
        h.group_service_join(bobGroup1);

        // 8. Verify joinedAmountByAccount includes both actions
        ExtensionGroupService gs = ExtensionGroupService(
            aliceGroup.groupServiceAddress
        );
        uint256 bobJoinedVal = gs.joinedAmountByAccount(
            bobGroup1.flow.userAddress
        );
        // Use original actionIds for expected value calculation since groups were activated with those
        uint256 expectedBobJoinedVal = h.getGroupManager().stakedByOwner(
            bobGroup1.groupActionAddress,
            bobGroup1.flow.userAddress
        ) +
            h.getGroupManager().stakedByOwner(
                aliceGroup.groupActionAddress,
                bobGroup1.flow.userAddress
            );
        assertEq(
            bobJoinedVal,
            expectedBobJoinedVal,
            "joinedAmountByAccount should include all actions"
        );
        assertTrue(bobJoinedVal > 0, "bobJoinedVal should be greater than 0");
    }
}
