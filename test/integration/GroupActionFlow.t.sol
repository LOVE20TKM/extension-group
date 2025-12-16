// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseGroupFlowTest} from "./base/BaseGroupFlowTest.sol";
import {GroupUserParams} from "./helper/TestGroupFlowHelper.sol";
import {
    LOVE20ExtensionGroupAction
} from "../../src/LOVE20ExtensionGroupAction.sol";

/// @title GroupActionFlowTest
/// @notice Integration test for complete group action flow
contract GroupActionFlowTest is BaseGroupFlowTest {
    /// @notice Test complete group action flow: create → submit → vote → activate → join → score → claim reward
    function test_full_group_action_flow() public {
        // 1. Create and setup group action
        bobGroup1.groupActionAddress = h.group_action_create(bobGroup1);
        bobGroup1.groupActionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = bobGroup1.groupActionId;
        h.vote(bobGroup1.flow);

        // 2. Activate and join
        h.next_phase();
        h.group_activate(bobGroup1);

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

        // 3. Submit scores in verify phase
        h.next_phase();
        uint256 verifyRound = h.verifyContract().currentRound();
        _submitTwoMemberScores();

        // 4. Core protocol verification - bobGroup1 verifies extension contract
        h.core_verify_extension(bobGroup1, bobGroup1.groupActionAddress);

        // Verify join state
        LOVE20ExtensionGroupAction ga = LOVE20ExtensionGroupAction(
            bobGroup1.groupActionAddress
        );
        assertEq(ga.totalJoinedAmount(), 30e18, "Total joined amount mismatch");
        assertEq(
            ga.accountsByGroupIdCount(bobGroup1.groupId),
            2,
            "Member count mismatch"
        );

        // 5. Claim rewards after verify phase ends
        h.next_phase();
        _verifyMemberRewardClaim(m1, m2, verifyRound);
    }

    function _submitTwoMemberScores() internal {
        uint256[] memory scores = new uint256[](2);
        scores[0] = 80;
        scores[1] = 90;
        h.group_submit_score(bobGroup1, scores);
    }

    function _verifyMemberRewardClaim(
        GroupUserParams memory m1,
        GroupUserParams memory m2,
        uint256 verifyRound
    ) internal {
        LOVE20ExtensionGroupAction ga = LOVE20ExtensionGroupAction(
            bobGroup1.groupActionAddress
        );

        // Get expected total reward from mint contract (source of truth)
        (uint256 expectedTotalReward, ) = h
            .mintContract()
            .actionRewardByActionIdByAccount(
                h.firstTokenAddress(),
                verifyRound,
                bobGroup1.groupActionId,
                bobGroup1.groupActionAddress
            );
        assertTrue(expectedTotalReward > 0, "Expected total reward > 0");

        // Verify extension contract matches mint contract
        assertEq(
            ga.reward(verifyRound),
            expectedTotalReward,
            "GA reward matches mint"
        );

        // Verify and claim m1
        _claimAndVerifyMemberReward(
            ga,
            m1,
            verifyRound,
            80,
            10e18,
            expectedTotalReward
        );
        // Verify and claim m2
        _claimAndVerifyMemberReward(
            ga,
            m2,
            verifyRound,
            90,
            20e18,
            expectedTotalReward
        );

        // Verify reward ratio (m1:m2 = 800:1800 = 4:9)
        (uint256 m1Claimed, ) = ga.rewardByAccount(
            verifyRound,
            m1.flow.userAddress
        );
        (uint256 m2Claimed, ) = ga.rewardByAccount(
            verifyRound,
            m2.flow.userAddress
        );
        // m1Score=800e18, m2Score=1800e18 => ratio = 4:9
        uint256 product1 = m2Claimed * 4;
        uint256 product2 = m1Claimed * 9;
        uint256 diff = product1 > product2
            ? product1 - product2
            : product2 - product1;
        assertTrue(
            diff * 1e10 < product1,
            "Reward ratio should match score ratio (4:9)"
        );
    }

    function _claimAndVerifyMemberReward(
        LOVE20ExtensionGroupAction ga,
        GroupUserParams memory member,
        uint256 verifyRound,
        uint256 score,
        uint256 joinAmount,
        uint256 totalReward
    ) internal {
        // Calculate expected reward using formula:
        // accountScore = originScore * joinAmount
        // expectedReward = totalReward * accountScore / groupTotalScore
        // m1: 80*10e18=800e18, m2: 90*20e18=1800e18, total=2600e18
        uint256 groupTotalScore = 80 * 10e18 + 90 * 20e18;
        uint256 accountScore = score * joinAmount;
        uint256 expectedReward = (totalReward * accountScore) / groupTotalScore;

        // Verify extension contract calculation matches our formula
        (uint256 contractExpected, ) = ga.rewardByAccount(
            verifyRound,
            member.flow.userAddress
        );
        assertEq(contractExpected, expectedReward, "Contract matches formula");

        // Claim
        uint256 balBefore = IERC20(h.firstTokenAddress()).balanceOf(
            member.flow.userAddress
        );
        uint256 claimed = h.group_action_claim_reward(member, bobGroup1, verifyRound);

        // Verify claimed amount matches calculated
        assertEq(claimed, expectedReward, "Claimed matches calculated");
        assertEq(
            IERC20(h.firstTokenAddress()).balanceOf(member.flow.userAddress),
            balBefore + claimed,
            "Balance increased correctly"
        );
    }
}
