// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseGroupFlowTest} from "./base/BaseGroupFlowTest.sol";
import {GroupUserParams} from "./helper/TestGroupFlowHelper.sol";
import {
    ExtensionGroupAction
} from "../../src/ExtensionGroupAction.sol";
import {GroupJoin} from "../../src/GroupJoin.sol";
import {IGroupJoin} from "../../src/interface/IGroupJoin.sol";

/// @title GroupActionFlowTest
/// @notice Integration test for complete group action flow
contract GroupActionFlowTest is BaseGroupFlowTest {
    // Store state for claim verification to reduce stack depth
    uint256 internal _verifyRound;
    uint256 internal _totalReward;
    ExtensionGroupAction internal _ga;

    /// @notice Test complete group action flow
    function test_full_group_action_flow() public {
        _setupGroupAction();
        _activateAndJoinMembers();
        _submitScoresAndVerify();
        _claimAndVerifyRewards();
    }

    function _setupGroupAction() internal {
        bobGroup1.groupActionAddress = h.group_action_create(bobGroup1);
        bobGroup1.groupActionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = bobGroup1.groupActionId;
        h.vote(bobGroup1.flow);
    }

    function _activateAndJoinMembers() internal {
        h.next_phase();
        h.group_activate(bobGroup1);

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
    }

    function _submitScoresAndVerify() internal {
        h.next_phase();
        _verifyRound = h.verifyContract().currentRound();

        uint256[] memory scores = new uint256[](2);
        scores[0] = 80;
        scores[1] = 90;
        h.group_submit_score(bobGroup1, scores);

        h.core_verify_extension(bobGroup1, bobGroup1.groupActionAddress);

        _ga = ExtensionGroupAction(bobGroup1.groupActionAddress);
        IGroupJoin groupJoin = IGroupJoin(
            h.groupActionFactory().GROUP_JOIN_ADDRESS()
        );
        assertEq(
            groupJoin.totalJoinedAmount(
                bobGroup1.groupActionAddress
            ),
            30e18,
            "Total joined mismatch"
        );
        assertEq(
            groupJoin.accountsByGroupIdCount(
                bobGroup1.groupActionAddress,
                bobGroup1.groupId
            ),
            2,
            "Member count"
        );
    }

    function _claimAndVerifyRewards() internal {
        h.next_phase();
        
        (_totalReward, ) = h.mintContract().actionRewardByActionIdByAccount(
            h.firstTokenAddress(),
            _verifyRound,
            bobGroup1.groupActionId,
            bobGroup1.groupActionAddress
        );
        assertTrue(_totalReward > 0, "Expected total reward > 0");
        assertEq(_ga.reward(_verifyRound), _totalReward, "GA reward matches");

        _claimMember1Reward();
        _claimMember2Reward();
        _verifyRewardRatio();
    }

    function _claimMember1Reward() internal {
        // score=80, joinAmount=10e18, groupTotal=2600e18
        uint256 expected = (_totalReward * 80 * 10e18) / (80 * 10e18 + 90 * 20e18);
        
        (uint256 contractExpected, ) = _ga.rewardByAccount(_verifyRound, member1().userAddress);
        assertEq(contractExpected, expected, "M1 contract matches");

        GroupUserParams memory m1;
        m1.flow = member1();
        uint256 balBefore = IERC20(h.firstTokenAddress()).balanceOf(m1.flow.userAddress);
        uint256 claimed = h.group_action_claim_reward(m1, bobGroup1, _verifyRound);
        
        assertEq(claimed, expected, "M1 claimed matches");
        assertEq(
            IERC20(h.firstTokenAddress()).balanceOf(m1.flow.userAddress),
            balBefore + claimed,
            "M1 balance"
        );
    }

    function _claimMember2Reward() internal {
        // score=90, joinAmount=20e18, groupTotal=2600e18
        uint256 expected = (_totalReward * 90 * 20e18) / (80 * 10e18 + 90 * 20e18);
        
        (uint256 contractExpected, ) = _ga.rewardByAccount(_verifyRound, member2().userAddress);
        assertEq(contractExpected, expected, "M2 contract matches");

        GroupUserParams memory m2;
        m2.flow = member2();
        uint256 balBefore = IERC20(h.firstTokenAddress()).balanceOf(m2.flow.userAddress);
        uint256 claimed = h.group_action_claim_reward(m2, bobGroup1, _verifyRound);
        
        assertEq(claimed, expected, "M2 claimed matches");
        assertEq(
            IERC20(h.firstTokenAddress()).balanceOf(m2.flow.userAddress),
            balBefore + claimed,
            "M2 balance"
        );
    }

    function _verifyRewardRatio() internal {
        (uint256 m1Claimed, ) = _ga.rewardByAccount(_verifyRound, member1().userAddress);
        (uint256 m2Claimed, ) = _ga.rewardByAccount(_verifyRound, member2().userAddress);
        
        // ratio = 4:9 (800e18 : 1800e18)
        uint256 product1 = m2Claimed * 4;
        uint256 product2 = m1Claimed * 9;
        uint256 diff = product1 > product2 ? product1 - product2 : product2 - product1;
        assertTrue(diff * 1e10 < product1, "Reward ratio 4:9");
    }
}
