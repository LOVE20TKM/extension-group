// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseGroupFlowTest} from "./base/BaseGroupFlowTest.sol";
import {GroupUserParams} from "./helper/TestGroupFlowHelper.sol";
import {
    LOVE20ExtensionGroupAction
} from "../../src/LOVE20ExtensionGroupAction.sol";
import {
    LOVE20ExtensionGroupService
} from "../../src/LOVE20ExtensionGroupService.sol";

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
        m1.flow = member1;
        m1.joinAmount = 10e18;
        m1.groupActionAddress = bobGroup1.groupActionAddress;
        h.group_join(m1, bobGroup1);

        // Bob joins aliceGroup's service (bobGroup1 has active group)
        bobGroup1.groupServiceAddress = aliceGroup.groupServiceAddress;
        bobGroup1.groupServiceActionId = aliceGroup.groupServiceActionId;
        h.group_service_join(bobGroup1);

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
        recipients[0] = member2.userAddress;
        recipients[1] = member3.userAddress;
        uint256[] memory basisPoints = new uint256[](2);
        basisPoints[0] = 5000; // 50%
        basisPoints[1] = 3000; // 30%
        bobGroup1.recipients = recipients;
        bobGroup1.basisPoints = basisPoints;
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
        LOVE20ExtensionGroupService gs = LOVE20ExtensionGroupService(
            aliceGroup.groupServiceAddress
        );
        LOVE20ExtensionGroupAction ga = LOVE20ExtensionGroupAction(
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
        uint256 bobGroup1GeneratedReward = ga.generatedRewardByVerifier(
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
        LOVE20ExtensionGroupService gs,
        uint256 verifyRound,
        uint256 expectedTotal
    ) internal view {
        // Verify recipients configuration
        (address[] memory addrs, uint256[] memory bps) = gs.recipients(
            bobGroup1.flow.userAddress,
            verifyRound
        );
        assertEq(addrs.length, 2, "Should have 2 recipients");
        assertEq(addrs[0], member2.userAddress, "Recipient 0 = member2");
        assertEq(addrs[1], member3.userAddress, "Recipient 1 = member3");
        assertEq(bps[0], 5000, "Recipient 0 = 50%");
        assertEq(bps[1], 3000, "Recipient 1 = 30%");

        // Calculate expected amounts
        uint256 expectedM2 = (expectedTotal * 5000) / 10000;
        uint256 expectedM3 = (expectedTotal * 3000) / 10000;
        uint256 expectedBob = expectedTotal - expectedM2 - expectedM3;

        // Verify rewardByRecipient
        assertEq(
            gs.rewardByRecipient(
                verifyRound,
                bobGroup1.flow.userAddress,
                member2.userAddress
            ),
            expectedM2,
            "rewardByRecipient m2"
        );
        assertEq(
            gs.rewardByRecipient(
                verifyRound,
                bobGroup1.flow.userAddress,
                member3.userAddress
            ),
            expectedM3,
            "rewardByRecipient m3"
        );
        assertEq(
            gs.rewardByRecipient(
                verifyRound,
                bobGroup1.flow.userAddress,
                bobGroup1.flow.userAddress
            ),
            expectedBob,
            "rewardByRecipient bobGroup1"
        );

        // Verify rewardDistribution
        (
            address[] memory distAddrs,
            uint256[] memory distBps,
            uint256[] memory distAmounts,
            uint256 ownerAmt
        ) = gs.rewardDistribution(verifyRound, bobGroup1.flow.userAddress);

        assertEq(distAddrs.length, 2, "Distribution has 2 recipients");
        assertEq(distAmounts[0], expectedM2, "Distribution amt 0");
        assertEq(distAmounts[1], expectedM3, "Distribution amt 1");
        assertEq(ownerAmt, expectedBob, "Owner amount");
        assertEq(distBps[0], 5000, "Distribution bps 0");
        assertEq(distBps[1], 3000, "Distribution bps 1");
    }

    function _claimAndVerifyServiceTransfers(
        LOVE20ExtensionGroupService gs,
        uint256 verifyRound,
        uint256 expectedTotal
    ) internal {
        // Calculate expected amounts
        uint256 expectedM2 = (expectedTotal * 5000) / 10000;
        uint256 expectedM3 = (expectedTotal * 3000) / 10000;
        uint256 expectedBob = expectedTotal - expectedM2 - expectedM3;

        // Record balances
        uint256 bobGroup1Bal = IERC20(h.firstTokenAddress()).balanceOf(
            bobGroup1.flow.userAddress
        );
        uint256 m2Bal = IERC20(h.firstTokenAddress()).balanceOf(
            member2.userAddress
        );
        uint256 m3Bal = IERC20(h.firstTokenAddress()).balanceOf(
            member3.userAddress
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
            IERC20(h.firstTokenAddress()).balanceOf(member2.userAddress) -
                m2Bal,
            expectedM2,
            "Member2 transfer"
        );
        assertEq(
            IERC20(h.firstTokenAddress()).balanceOf(member3.userAddress) -
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
        LOVE20ExtensionGroupAction ga = LOVE20ExtensionGroupAction(
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
}
