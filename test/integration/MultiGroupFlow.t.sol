// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseGroupFlowTest} from "./base/BaseGroupFlowTest.sol";
import {GroupUserParams} from "./helper/TestGroupFlowHelper.sol";
import {
    LOVE20ExtensionGroupAction
} from "../../src/LOVE20ExtensionGroupAction.sol";

/// @title MultiGroupFlowTest
/// @notice Integration tests for multi-group and multi-member scenarios
contract MultiGroupFlowTest is BaseGroupFlowTest {
    /// @notice Test complex scenario: 3 groups (bob has 2, alice has 1), each with 3 members
    /// Verifies:
    /// 1. Reward distribution within each group (by score * joinAmount)
    /// 2. Reward distribution across groups (by core protocol score)
    /// 3. Total rewards for owner with multiple groups (bob)
    function test_multi_group_multi_member_flow() public {
        // === Setup Phase ===
        address extensionAddr = h.group_action_create(bob);

        // Submit action (bob submits since he created the extension)
        bob.groupActionAddress = extensionAddr;
        bob.groupActionId = h.submit_group_action(bob);
        bob.flow.actionId = bob.groupActionId;

        // All group owners reference same extension
        bob2.groupActionAddress = extensionAddr;
        bob2.flow.actionId = bob.groupActionId;
        bob2.groupActionId = bob.groupActionId;
        alice.groupActionAddress = extensionAddr;
        alice.flow.actionId = bob.groupActionId;
        alice.groupActionId = bob.groupActionId;

        // Vote - all owners vote for the action
        h.vote(bob.flow);
        h.vote(alice.flow);
        // Note: bob2 uses same address as bob, so only 2 votes

        // === Join Phase ===
        h.next_phase();

        // Activate groups (bob first to initialize, then others)
        h.group_activate(bob);
        h.group_activate_without_init(bob2);
        h.group_activate_without_init(alice);

        // Create member params and join groups
        GroupUserParams[3] memory g1Members = _setupGroup1Members(extensionAddr);
        GroupUserParams[3] memory g2Members = _setupGroup2Members(extensionAddr);
        GroupUserParams[3] memory g3Members = _setupGroup3Members(extensionAddr);

        // === Verify Phase ===
        h.next_phase();
        uint256 verifyRound = h.verifyContract().currentRound();

        // Each owner submits scores for their group members
        _submitGroup1Scores(g1Members);
        _submitGroup2Scores(g2Members);
        _submitGroup3Scores(g3Members);

        // Core protocol verification
        h.core_verify_extension(bob, extensionAddr);
        h.core_verify_extension(bob2, extensionAddr);
        h.core_verify_extension(alice, extensionAddr);

        // Verify state
        LOVE20ExtensionGroupAction ga = LOVE20ExtensionGroupAction(extensionAddr);
        assertEq(
            ga.verifiersCount(verifyRound),
            2,
            "2 unique verifiers (bob=bob2, alice)"
        );
        assertEq(ga.accountsByGroupIdCount(bob.groupId), 3, "Group1 has 3 members");
        assertEq(ga.accountsByGroupIdCount(bob2.groupId), 3, "Group2 has 3 members");
        assertEq(ga.accountsByGroupIdCount(alice.groupId), 3, "Group3 has 3 members");

        // === Claim Phase ===
        h.next_phase();

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
        address bobExtension = h.group_action_create(bob);
        bob.groupActionAddress = bobExtension;
        uint256 bobActionId = h.submit_group_action(bob);
        bob.flow.actionId = bobActionId;
        bob.groupActionId = bobActionId;

        // 2. Alice also uses same extension (share same action ID)
        alice.groupActionAddress = bobExtension;
        alice.flow.actionId = bobActionId;
        alice.groupActionId = bobActionId;

        // 3. Both vote for the action
        h.vote(bob.flow);
        h.vote(alice.flow);

        // 4. Move to join phase
        h.next_phase();
        h.group_activate(bob);
        h.group_activate_without_init(alice);

        // 5. Members join different groups
        GroupUserParams memory m1;
        m1.flow = member1;
        m1.joinAmount = 10e18;
        m1.groupActionAddress = bobExtension;
        h.group_join(m1, bob);

        GroupUserParams memory m2;
        m2.flow = member2;
        m2.joinAmount = 15e18;
        m2.groupActionAddress = bobExtension;
        h.group_join(m2, alice);

        // 6. Move to verify phase
        h.next_phase();

        // Both owners submit scores for their members
        address[] memory bobMembers = new address[](1);
        bobMembers[0] = member1.userAddress;
        uint256[] memory bobScores = new uint256[](1);
        bobScores[0] = 85;
        h.group_submit_score(bob, bobMembers, bobScores);

        address[] memory aliceMembers = new address[](1);
        aliceMembers[0] = member2.userAddress;
        uint256[] memory aliceScores = new uint256[](1);
        aliceScores[0] = 90;
        h.group_submit_score(alice, aliceMembers, aliceScores);

        // Verify both verifiers registered
        LOVE20ExtensionGroupAction groupAction = LOVE20ExtensionGroupAction(
            bobExtension
        );
        uint256 round = h.verifyContract().currentRound();
        assertEq(groupAction.verifiersCount(round), 2, "Verifiers count mismatch");
    }

    // ============ Setup Helpers ============

    function _setupGroup1Members(
        address extensionAddr
    ) internal returns (GroupUserParams[3] memory members) {
        // m1: join=10e18, score=80; m2: join=20e18, score=90; m3: join=15e18, score=85
        members[0].flow = member1;
        members[0].joinAmount = 10e18;
        members[0].groupActionAddress = extensionAddr;
        h.group_join(members[0], bob);

        members[1].flow = member2;
        members[1].joinAmount = 20e18;
        members[1].groupActionAddress = extensionAddr;
        h.group_join(members[1], bob);

        members[2].flow = member3;
        members[2].joinAmount = 15e18;
        members[2].groupActionAddress = extensionAddr;
        h.group_join(members[2], bob);
    }

    function _setupGroup2Members(
        address extensionAddr
    ) internal returns (GroupUserParams[3] memory members) {
        // m4: join=25e18, score=75; m5: join=30e18, score=95; m6: join=12e18, score=88
        members[0].flow = member4;
        members[0].joinAmount = 25e18;
        members[0].groupActionAddress = extensionAddr;
        h.group_join(members[0], bob2);

        members[1].flow = member5;
        members[1].joinAmount = 30e18;
        members[1].groupActionAddress = extensionAddr;
        h.group_join(members[1], bob2);

        members[2].flow = member6;
        members[2].joinAmount = 12e18;
        members[2].groupActionAddress = extensionAddr;
        h.group_join(members[2], bob2);
    }

    function _setupGroup3Members(
        address extensionAddr
    ) internal returns (GroupUserParams[3] memory members) {
        // m7: join=18e18, score=82; m8: join=22e18, score=93; m9: join=16e18, score=78
        members[0].flow = member7;
        members[0].joinAmount = 18e18;
        members[0].groupActionAddress = extensionAddr;
        h.group_join(members[0], alice);

        members[1].flow = member8;
        members[1].joinAmount = 22e18;
        members[1].groupActionAddress = extensionAddr;
        h.group_join(members[1], alice);

        members[2].flow = member9;
        members[2].joinAmount = 16e18;
        members[2].groupActionAddress = extensionAddr;
        h.group_join(members[2], alice);
    }

    // ============ Score Submission Helpers ============

    function _submitGroup1Scores(GroupUserParams[3] memory members) internal {
        address[] memory addrs = new address[](3);
        addrs[0] = members[0].flow.userAddress;
        addrs[1] = members[1].flow.userAddress;
        addrs[2] = members[2].flow.userAddress;
        uint256[] memory scores = new uint256[](3);
        scores[0] = 80;
        scores[1] = 90;
        scores[2] = 85;
        h.group_submit_score(bob, addrs, scores);
    }

    function _submitGroup2Scores(GroupUserParams[3] memory members) internal {
        address[] memory addrs = new address[](3);
        addrs[0] = members[0].flow.userAddress;
        addrs[1] = members[1].flow.userAddress;
        addrs[2] = members[2].flow.userAddress;
        uint256[] memory scores = new uint256[](3);
        scores[0] = 75;
        scores[1] = 95;
        scores[2] = 88;
        h.group_submit_score(bob2, addrs, scores);
    }

    function _submitGroup3Scores(GroupUserParams[3] memory members) internal {
        address[] memory addrs = new address[](3);
        addrs[0] = members[0].flow.userAddress;
        addrs[1] = members[1].flow.userAddress;
        addrs[2] = members[2].flow.userAddress;
        uint256[] memory scores = new uint256[](3);
        scores[0] = 82;
        scores[1] = 93;
        scores[2] = 78;
        h.group_submit_score(alice, addrs, scores);
    }

    // ============ Reward Verification Helpers ============

    function _verifyGroup1Rewards(
        LOVE20ExtensionGroupAction ga,
        GroupUserParams[3] memory members,
        uint256 verifyRound
    ) internal {
        // Group1: scores=[80,90,85], joinAmounts=[10,20,15]e18
        uint256[3] memory scores = [uint256(80), uint256(90), uint256(85)];
        uint256[3] memory joinAmounts = [uint256(10e18), uint256(20e18), uint256(15e18)];
        uint256 groupTotalScore = 80 * 10e18 + 90 * 20e18 + 85 * 15e18;

        uint256 groupReward = ga.generatedRewardByGroupId(verifyRound, bob.groupId);
        assertTrue(groupReward > 0, "Group1 should have reward");

        for (uint256 i = 0; i < 3; i++) {
            uint256 accountScore = scores[i] * joinAmounts[i];
            uint256 expectedReward = (groupReward * accountScore) / groupTotalScore;

            (uint256 contractReward, ) = ga.rewardByAccount(
                verifyRound,
                members[i].flow.userAddress
            );
            assertEq(contractReward, expectedReward, "G1 member reward match");

            uint256 claimed = h.group_action_claim_reward(members[i], bob, verifyRound);
            assertEq(claimed, expectedReward, "G1 claimed matches expected");
        }
    }

    function _verifyGroup2Rewards(
        LOVE20ExtensionGroupAction ga,
        GroupUserParams[3] memory members,
        uint256 verifyRound
    ) internal {
        // Group2: scores=[75,95,88], joinAmounts=[25,30,12]e18
        uint256[3] memory scores = [uint256(75), uint256(95), uint256(88)];
        uint256[3] memory joinAmounts = [uint256(25e18), uint256(30e18), uint256(12e18)];
        uint256 groupTotalScore = 75 * 25e18 + 95 * 30e18 + 88 * 12e18;

        uint256 groupReward = ga.generatedRewardByGroupId(verifyRound, bob2.groupId);
        assertTrue(groupReward > 0, "Group2 should have reward");

        for (uint256 i = 0; i < 3; i++) {
            uint256 accountScore = scores[i] * joinAmounts[i];
            uint256 expectedReward = (groupReward * accountScore) / groupTotalScore;

            (uint256 contractReward, ) = ga.rewardByAccount(
                verifyRound,
                members[i].flow.userAddress
            );
            assertEq(contractReward, expectedReward, "G2 member reward match");

            uint256 claimed = h.group_action_claim_reward(members[i], bob2, verifyRound);
            assertEq(claimed, expectedReward, "G2 claimed matches expected");
        }
    }

    function _verifyGroup3Rewards(
        LOVE20ExtensionGroupAction ga,
        GroupUserParams[3] memory members,
        uint256 verifyRound
    ) internal {
        // Group3: scores=[82,93,78], joinAmounts=[18,22,16]e18
        uint256[3] memory scores = [uint256(82), uint256(93), uint256(78)];
        uint256[3] memory joinAmounts = [uint256(18e18), uint256(22e18), uint256(16e18)];
        uint256 groupTotalScore = 82 * 18e18 + 93 * 22e18 + 78 * 16e18;

        uint256 groupReward = ga.generatedRewardByGroupId(verifyRound, alice.groupId);
        assertTrue(groupReward > 0, "Group3 should have reward");

        for (uint256 i = 0; i < 3; i++) {
            uint256 accountScore = scores[i] * joinAmounts[i];
            uint256 expectedReward = (groupReward * accountScore) / groupTotalScore;

            (uint256 contractReward, ) = ga.rewardByAccount(
                verifyRound,
                members[i].flow.userAddress
            );
            assertEq(contractReward, expectedReward, "G3 member reward match");

            uint256 claimed = h.group_action_claim_reward(members[i], alice, verifyRound);
            assertEq(claimed, expectedReward, "G3 claimed matches expected");
        }
    }

    function _verifyBobTotalGroupRewards(
        LOVE20ExtensionGroupAction ga,
        GroupUserParams[3] memory g1Members,
        GroupUserParams[3] memory g2Members,
        uint256 verifyRound
    ) internal {
        // Bob owns Group1 and Group2 (via bob2)
        uint256 group1Reward = ga.generatedRewardByGroupId(verifyRound, bob.groupId);
        uint256 group2Reward = ga.generatedRewardByGroupId(verifyRound, bob2.groupId);
        uint256 bobTotalGroupReward = group1Reward + group2Reward;

        // Calculate sum of member rewards in both groups
        uint256 g1MembersTotal;
        uint256 g2MembersTotal;

        for (uint256 i = 0; i < 3; i++) {
            (uint256 r, ) = ga.rewardByAccount(verifyRound, g1Members[i].flow.userAddress);
            g1MembersTotal += r;
        }

        for (uint256 i = 0; i < 3; i++) {
            (uint256 r, ) = ga.rewardByAccount(verifyRound, g2Members[i].flow.userAddress);
            g2MembersTotal += r;
        }

        // Group rewards should equal sum of member rewards (minus rounding dust)
        assertTrue(
            group1Reward >= g1MembersTotal && group1Reward - g1MembersTotal < 1e10,
            "G1 reward = sum of member rewards"
        );
        assertTrue(
            group2Reward >= g2MembersTotal && group2Reward - g2MembersTotal < 1e10,
            "G2 reward = sum of member rewards"
        );

        // Verify bob's groups got non-trivial share (not 0% or 100%)
        uint256 totalExtensionReward = ga.reward(verifyRound);
        assertTrue(
            bobTotalGroupReward > 0 && bobTotalGroupReward < totalExtensionReward,
            "Bob's share is non-trivial"
        );

        // Log percentages for visibility
        uint256 bobPercent = (bobTotalGroupReward * 100) / totalExtensionReward;
        uint256 alicePercent = 100 - bobPercent;
        emit log_named_uint("Bob's groups reward %", bobPercent);
        emit log_named_uint("Alice's group reward %", alicePercent);
    }
}

