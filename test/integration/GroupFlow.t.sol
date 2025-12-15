// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    TestGroupFlowHelper,
    GroupUserParams,
    FlowUserParams
} from "./helper/TestGroupFlowHelper.sol";
import {FIRST_PARENT_TOKEN_FUNDRAISING_GOAL} from "@core-test/Constant.sol";
import {
    LOVE20ExtensionGroupAction
} from "../../src/LOVE20ExtensionGroupAction.sol";
import {
    LOVE20ExtensionGroupService
} from "../../src/LOVE20ExtensionGroupService.sol";

/// @title GroupFlowTest
/// @notice Integration tests for Group Action and Group Service extensions using REAL contracts
contract GroupFlowTest is Test {
    TestGroupFlowHelper public h;

    // Test users - Group owners
    GroupUserParams public bob;
    GroupUserParams public alice;

    // Regular flow users (for members)
    FlowUserParams public member1;
    FlowUserParams public member2;
    FlowUserParams public member3;

    function setUp() public virtual {
        h = new TestGroupFlowHelper();

        // Complete launch phase first (required for real contracts)
        _finishLaunch();

        // Create group owners - they need to stake first to have gov votes
        bob = _createAndPrepareGroupUser("bob", "BobsGroup");
        alice = _createAndPrepareGroupUser("alice", "AlicesGroup");

        // Create regular members (no need for staking)
        member1 = h.createUser(
            "member1",
            h.firstTokenAddress(),
            FIRST_PARENT_TOKEN_FUNDRAISING_GOAL / 10
        );
        member2 = h.createUser(
            "member2",
            h.firstTokenAddress(),
            FIRST_PARENT_TOKEN_FUNDRAISING_GOAL / 10
        );
        member3 = h.createUser(
            "member3",
            h.firstTokenAddress(),
            FIRST_PARENT_TOKEN_FUNDRAISING_GOAL / 10
        );
    }

    function _finishLaunch() internal {
        // Create two temp users to complete launch
        FlowUserParams memory launcher1 = h.createUser(
            "launcher1",
            h.firstTokenAddress(),
            FIRST_PARENT_TOKEN_FUNDRAISING_GOAL
        );
        FlowUserParams memory launcher2 = h.createUser(
            "launcher2",
            h.firstTokenAddress(),
            FIRST_PARENT_TOKEN_FUNDRAISING_GOAL
        );

        h.launch_contribute(launcher1);
        h.jump_second_half_min();
        h.launch_contribute(launcher2);
        h.launch_skip_claim_delay();
        h.launch_claim(launcher1);
        h.launch_claim(launcher2);
    }

    function _createAndPrepareGroupUser(
        string memory userName,
        string memory groupName
    ) internal returns (GroupUserParams memory user) {
        // Create user with parent tokens
        user = h.createGroupUser(
            userName,
            h.firstTokenAddress(),
            FIRST_PARENT_TOKEN_FUNDRAISING_GOAL,
            groupName
        );

        // User needs to have child tokens for staking
        // Mint tokens to user (using forceMint through minter)
        uint256 tokenAmount = 1_000_000_000 ether; // 1 billion tokens
        h.forceMint(h.firstTokenAddress(), user.flow.userAddress, tokenAmount);

        // Stake liquidity and token to get gov votes (required for group operations)
        h.stake_liquidity(user.flow);
        h.stake_token(user.flow);

        return user;
    }

    // ============ Full Group Action Flow Tests ============

    /// @notice Test complete group action flow: create → submit → vote → activate → join → score
    function test_full_group_action_flow() public {
        // 1. Create group action extension
        address extensionAddr = h.group_action_create(bob);
        bob.groupActionAddress = extensionAddr;

        // 2. Submit action with extension
        uint256 actionId = h.submit_group_action(bob);
        bob.flow.actionId = actionId;
        bob.groupActionId = actionId;

        // 3. Vote for the action
        h.vote(bob.flow);

        // 4. Move to join phase and activate group
        h.next_phase();
        h.group_activate(bob);

        // 5. Members join the group
        GroupUserParams memory m1;
        m1.flow = member1;
        m1.joinAmount = 10e18;
        m1.groupActionAddress = bob.groupActionAddress;
        h.group_join(m1, bob);

        GroupUserParams memory m2;
        m2.flow = member2;
        m2.joinAmount = 20e18;
        m2.groupActionAddress = bob.groupActionAddress;
        h.group_join(m2, bob);

        // 6. Move to verify phase and submit scores
        h.next_phase();

        address[] memory members = new address[](2);
        members[0] = member1.userAddress;
        members[1] = member2.userAddress;

        uint256[] memory scores = new uint256[](2);
        scores[0] = 80;
        scores[1] = 90;

        h.group_submit_score(bob, members, scores);

        // Verify final state
        LOVE20ExtensionGroupAction groupAction = LOVE20ExtensionGroupAction(
            bob.groupActionAddress
        );
        assertEq(
            groupAction.totalJoinedAmount(),
            m1.joinAmount + m2.joinAmount,
            "Total joined amount mismatch"
        );
        assertEq(
            groupAction.accountsByGroupIdCount(bob.groupId),
            2,
            "Member count mismatch"
        );
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

        // 4. Move to join phase - Bob activates first (which initializes extension)
        h.next_phase();
        h.group_activate(bob);

        // Alice activates her group (extension already initialized)
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
        assertEq(
            groupAction.verifiersCount(round),
            2,
            "Verifiers count mismatch"
        );
    }

    /// @notice Test group expansion
    function test_group_expansion() public {
        // 1. Setup group action with lower initial stake to allow expansion
        address extensionAddr = h.group_action_create(bob);
        bob.groupActionAddress = extensionAddr;
        uint256 actionId = h.submit_group_action(bob);
        bob.flow.actionId = actionId;
        bob.groupActionId = actionId;

        h.vote(bob.flow);
        h.next_phase();

        // Use moderate stake for activation to leave room for expansion (50M tokens)
        bob.stakeAmount = 50_000_000e18;
        h.group_activate(bob);

        // 2. Get initial capacity
        (, , uint256 initialStaked, uint256 initialCapacity, , , , , , ) = h
            .getGroupManager()
            .groupInfo(h.firstTokenAddress(), actionId, bob.groupId);

        // 3. Expand the group with small amount (10M tokens)
        uint256 additionalStake = 10_000_000e18;
        h.group_expand(bob, additionalStake);

        // 4. Verify expansion
        (, , uint256 newStaked, uint256 newCapacity, , , , , , ) = h
            .getGroupManager()
            .groupInfo(h.firstTokenAddress(), actionId, bob.groupId);

        assertEq(
            newStaked,
            initialStaked + additionalStake,
            "Staked amount mismatch"
        );
        assertTrue(newCapacity >= initialCapacity, "Capacity should increase");
    }

    /// @notice Test group deactivation
    function test_group_deactivation() public {
        // 1. Setup group action
        address extensionAddr = h.group_action_create(bob);
        bob.groupActionAddress = extensionAddr;
        uint256 actionId = h.submit_group_action(bob);
        bob.flow.actionId = actionId;
        bob.groupActionId = actionId;

        h.vote(bob.flow);
        h.next_phase();
        h.group_activate(bob);

        assertTrue(
            h.getGroupManager().isGroupActive(
                h.firstTokenAddress(),
                actionId,
                bob.groupId
            ),
            "Group should be active"
        );

        // 2. Deactivate (need to advance round first)
        h.next_phase();
        h.group_deactivate(bob);

        // 3. Verify deactivation
        assertFalse(
            h.getGroupManager().isGroupActive(
                h.firstTokenAddress(),
                actionId,
                bob.groupId
            ),
            "Group should be deactivated"
        );
    }

    // ============ Cross-Round Tests ============

    /// @notice Test behavior across multiple rounds
    function test_cross_round_behavior() public {
        // 1. Setup group action
        address extensionAddr = h.group_action_create(bob);
        bob.groupActionAddress = extensionAddr;
        uint256 actionId = h.submit_group_action(bob);
        bob.flow.actionId = actionId;
        bob.groupActionId = actionId;

        h.vote(bob.flow);
        h.next_phase();
        h.group_activate(bob);

        // 2. Member joins
        GroupUserParams memory m1;
        m1.flow = member1;
        m1.joinAmount = 10e18;
        m1.groupActionAddress = bob.groupActionAddress;
        h.group_join(m1, bob);

        // 3. Round 1: Submit scores
        h.next_phase();
        uint256 round1 = h.verifyContract().currentRound();

        address[] memory members = new address[](1);
        members[0] = member1.userAddress;
        uint256[] memory scores1 = new uint256[](1);
        scores1[0] = 80;
        h.group_submit_score(bob, members, scores1);

        LOVE20ExtensionGroupAction groupAction = LOVE20ExtensionGroupAction(
            extensionAddr
        );

        // Verify round 1 score
        assertEq(
            groupAction.originScoreByAccount(round1, member1.userAddress),
            80,
            "Round 1 score mismatch"
        );

        // 4. Advance to next rounds
        h.next_phases(3);
        uint256 round2 = h.verifyContract().currentRound();

        // 5. Submit different scores in round 2
        uint256[] memory scores2 = new uint256[](1);
        scores2[0] = 90;
        h.group_submit_score(bob, members, scores2);

        // 6. Verify scores are round-specific
        assertEq(
            groupAction.originScoreByAccount(round1, member1.userAddress),
            80,
            "Round 1 score should remain 80"
        );
        assertEq(
            groupAction.originScoreByAccount(round2, member1.userAddress),
            90,
            "Round 2 score should be 90"
        );
    }

    // ============ Edge Cases ============

    /// @notice Test member exit and rejoin
    function test_member_exit_and_rejoin() public {
        // 1. Setup
        address extensionAddr = h.group_action_create(bob);
        bob.groupActionAddress = extensionAddr;
        uint256 actionId = h.submit_group_action(bob);
        bob.flow.actionId = actionId;
        bob.groupActionId = actionId;

        h.vote(bob.flow);
        h.next_phase();
        h.group_activate(bob);

        // 2. Member joins
        GroupUserParams memory m1;
        m1.flow = member1;
        m1.joinAmount = 10e18;
        m1.groupActionAddress = bob.groupActionAddress;
        h.group_join(m1, bob);

        LOVE20ExtensionGroupAction groupAction = LOVE20ExtensionGroupAction(
            extensionAddr
        );

        // Verify joined
        (uint256 joinedRound, , ) = groupAction.joinInfo(member1.userAddress);
        assertTrue(joinedRound > 0, "Should be joined");

        // 3. Member exits
        h.group_exit(m1, bob);

        // Verify exited
        (joinedRound, , ) = groupAction.joinInfo(member1.userAddress);
        assertEq(joinedRound, 0, "Should not be joined after exit");

        // 4. Member rejoins with different amount
        m1.joinAmount = 15e18;
        h.group_join(m1, bob);

        // Verify rejoined
        uint256 amount;
        (joinedRound, amount, ) = groupAction.joinInfo(member1.userAddress);
        assertTrue(joinedRound > 0, "Should be joined after rejoin");
        assertEq(amount, 15e18, "Amount should be 15e18");
    }

    /// @notice Test IExtensionJoinedValue interface
    function test_joined_value_calculation() public {
        // 1. Setup
        address extensionAddr = h.group_action_create(bob);
        bob.groupActionAddress = extensionAddr;
        uint256 actionId = h.submit_group_action(bob);
        bob.flow.actionId = actionId;
        bob.groupActionId = actionId;

        h.vote(bob.flow);
        h.next_phase();
        h.group_activate(bob);

        LOVE20ExtensionGroupAction groupAction = LOVE20ExtensionGroupAction(
            extensionAddr
        );

        // Initial joined value should be 0
        assertEq(
            groupAction.joinedValue(),
            0,
            "Initial joined value should be 0"
        );

        // 2. Members join
        GroupUserParams memory m1;
        m1.flow = member1;
        m1.joinAmount = 10e18;
        m1.groupActionAddress = bob.groupActionAddress;
        h.group_join(m1, bob);

        GroupUserParams memory m2;
        m2.flow = member2;
        m2.joinAmount = 20e18;
        m2.groupActionAddress = bob.groupActionAddress;
        h.group_join(m2, bob);

        // 3. Verify joined values
        assertEq(
            groupAction.joinedValue(),
            30e18,
            "Total joined value mismatch"
        );
        assertEq(
            groupAction.joinedValueByAccount(member1.userAddress),
            10e18,
            "Member1 joined value mismatch"
        );
        assertEq(
            groupAction.joinedValueByAccount(member2.userAddress),
            20e18,
            "Member2 joined value mismatch"
        );
        assertFalse(
            groupAction.isJoinedValueCalculated(),
            "Should not be calculated"
        );
    }
}
