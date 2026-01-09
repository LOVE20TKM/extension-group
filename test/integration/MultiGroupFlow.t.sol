// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseGroupFlowTest} from "./base/BaseGroupFlowTest.sol";
import {GroupUserParams} from "./helper/TestGroupFlowHelper.sol";
import {ExtensionGroupAction} from "../../src/ExtensionGroupAction.sol";
import {IGroupVerify} from "../../src/interface/IGroupVerify.sol";
import {IGroupJoin} from "../../src/interface/IGroupJoin.sol";

/// @title MultiGroupFlowTest
/// @notice Integration tests for multi-group and multi-member scenarios
contract MultiGroupFlowTest is BaseGroupFlowTest {
    // Expected values calculated at the start - independent of contract view methods
    struct ExpectedGroupRewards {
        uint256 totalReward; // Total reward from mint contract
        uint256 group1Reward; // Group1's reward (from contract, used for member calculations)
        uint256 group2Reward; // Group2's reward (from contract, used for member calculations)
        uint256 group3Reward; // Group3's reward (from contract, used for member calculations)
        uint256[3] group1MemberRewards; // Expected rewards for group1 members
        uint256[3] group2MemberRewards; // Expected rewards for group2 members
        uint256[3] group3MemberRewards; // Expected rewards for group3 members
    }
    ExpectedGroupRewards internal _expected;
    /// @notice Test complex scenario: 3 groups (bob has 2, alice has 1), each with 3 members
    /// Verifies:
    /// 1. Reward distribution within each group (by score * joinAmount)
    /// 2. Reward distribution across groups (by core protocol score)
    /// 3. Total rewards for owner with multiple groups (bob)
    function test_multi_group_multi_member_flow() public {
        // === Setup Phase ===
        address extensionAddr = h.group_action_create(bobGroup1);

        // Submit action (bob submits since he created the extension)
        bobGroup1.groupActionAddress = extensionAddr;
        bobGroup1.groupActionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = bobGroup1.groupActionId;

        // All group owners reference same extension
        bobGroup2.groupActionAddress = extensionAddr;
        bobGroup2.flow.actionId = bobGroup1.groupActionId;
        bobGroup2.groupActionId = bobGroup1.groupActionId;
        aliceGroup.groupActionAddress = extensionAddr;
        aliceGroup.flow.actionId = bobGroup1.groupActionId;
        aliceGroup.groupActionId = bobGroup1.groupActionId;

        // Vote - all owners vote for the action
        h.vote(bobGroup1.flow);
        h.vote(aliceGroup.flow);
        // Note: bobGroup2 uses same address as bobGroup1, so only 2 votes

        // === Join Phase ===
        h.next_phase();

        // Activate groups
        h.group_activate(bobGroup1);
        h.group_activate(bobGroup2);
        h.group_activate(aliceGroup);

        // Create member params and join groups
        GroupUserParams[3] memory g1Members = _setupGroup1Members(
            extensionAddr
        );
        GroupUserParams[3] memory g2Members = _setupGroup2Members(
            extensionAddr
        );
        GroupUserParams[3] memory g3Members = _setupGroup3Members(
            extensionAddr
        );

        // === Verify Phase ===
        h.next_phase();
        uint256 verifyRound = h.verifyContract().currentRound();

        // Each owner submits scores for their group members
        _submitGroup1Scores(g1Members);
        _submitGroup2Scores(g2Members);
        _submitGroup3Scores(g3Members);

        // Core protocol verification
        h.core_verify_extension(bobGroup1, extensionAddr);
        h.core_verify_extension(bobGroup2, extensionAddr);
        h.core_verify_extension(aliceGroup, extensionAddr);

        // Verify state
        ExtensionGroupAction ga = ExtensionGroupAction(extensionAddr);
        IGroupVerify groupVerify = IGroupVerify(
            h.groupActionFactory().GROUP_VERIFY_ADDRESS()
        );
        IGroupJoin groupJoin = IGroupJoin(
            h.groupActionFactory().GROUP_JOIN_ADDRESS()
        );
        assertEq(
            groupVerify.verifiersCount(
                bobGroup1.groupActionAddress,
                verifyRound
            ),
            2,
            "2 unique verifiers (bobGroup1=bobGroup2, aliceGroup)"
        );
        assertEq(
            groupJoin.accountsByGroupIdCount(
                bobGroup1.groupActionAddress,
                bobGroup1.groupId
            ),
            3,
            "Group1 has 3 members"
        );
        assertEq(
            groupJoin.accountsByGroupIdCount(
                bobGroup1.groupActionAddress,
                bobGroup2.groupId
            ),
            3,
            "Group2 has 3 members"
        );
        assertEq(
            groupJoin.accountsByGroupIdCount(
                bobGroup1.groupActionAddress,
                aliceGroup.groupId
            ),
            3,
            "Group3 has 3 members"
        );

        // === Claim Phase ===
        h.next_phase();

        // Calculate all expected values before verification
        _calculateExpectedRewards(ga, verifyRound);

        // Verify rewards for each group
        _verifyGroup1Rewards(ga, g1Members, verifyRound);
        _verifyGroup2Rewards(ga, g2Members, verifyRound);
        _verifyGroup3Rewards(ga, g3Members, verifyRound);

        // Verify bob's total rewards from both groups
        _verifyBobTotalGroupRewards(ga, g1Members, g2Members, verifyRound);
    }

    /// @notice Test group action with multiple group owners
    function test_multi_group_owners() public {
        // 1. Bob creates and submits group action
        address extensionAddr = h.group_action_create(bobGroup1);
        bobGroup1.groupActionAddress = extensionAddr;
        uint256 actionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = actionId;
        bobGroup1.groupActionId = actionId;

        // 2. Alice also uses same extension (share same action ID)
        aliceGroup.groupActionAddress = extensionAddr;
        aliceGroup.flow.actionId = actionId;
        aliceGroup.groupActionId = actionId;

        // 3. Both vote for the action
        h.vote(bobGroup1.flow);
        h.vote(aliceGroup.flow);

        // 4. Move to join phase
        h.next_phase();
        h.group_activate(bobGroup1);
        h.group_activate(aliceGroup);

        // 5. Members join different groups
        GroupUserParams memory m1;
        m1.flow = member1();
        m1.joinAmount = 10e18;
        m1.groupActionAddress = extensionAddr;
        h.group_join(m1, bobGroup1);

        GroupUserParams memory m2;
        m2.flow = member2();
        m2.joinAmount = 15e18;
        m2.groupActionAddress = extensionAddr;
        h.group_join(m2, aliceGroup);

        // 6. Move to verify phase
        h.next_phase();

        // Both owners submit scores for their members
        uint256[] memory bobScores = new uint256[](1);
        bobScores[0] = 85;
        h.group_submit_score(bobGroup1, bobScores);

        uint256[] memory aliceScores = new uint256[](1);
        aliceScores[0] = 90;
        h.group_submit_score(aliceGroup, aliceScores);

        // Verify both verifiers registered
        IGroupVerify groupVerifyContract = IGroupVerify(
            h.groupActionFactory().GROUP_VERIFY_ADDRESS()
        );
        uint256 round = h.verifyContract().currentRound();
        assertEq(
            groupVerifyContract.verifiersCount(
                bobGroup1.groupActionAddress,
                round
            ),
            2,
            "Verifiers count mismatch"
        );
    }

    // ============ Setup Helpers ============

    function _setupGroup1Members(
        address extensionAddr
    ) internal returns (GroupUserParams[3] memory members) {
        // m1: join=10e18, score=80; m2: join=20e18, score=90; m3: join=15e18, score=85
        members[0].flow = member1();
        members[0].joinAmount = 10e18;
        members[0].groupActionAddress = extensionAddr;
        h.group_join(members[0], bobGroup1);

        members[1].flow = member2();
        members[1].joinAmount = 20e18;
        members[1].groupActionAddress = extensionAddr;
        h.group_join(members[1], bobGroup1);

        members[2].flow = member3();
        members[2].joinAmount = 15e18;
        members[2].groupActionAddress = extensionAddr;
        h.group_join(members[2], bobGroup1);
    }

    function _setupGroup2Members(
        address extensionAddr
    ) internal returns (GroupUserParams[3] memory members) {
        // m4: join=25e18, score=75; m5: join=30e18, score=95; m6: join=12e18, score=88
        members[0].flow = member4();
        members[0].joinAmount = 25e18;
        members[0].groupActionAddress = extensionAddr;
        h.group_join(members[0], bobGroup2);

        members[1].flow = member5();
        members[1].joinAmount = 30e18;
        members[1].groupActionAddress = extensionAddr;
        h.group_join(members[1], bobGroup2);

        members[2].flow = member6();
        members[2].joinAmount = 12e18;
        members[2].groupActionAddress = extensionAddr;
        h.group_join(members[2], bobGroup2);
    }

    function _setupGroup3Members(
        address extensionAddr
    ) internal returns (GroupUserParams[3] memory members) {
        // m7: join=18e18, score=82; m8: join=22e18, score=93; m9: join=16e18, score=78
        members[0].flow = member7();
        members[0].joinAmount = 18e18;
        members[0].groupActionAddress = extensionAddr;
        h.group_join(members[0], aliceGroup);

        members[1].flow = member8();
        members[1].joinAmount = 22e18;
        members[1].groupActionAddress = extensionAddr;
        h.group_join(members[1], aliceGroup);

        members[2].flow = member9();
        members[2].joinAmount = 16e18;
        members[2].groupActionAddress = extensionAddr;
        h.group_join(members[2], aliceGroup);
    }

    // ============ Score Submission Helpers ============

    function _submitGroup1Scores(GroupUserParams[3] memory) internal {
        uint256[] memory scores = new uint256[](3);
        scores[0] = 80;
        scores[1] = 90;
        scores[2] = 85;
        h.group_submit_score(bobGroup1, scores);
    }

    function _submitGroup2Scores(GroupUserParams[3] memory) internal {
        uint256[] memory scores = new uint256[](3);
        scores[0] = 75;
        scores[1] = 95;
        scores[2] = 88;
        h.group_submit_score(bobGroup2, scores);
    }

    function _submitGroup3Scores(GroupUserParams[3] memory) internal {
        uint256[] memory scores = new uint256[](3);
        scores[0] = 82;
        scores[1] = 93;
        scores[2] = 78;
        h.group_submit_score(aliceGroup, scores);
    }

    // ============ Reward Calculation Helpers ============

    /// @notice Calculate all expected reward values at the start
    /// @dev This function calculates expected values based on business rules, not contract view methods
    function _calculateExpectedRewards(
        ExtensionGroupAction ga,
        uint256 verifyRound
    ) internal {
        // Get total reward from mint contract (only external dependency)
        (_expected.totalReward, ) = h
            .mintContract()
            .actionRewardByActionIdByAccount(
                h.firstTokenAddress(),
                verifyRound,
                bobGroup1.groupActionId,
                bobGroup1.groupActionAddress
            );
        assertTrue(_expected.totalReward > 0, "Total reward should be > 0");

        // Get group rewards from contract (needed to calculate member rewards)
        // Note: We get these once and use them for all calculations
        _expected.group1Reward = ga.generatedRewardByGroupId(
            verifyRound,
            bobGroup1.groupId
        );
        _expected.group2Reward = ga.generatedRewardByGroupId(
            verifyRound,
            bobGroup2.groupId
        );
        _expected.group3Reward = ga.generatedRewardByGroupId(
            verifyRound,
            aliceGroup.groupId
        );

        assertTrue(_expected.group1Reward > 0, "Group1 should have reward");
        assertTrue(_expected.group2Reward > 0, "Group2 should have reward");
        assertTrue(_expected.group3Reward > 0, "Group3 should have reward");

        // Calculate expected member rewards based on business rules
        // Group1: scores=[80,90,85], joinAmounts=[10,20,15]e18
        uint256[3] memory g1Scores = [uint256(80), uint256(90), uint256(85)];
        uint256[3] memory g1JoinAmounts = [
            uint256(10e18),
            uint256(20e18),
            uint256(15e18)
        ];
        uint256 g1TotalScore = 80 * 10e18 + 90 * 20e18 + 85 * 15e18;
        for (uint256 i = 0; i < 3; i++) {
            uint256 accountScore = g1Scores[i] * g1JoinAmounts[i];
            _expected.group1MemberRewards[i] =
                (_expected.group1Reward * accountScore) /
                g1TotalScore;
        }

        // Group2: scores=[75,95,88], joinAmounts=[25,30,12]e18
        uint256[3] memory g2Scores = [uint256(75), uint256(95), uint256(88)];
        uint256[3] memory g2JoinAmounts = [
            uint256(25e18),
            uint256(30e18),
            uint256(12e18)
        ];
        uint256 g2TotalScore = 75 * 25e18 + 95 * 30e18 + 88 * 12e18;
        for (uint256 i = 0; i < 3; i++) {
            uint256 accountScore = g2Scores[i] * g2JoinAmounts[i];
            _expected.group2MemberRewards[i] =
                (_expected.group2Reward * accountScore) /
                g2TotalScore;
        }

        // Group3: scores=[82,93,78], joinAmounts=[18,22,16]e18
        uint256[3] memory g3Scores = [uint256(82), uint256(93), uint256(78)];
        uint256[3] memory g3JoinAmounts = [
            uint256(18e18),
            uint256(22e18),
            uint256(16e18)
        ];
        uint256 g3TotalScore = 82 * 18e18 + 93 * 22e18 + 78 * 16e18;
        for (uint256 i = 0; i < 3; i++) {
            uint256 accountScore = g3Scores[i] * g3JoinAmounts[i];
            _expected.group3MemberRewards[i] =
                (_expected.group3Reward * accountScore) /
                g3TotalScore;
        }
    }

    // ============ Reward Verification Helpers ============

    function _verifyGroup1Rewards(
        ExtensionGroupAction ga,
        GroupUserParams[3] memory members,
        uint256 verifyRound
    ) internal {
        // Verify group reward matches expected
        uint256 groupReward = ga.generatedRewardByGroupId(
            verifyRound,
            bobGroup1.groupId
        );
        assertEq(
            groupReward,
            _expected.group1Reward,
            "Group1 reward matches expected"
        );

        for (uint256 i = 0; i < 3; i++) {
            // Verify claimed amount matches expected (calculated independently)
            uint256 claimed = h.group_action_claim_reward(
                members[i],
                bobGroup1,
                verifyRound
            );
            assertEq(
                claimed,
                _expected.group1MemberRewards[i],
                "G1 member claimed matches expected"
            );

            // Verify contract's view method matches expected (as additional check)
            (uint256 contractReward, ) = ga.rewardByAccount(
                verifyRound,
                members[i].flow.userAddress
            );
            assertEq(
                contractReward,
                _expected.group1MemberRewards[i],
                "G1 member contract view matches expected"
            );
        }
    }

    function _verifyGroup2Rewards(
        ExtensionGroupAction ga,
        GroupUserParams[3] memory members,
        uint256 verifyRound
    ) internal {
        // Verify group reward matches expected
        uint256 groupReward = ga.generatedRewardByGroupId(
            verifyRound,
            bobGroup2.groupId
        );
        assertEq(
            groupReward,
            _expected.group2Reward,
            "Group2 reward matches expected"
        );

        for (uint256 i = 0; i < 3; i++) {
            // Verify claimed amount matches expected (calculated independently)
            uint256 claimed = h.group_action_claim_reward(
                members[i],
                bobGroup2,
                verifyRound
            );
            assertEq(
                claimed,
                _expected.group2MemberRewards[i],
                "G2 member claimed matches expected"
            );

            // Verify contract's view method matches expected (as additional check)
            (uint256 contractReward, ) = ga.rewardByAccount(
                verifyRound,
                members[i].flow.userAddress
            );
            assertEq(
                contractReward,
                _expected.group2MemberRewards[i],
                "G2 member contract view matches expected"
            );
        }
    }

    function _verifyGroup3Rewards(
        ExtensionGroupAction ga,
        GroupUserParams[3] memory members,
        uint256 verifyRound
    ) internal {
        // Verify group reward matches expected
        uint256 groupReward = ga.generatedRewardByGroupId(
            verifyRound,
            aliceGroup.groupId
        );
        assertEq(
            groupReward,
            _expected.group3Reward,
            "Group3 reward matches expected"
        );

        for (uint256 i = 0; i < 3; i++) {
            // Verify claimed amount matches expected (calculated independently)
            uint256 claimed = h.group_action_claim_reward(
                members[i],
                aliceGroup,
                verifyRound
            );
            assertEq(
                claimed,
                _expected.group3MemberRewards[i],
                "G3 member claimed matches expected"
            );

            // Verify contract's view method matches expected (as additional check)
            (uint256 contractReward, ) = ga.rewardByAccount(
                verifyRound,
                members[i].flow.userAddress
            );
            assertEq(
                contractReward,
                _expected.group3MemberRewards[i],
                "G3 member contract view matches expected"
            );
        }
    }

    function _verifyBobTotalGroupRewards(
        ExtensionGroupAction ga,
        GroupUserParams[3] memory g1Members,
        GroupUserParams[3] memory g2Members,
        uint256 verifyRound
    ) internal {
        // Calculate expected sum of member rewards in both groups (from pre-calculated values)
        uint256 g1MembersTotal;
        uint256 g2MembersTotal;
        for (uint256 i = 0; i < 3; i++) {
            g1MembersTotal += _expected.group1MemberRewards[i];
            g2MembersTotal += _expected.group2MemberRewards[i];
        }

        // Verify group rewards match expected
        uint256 group1Reward = ga.generatedRewardByGroupId(
            verifyRound,
            bobGroup1.groupId
        );
        uint256 group2Reward = ga.generatedRewardByGroupId(
            verifyRound,
            bobGroup2.groupId
        );
        assertEq(
            group1Reward,
            _expected.group1Reward,
            "Group1 reward matches expected"
        );
        assertEq(
            group2Reward,
            _expected.group2Reward,
            "Group2 reward matches expected"
        );

        // Group rewards should equal sum of member rewards (minus rounding dust)
        assertTrue(
            group1Reward >= g1MembersTotal &&
                group1Reward - g1MembersTotal < 1e10,
            "G1 reward = sum of member rewards"
        );
        assertTrue(
            group2Reward >= g2MembersTotal &&
                group2Reward - g2MembersTotal < 1e10,
            "G2 reward = sum of member rewards"
        );

        // Verify bob's groups got non-trivial share (not 0% or 100%)
        uint256 bobTotalGroupReward = _expected.group1Reward +
            _expected.group2Reward;
        assertEq(
            ga.reward(verifyRound),
            _expected.totalReward,
            "Total reward matches expected"
        );
        assertTrue(
            bobTotalGroupReward > 0 &&
                bobTotalGroupReward < _expected.totalReward,
            "Bob's share is non-trivial"
        );

        // Log percentages for visibility
        uint256 bobPercent = (bobTotalGroupReward * 100) /
            _expected.totalReward;
        uint256 alicePercent = 100 - bobPercent;
        emit log_named_uint("Bob's groups reward %", bobPercent);
        emit log_named_uint("Alice's group reward %", alicePercent);
    }

    /// @notice Test that capacity reduction coefficient is 1e18 when within capacity
    function test_capacityReduction_NoReductionInNormalFlow() public {
        // Setup: Create extension and action
        address extensionAddr = h.group_action_create(bobGroup1);
        bobGroup1.groupActionAddress = extensionAddr;
        uint256 actionId = h.submit_group_action(bobGroup1);
        bobGroup1.flow.actionId = actionId;
        bobGroup1.groupActionId = actionId;

        // Both bob groups use same extension
        bobGroup2.groupActionAddress = extensionAddr;
        bobGroup2.flow.actionId = actionId;
        bobGroup2.groupActionId = actionId;

        // Vote
        h.vote(bobGroup1.flow);

        // Join phase
        h.next_phase();
        h.group_activate(bobGroup1);
        h.group_activate(bobGroup2);

        // Members join both groups
        GroupUserParams memory m1;
        m1.flow = member1();
        m1.joinAmount = 10e18;
        m1.groupActionAddress = extensionAddr;
        h.group_join(m1, bobGroup1);

        GroupUserParams memory m2;
        m2.flow = member2();
        m2.joinAmount = 15e18;
        m2.groupActionAddress = extensionAddr;
        h.group_join(m2, bobGroup2);

        // Verify phase
        h.next_phase();
        uint256 verifyRound = h.verifyContract().currentRound();

        // Submit scores for both groups
        uint256[] memory scores1 = new uint256[](1);
        scores1[0] = 100;
        h.group_submit_score(bobGroup1, scores1);

        uint256[] memory scores2 = new uint256[](1);
        scores2[0] = 100;
        h.group_submit_score(bobGroup2, scores2);

        // Verify capacity reduction coefficients
        // Both groups should have no reduction (1e18) since join amounts are small
        IGroupVerify groupVerifyContract2 = IGroupVerify(
            h.groupActionFactory().GROUP_VERIFY_ADDRESS()
        );
        uint256 reduction1 = groupVerifyContract2.capacityReductionByGroupId(
            bobGroup1.groupActionAddress,
            verifyRound,
            bobGroup1.groupId
        );
        uint256 reduction2 = groupVerifyContract2.capacityReductionByGroupId(
            bobGroup1.groupActionAddress,
            verifyRound,
            bobGroup2.groupId
        );

        assertEq(reduction1, 1e18, "Group1 should have no capacity reduction");
        assertEq(reduction2, 1e18, "Group2 should have no capacity reduction");

        // Verify group scores match joined amounts (no reduction applied)
        assertEq(
            groupVerifyContract2.groupScore(
                bobGroup1.groupActionAddress,
                verifyRound,
                bobGroup1.groupId
            ),
            10e18,
            "Group1 score should equal joined amount"
        );
        assertEq(
            groupVerifyContract2.groupScore(
                bobGroup1.groupActionAddress,
                verifyRound,
                bobGroup2.groupId
            ),
            15e18,
            "Group2 score should equal joined amount"
        );
    }
}
