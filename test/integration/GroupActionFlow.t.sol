// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseGroupFlowTest} from "./base/BaseGroupFlowTest.sol";
import {GroupUserParams} from "./helper/TestGroupFlowHelper.sol";
import {ExtensionGroupAction} from "../../src/ExtensionGroupAction.sol";
import {GroupJoin} from "../../src/GroupJoin.sol";
import {IGroupJoin} from "../../src/interface/IGroupJoin.sol";

/// @title GroupActionFlowTest
/// @notice Integration test for complete group action flow
contract GroupActionFlowTest is BaseGroupFlowTest {
    // Store state for claim verification to reduce stack depth
    uint256 internal _verifyRound;
    ExtensionGroupAction internal _ga;

    // Expected values calculated at the start - independent of contract view methods
    struct ExpectedRewards {
        uint256 totalReward; // Total reward for the group action
        uint256 member1Reward; // Expected reward for member1
        uint256 member2Reward; // Expected reward for member2
        uint256 member1AccountScore; // member1's accountScore (score * joinAmount)
        uint256 member2AccountScore; // member2's accountScore (score * joinAmount)
        uint256 groupTotalScore; // Total score for the group
    }
    ExpectedRewards internal _expected;

    /// @notice Test complete group action flow
    function test_full_group_action_flow() public {
        _setupGroupAction();
        _activateAndJoinMembers();
        _submitScoresAndVerify();
        _calculateExpectedRewards();
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
            groupJoin.joinedAmount(bobGroup1.groupActionAddress),
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

    /// @notice Calculate all expected reward values at the start, before any verification
    /// @dev This function calculates expected values based on business rules, not contract view methods
    function _calculateExpectedRewards() internal {
        h.next_phase();

        // Get totalReward from mint contract (this is the only external dependency)
        // We need this to calculate member rewards, but we calculate it once and use it for all verifications
        (_expected.totalReward, ) = h
            .mintContract()
            .actionRewardByActionIdByAccount(
                h.firstTokenAddress(),
                _verifyRound,
                bobGroup1.groupActionId,
                bobGroup1.groupActionAddress
            );
        assertTrue(_expected.totalReward > 0, "Expected total reward > 0");

        // Calculate expected values based on business rules (not contract view methods)
        // Input parameters from test setup:
        // - member1: score=80, joinAmount=10e18
        // - member2: score=90, joinAmount=20e18

        // AccountScore formula: accountScore = originScore * joinAmount
        _expected.member1AccountScore = 80 * 10e18; // 800e18
        _expected.member2AccountScore = 90 * 20e18; // 1800e18

        // GroupTotalScore = sum of all accountScores in the group
        _expected.groupTotalScore =
            _expected.member1AccountScore +
            _expected.member2AccountScore; // 2600e18

        // Member reward formula: memberReward = (totalReward * accountScore) / groupTotalScore
        _expected.member1Reward =
            (_expected.totalReward * _expected.member1AccountScore) /
            _expected.groupTotalScore;
        _expected.member2Reward =
            (_expected.totalReward * _expected.member2AccountScore) /
            _expected.groupTotalScore;

        // Verify expected values sum to totalReward (with rounding tolerance)
        uint256 sumRewards = _expected.member1Reward + _expected.member2Reward;
        // Allow small rounding difference (up to 1 wei per member)
        assertTrue(
            sumRewards >= _expected.totalReward - 2 &&
                sumRewards <= _expected.totalReward,
            "Sum of member rewards should equal total reward (with rounding tolerance)"
        );
    }

    function _claimAndVerifyRewards() internal {
        // Verify total reward matches expected
        assertEq(
            _ga.reward(_verifyRound),
            _expected.totalReward,
            "GA reward matches expected"
        );

        _claimMember1Reward();
        _claimMember2Reward();
        _verifyRewardRatio();
    }

    function _claimMember1Reward() internal {
        GroupUserParams memory m1;
        m1.flow = member1();

        // Record balance before claim
        uint256 balBefore = IERC20(h.firstTokenAddress()).balanceOf(
            m1.flow.userAddress
        );

        // Claim reward
        uint256 claimed = h.group_action_claim_reward(
            m1,
            bobGroup1,
            _verifyRound
        );

        // Verify claimed amount matches expected (calculated independently)
        assertEq(
            claimed,
            _expected.member1Reward,
            "M1 claimed matches expected"
        );

        // Verify contract's view method matches expected (as additional check, not primary verification)
        (uint256 contractValue, ) = _ga.rewardByAccount(
            _verifyRound,
            member1().userAddress
        );
        assertEq(
            contractValue,
            _expected.member1Reward,
            "M1 contract view matches expected"
        );

        // Verify balance increased by exact expected amount
        assertEq(
            IERC20(h.firstTokenAddress()).balanceOf(m1.flow.userAddress),
            balBefore + _expected.member1Reward,
            "M1 balance increased by expected amount"
        );
    }

    function _claimMember2Reward() internal {
        GroupUserParams memory m2;
        m2.flow = member2();

        // Record balance before claim
        uint256 balBefore = IERC20(h.firstTokenAddress()).balanceOf(
            m2.flow.userAddress
        );

        // Claim reward
        uint256 claimed = h.group_action_claim_reward(
            m2,
            bobGroup1,
            _verifyRound
        );

        // Verify claimed amount matches expected (calculated independently)
        assertEq(
            claimed,
            _expected.member2Reward,
            "M2 claimed matches expected"
        );

        // Verify contract's view method matches expected (as additional check, not primary verification)
        (uint256 contractValue, ) = _ga.rewardByAccount(
            _verifyRound,
            member2().userAddress
        );
        assertEq(
            contractValue,
            _expected.member2Reward,
            "M2 contract view matches expected"
        );

        // Verify balance increased by exact expected amount
        assertEq(
            IERC20(h.firstTokenAddress()).balanceOf(m2.flow.userAddress),
            balBefore + _expected.member2Reward,
            "M2 balance increased by expected amount"
        );
    }

    function _verifyRewardRatio() internal {
        // Verify reward ratio based on expected values (not contract view methods)
        // Expected ratio: member1:member2 = 800e18:1800e18 = 4:9
        // This means: member2Reward * 4 should equal member1Reward * 9

        uint256 product1 = _expected.member2Reward * 4;
        uint256 product2 = _expected.member1Reward * 9;
        uint256 diff = product1 > product2
            ? product1 - product2
            : product2 - product1;

        // Allow small rounding difference (up to 1e10 wei relative to product1)
        assertTrue(diff * 1e10 < product1, "Reward ratio 4:9 matches expected");

        // Additional verification: verify contract values also match the ratio
        // (This is a secondary check, primary verification uses expected values)
        (uint256 m1ContractValue, ) = _ga.rewardByAccount(
            _verifyRound,
            member1().userAddress
        );
        (uint256 m2ContractValue, ) = _ga.rewardByAccount(
            _verifyRound,
            member2().userAddress
        );

        uint256 contractProduct1 = m2ContractValue * 4;
        uint256 contractProduct2 = m1ContractValue * 9;
        uint256 contractDiff = contractProduct1 > contractProduct2
            ? contractProduct1 - contractProduct2
            : contractProduct2 - contractProduct1;
        assertTrue(
            contractDiff * 1e10 < contractProduct1,
            "Contract reward ratio 4:9"
        );
    }
}
