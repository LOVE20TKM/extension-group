// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "./utils/BaseGroupTest.sol";
import {ExtensionGroupAction} from "../src/ExtensionGroupAction.sol";
import {GroupManager} from "../src/GroupManager.sol";
import {IGroupManager} from "../src/interface/IGroupManager.sol";
import {IGroupJoin} from "../src/interface/IGroupJoin.sol";
import {IGroupVerify} from "../src/interface/IGroupVerify.sol";
import {MAX_ORIGIN_SCORE} from "../src/interface/IGroupVerify.sol";
import {MockUniswapV2Pair} from "@extension/test/mocks/MockUniswapV2Pair.sol";

/**
 * @title ExtensionGroupActionTest
 * @notice End-to-end test suite for ExtensionGroupAction
 */
contract ExtensionGroupActionTest is BaseGroupTest {
    ExtensionGroupAction public groupAction;

    uint256 public groupId1;
    uint256 public groupId2;

    function _groupStakedAmount(
        uint256 groupId
    ) internal view returns (uint256) {
        (bool ok, bytes memory data) = address(groupManager).staticcall(
            abi.encodeWithSelector(
                IGroupManager.groupInfo.selector,
                address(groupAction),
                groupId
            )
        );
        require(ok, "groupInfo call failed");
        uint256 v;
        // stakedAmount is word 2 in the ABI head
        assembly {
            v := mload(add(data, 0x60))
        }
        return v;
    }

    function _minJoinAmount(uint256 groupId) internal view returns (uint256) {
        (bool ok, bytes memory data) = address(groupManager).staticcall(
            abi.encodeWithSelector(
                IGroupManager.groupInfo.selector,
                address(groupAction),
                groupId
            )
        );
        require(ok, "groupInfo call failed");
        uint256 v;
        // minJoinAmount is word 3 in the ABI head (after capacity removed)
        assembly {
            v := mload(add(data, 0x80))
        }
        return v;
    }

    function _maxJoinAmount(uint256 groupId) internal view returns (uint256) {
        (bool ok, bytes memory data) = address(groupManager).staticcall(
            abi.encodeWithSelector(
                IGroupManager.groupInfo.selector,
                address(groupAction),
                groupId
            )
        );
        require(ok, "groupInfo call failed");
        uint256 v;
        // maxJoinAmount is word 4 in the ABI head (after capacity removed)
        assembly {
            v := mload(add(data, 0xa0))
        }
        return v;
    }

    function _groupDescription(
        uint256 groupId
    ) internal view returns (string memory s) {
        (bool ok, bytes memory data) = address(groupManager).staticcall(
            abi.encodeWithSelector(
                IGroupManager.groupInfo.selector,
                address(groupAction),
                groupId
            )
        );
        require(ok, "groupInfo call failed");

        uint256 offset;
        assembly {
            // slot 1 holds the offset to the string data (relative to start of return data)
            offset := mload(add(data, 0x40))
        }
        // ABI string at (data + 0x20 + offset): [len][bytes...]
        assembly {
            s := add(add(data, 0x20), offset)
        }
    }

    function setUp() public {
        setUpBase();

        // Deploy the actual GroupAction contract using mockGroupActionFactory
        groupAction = new ExtensionGroupAction(
            address(mockGroupActionFactory),
            address(token),
            address(token), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        // Register extension in mockGroupActionFactory (not mockFactory)
        // because groupAction.factory() returns mockGroupActionFactory
        token.mint(address(this), 1e18);
        token.approve(address(mockGroupActionFactory), type(uint256).max);
        mockGroupActionFactory.registerExtensionForTesting(
            address(groupAction),
            address(token)
        );

        // Setup group owners
        groupId1 = setupGroupOwner(groupOwner1, 10000e18, "TestGroup1");
        groupId2 = setupGroupOwner(groupOwner2, 10000e18, "TestGroup2");

        // Prepare extension init (config already set in GroupCore constructor)
        prepareExtensionInit(address(groupAction), address(token), ACTION_ID);

        // Activate groups (through GroupManager directly)
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );
        setupUser(
            groupOwner2,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(groupAction),
            groupId1,
            "Group1",
            0, // maxCapacity (0 = use owner's theoretical max)
            1e18, // minJoinAmount
            0,
            0
        );

        vm.prank(groupOwner2, groupOwner2);
        groupManager.activateGroup(
            address(groupAction),
            groupId2,
            "Group2",
            0, // maxCapacity (0 = use owner's theoretical max)
            1e18, // minJoinAmount
            0,
            0
        );
    }

    // ============ Integration Tests ============

    function test_FullLifecycle() public {
        // 1. Users join groups
        uint256 joinAmount1 = 10e18;
        uint256 joinAmount2 = 20e18;
        setupUser(user1, joinAmount1, address(groupJoin));
        setupUser(user2, joinAmount2, address(groupJoin));

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount1,
            new string[](0)
        );

        vm.prank(user2);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount2,
            new string[](0)
        );

        // Verify join state
        assertEq(
            groupJoin.joinedAmount(address(groupAction)),
            joinAmount1 + joinAmount2
        );
        assertEq(
            groupJoin.accountsByGroupIdCount(address(groupAction), groupId1),
            2
        );

        // 2. Submit scores
        uint256[] memory scores = new uint256[](2);
        scores[0] = 80;
        scores[1] = 90;

        vm.prank(groupOwner1);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            0,
            scores
        );

        // 3. Verify scores
        uint256 round = verify.currentRound();
        assertEq(
            groupVerify.originScoreByAccount(
                address(groupAction),
                round,
                user1
            ),
            80
        );
        assertEq(
            groupVerify.originScoreByAccount(
                address(groupAction),
                round,
                user2
            ),
            90
        );

        // 4. User exits
        vm.prank(user1);
        groupJoin.exit(address(groupAction));

        assertEq(groupJoin.joinedAmount(address(groupAction)), joinAmount2);
        assertEq(
            groupJoin.accountsByGroupIdCount(address(groupAction), groupId1),
            1
        );
    }

    function test_GroupActivationAndDeactivation() public {
        assertTrue(groupManager.isGroupActive(address(groupAction), groupId1));

        advanceRound();
        // Setup actionIds for new round
        uint256 round = verify.currentRound();
        vote.setVotedActionIds(address(token), round, ACTION_ID);
        // Set votes for this round
        vote.setVotesNum(address(token), round, 10000e18);
        vote.setVotesNumByActionId(address(token), round, ACTION_ID, 10000e18);

        vm.prank(groupOwner1, groupOwner1);
        groupManager.deactivateGroup(address(groupAction), groupId1);

        assertFalse(groupManager.isGroupActive(address(groupAction), groupId1));

        // Cannot join deactivated group
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));

        vm.prank(user1);
        vm.expectRevert(IGroupJoin.CannotJoinDeactivatedGroup.selector);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );
    }

    function test_DelegatedVerification() public {
        address delegate = address(0x123);

        vm.prank(groupOwner1);
        groupVerify.setGroupDelegate(address(groupAction), groupId1, delegate);

        // User joins
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // Delegated verifier can submit scores
        uint256[] memory scores = new uint256[](1);
        scores[0] = 85;

        vm.prank(delegate);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            0,
            scores
        );

        uint256 round = verify.currentRound();
        assertEq(
            groupVerify.originScoreByAccount(
                address(groupAction),
                round,
                user1
            ),
            85
        );
    }

    function test_DistrustVoting() public {
        // Setup group with member
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.prank(groupOwner1);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            0,
            scores
        );

        // Setup governor
        address governor = address(0x50);
        setupVerifyVotes(governor, ACTION_ID, address(groupAction), 100e18);

        uint256 round = verify.currentRound();
        uint256 scoreBefore = groupVerify.groupScore(
            address(groupAction),
            round,
            groupId1
        );

        // Cast distrust vote
        vm.prank(governor, governor);
        groupVerify.distrustVote(
            address(groupAction),
            groupOwner1,
            50e18,
            "Bad behavior"
        );

        uint256 scoreAfter = groupVerify.groupScore(
            address(groupAction),
            round,
            groupId1
        );
        assertTrue(scoreAfter < scoreBefore);
    }

    function test_MultipleGroupsWithDifferentOwners() public {
        // Both groups have members
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));
        setupUser(user2, joinAmount, address(groupJoin));

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        vm.prank(user2);
        groupJoin.join(
            address(groupAction),
            groupId2,
            joinAmount,
            new string[](0)
        );

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.prank(groupOwner1);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            0,
            scores
        );

        vm.prank(groupOwner2);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId2,
            0,
            scores
        );

        uint256 round = verify.currentRound();
        assertEq(groupVerify.verifiersCount(address(groupAction), round), 2);
    }

    // ============ IExtensionJoinedAmount Tests ============

    function test_JoinedAmount() public {
        uint256 joinAmount1 = 10e18;
        uint256 joinAmount2 = 20e18;
        setupUser(user1, joinAmount1, address(groupJoin));
        setupUser(user2, joinAmount2, address(groupJoin));

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount1,
            new string[](0)
        );

        vm.prank(user2);
        groupJoin.join(
            address(groupAction),
            groupId2,
            joinAmount2,
            new string[](0)
        );

        assertEq(groupAction.joinedAmount(), joinAmount1 + joinAmount2);
    }

    function test_JoinedAmountByAccount() public {
        uint256 joinAmount = 15e18;
        setupUser(user1, joinAmount, address(groupJoin));

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        assertEq(groupAction.joinedAmountByAccount(user1), joinAmount);
        assertEq(groupAction.joinedAmountByAccount(user2), 0);
    }

    // ============ Reward Functions Tests ============

    function test_ImplementsGroupInterfaces() public view {
        // Contract should properly implement the interfaces
        assertTrue(
            groupVerify.canVerify(address(groupAction), groupOwner1, groupId1)
        );
        assertFalse(
            groupVerify.canVerify(address(groupAction), user1, groupId1)
        );
    }

    // ============ Edge Cases ============

    function test_JoinThenExitThenRejoin() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount * 2, address(groupJoin));

        // First join
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        assertEq(groupJoin.joinedAmount(address(groupAction)), joinAmount);

        // Exit
        vm.prank(user1);
        groupJoin.exit(address(groupAction));

        assertEq(groupJoin.joinedAmount(address(groupAction)), 0);

        // Rejoin (possibly different group)
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId2,
            joinAmount,
            new string[](0)
        );

        assertEq(groupJoin.joinedAmount(address(groupAction)), joinAmount);
        (, , uint256 groupId) = groupJoin.joinInfo(address(groupAction), user1);
        assertEq(groupId, groupId2);
    }

    function test_ScoreWithZeroAmount() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        uint256[] memory scores = new uint256[](1);
        scores[0] = 0;

        vm.prank(groupOwner1);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            0,
            scores
        );

        uint256 round = verify.currentRound();
        assertEq(
            groupVerify.accountScore(address(groupAction), round, user1),
            0
        );
    }

    function test_MaxScore() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        uint256[] memory scores = new uint256[](1);
        scores[0] = MAX_ORIGIN_SCORE;

        vm.prank(groupOwner1);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            0,
            scores
        );

        uint256 round = verify.currentRound();
        assertEq(
            groupVerify.originScoreByAccount(
                address(groupAction),
                round,
                user1
            ),
            MAX_ORIGIN_SCORE
        );
    }

    function test_UpdateGroupInfo() public {
        string memory newDescription = "Updated description";
        uint256 newMin = 5e18;
        uint256 newMax = 50e18;

        vm.prank(groupOwner1, groupOwner1);
        groupManager.updateGroupInfo(
            address(groupAction),
            groupId1,
            newDescription,
            0, // newMaxCapacity
            newMin,
            newMax,
            0
        );

        string memory description = _groupDescription(groupId1);
        uint256 minJoin = _minJoinAmount(groupId1);
        uint256 maxJoin = _maxJoinAmount(groupId1);
        assertEq(description, newDescription);
        assertEq(minJoin, newMin);
        assertEq(maxJoin, newMax);
    }

    // ============ Verifier Capacity Tests ============

    function test_VerifierCapacityLimit() public {
        // Test that verifier capacity is limited by governance votes

        // Get max verify capacity for owner
        uint256 maxCapacity = groupManager.maxVerifyCapacityByOwner(
            address(groupAction),
            groupOwner1
        );
        uint256 maxPerAccount = groupManager.maxJoinAmount(
            address(groupAction)
        );
        assertTrue(maxCapacity > 0, "maxCapacity should be > 0");
        assertTrue(maxPerAccount > 0, "maxPerAccount should be > 0");

        // Use a small amount that's within limits (1e18 is the minStake from submit)
        uint256 joinAmount = 1e18;

        // Have users join group
        setupUser(user1, joinAmount, address(groupJoin));

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // Verify join was successful
        assertEq(
            groupJoin.accountsByGroupIdCount(address(groupAction), groupId1),
            1
        );

        // Capacity check is done during submitOriginScores, so let's test that path
        advanceRound();
        uint256 round = verify.currentRound();
        vote.setVotedActionIds(address(token), round, ACTION_ID);
        // Set votes for this round
        vote.setVotesNum(address(token), round, 10000e18);
        vote.setVotesNumByActionId(address(token), round, ACTION_ID, 10000e18);

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        // This should succeed since we're within capacity
        vm.prank(groupOwner1);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            0,
            scores
        );

        assertEq(groupVerify.verifiersCount(address(groupAction), round), 1);
    }

    // ============ Cross-Round Tests ============

    function test_CrossRoundBehavior() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));

        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );

        // Advance round to get fresh snapshot for round 1
        advanceRound();
        uint256 round1 = verify.currentRound();

        // Submit scores in round 1
        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.prank(groupOwner1);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            0,
            scores
        );

        // Advance round
        advanceRound();
        uint256 round2 = verify.currentRound();

        // Scores should be specific to round
        assertEq(
            groupVerify.originScoreByAccount(
                address(groupAction),
                round1,
                user1
            ),
            80
        );
        assertEq(
            groupVerify.originScoreByAccount(
                address(groupAction),
                round2,
                user1
            ),
            0
        );

        // Submit scores in round 2
        uint256[] memory scores2 = new uint256[](1);
        scores2[0] = 90;

        vm.prank(groupOwner1);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            0,
            scores2
        );

        assertEq(
            groupVerify.originScoreByAccount(
                address(groupAction),
                round2,
                user1
            ),
            90
        );
    }

    function test_MaxAccounts_ZeroMeansNoLimit() public {
        // Setup: Create a new group with maxAccounts = 0 (no limit)
        uint256 groupId3 = setupGroupOwner(groupOwner1, 10000e18, "TestGroup3");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(groupAction),
            groupId3,
            "Group3",
            0, // maxCapacity
            1e18, // minJoinAmount
            0, // maxJoinAmount (no limit)
            0 // maxAccounts (0 = no limit)
        );

        // Verify maxAccounts is 0
        (, , , , , uint256 maxAccounts, , , ) = groupManager.groupInfo(
            address(groupAction),
            groupId3
        );
        assertEq(maxAccounts, 0, "maxAccounts should be 0");

        // Join multiple users (more than would normally be allowed if there was a limit)
        // Test with 10 users to ensure no limit is enforced
        address[] memory users = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            users[i] = address(uint160(0x1000 + i));
            setupUser(users[i], 10e18, address(groupJoin));

            vm.prank(users[i]);
            groupJoin.join(
                address(groupAction),
                groupId3,
                10e18,
                new string[](0)
            );
        }

        // Verify all users joined successfully
        uint256 accountCount = groupJoin.accountsByGroupIdByRoundCount(
            address(groupAction),
            verify.currentRound(),
            groupId3
        );
        assertEq(accountCount, 10, "All 10 users should have joined");

        // Verify no GroupAccountsFull error occurred
        assertTrue(
            groupManager.isGroupActive(address(groupAction), groupId3),
            "Group should still be active"
        );
    }

    function test_MaxAccounts_NonZeroEnforcesLimit() public {
        // Setup: Create a new group with maxAccounts = 3
        uint256 groupId4 = setupGroupOwner(groupOwner1, 10000e18, "TestGroup4");
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(groupAction),
            groupId4,
            "Group4",
            0, // maxCapacity
            1e18, // minJoinAmount
            0, // maxJoinAmount (no limit)
            3 // maxAccounts = 3
        );

        // Verify maxAccounts is 3
        (, , , , , uint256 maxAccounts, , , ) = groupManager.groupInfo(
            address(groupAction),
            groupId4
        );
        assertEq(maxAccounts, 3, "maxAccounts should be 3");

        // Join 3 users (should succeed)
        address[] memory users = new address[](3);
        for (uint256 i = 0; i < 3; i++) {
            users[i] = address(uint160(0x2000 + i));
            setupUser(users[i], 10e18, address(groupJoin));

            vm.prank(users[i]);
            groupJoin.join(
                address(groupAction),
                groupId4,
                10e18,
                new string[](0)
            );
        }

        // Verify 3 users joined
        uint256 accountCount = groupJoin.accountsByGroupIdByRoundCount(
            address(groupAction),
            verify.currentRound(),
            groupId4
        );
        assertEq(accountCount, 3, "3 users should have joined");

        // Try to join a 4th user (should fail)
        address user4 = address(0x2003);
        setupUser(user4, 10e18, address(groupJoin));

        vm.prank(user4);
        vm.expectRevert(IGroupJoin.GroupAccountsFull.selector);
        groupJoin.join(
            address(groupAction),
            groupId4,
            10e18,
            new string[](0)
        );
    }
}

/**
 * @title ExtensionGroupActionJoinTokenTest
 * @notice Tests for joinTokenAddress validation and LP token conversion
 */
contract ExtensionGroupActionJoinTokenTest is BaseGroupTest {
    MockUniswapV2Pair public lpToken;

    function setUp() public {
        setUpBase();

        // Create LP token containing token
        lpToken = new MockUniswapV2Pair(address(token), address(0x999));
        lpToken.setReserves(1000e18, 500e18); // 1000 token, 500 other
        lpToken.mint(address(this), 100e18); // LP total supply
    }

    function test_InvalidJoinToken_NotLPToken() public {
        // Using random address that's not an LP token
        address invalidToken = address(0x123);

        vm.expectRevert(); // Low-level call to non-contract returns no data
        new ExtensionGroupAction(
            address(mockGroupActionFactory),
            address(token),
            invalidToken, // invalid joinToken
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );
    }

    function test_InvalidJoinToken_LPNotContainingToken() public {
        // Create LP with neither token being tokenAddress
        MockUniswapV2Pair badLp = new MockUniswapV2Pair(
            address(0x111),
            address(0x222)
        );

        vm.expectRevert(IGroupJoin.InvalidJoinTokenAddress.selector);
        new ExtensionGroupAction(
            address(mockGroupActionFactory),
            address(token),
            address(badLp), // LP doesn't contain token
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );
    }

    function test_ValidJoinToken_TokenItself() public {
        // Should not revert
        ExtensionGroupAction action = new ExtensionGroupAction(
            address(mockGroupActionFactory),
            address(token),
            address(token), // joinToken = token
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        // Register extension to get actionId
        token.mint(address(this), 1e18);
        token.approve(address(mockFactory), type(uint256).max);
        mockFactory.registerExtension(address(action), address(token));
        prepareExtensionInit(address(action), address(token), ACTION_ID);

        // Get joinTokenAddress from extension config
        address joinTokenAddress = action.JOIN_TOKEN_ADDRESS();
        assertEq(joinTokenAddress, address(token));
        assertEq(
            action.TOKEN_ADDRESS(),
            address(token),
            "tokenAddress mismatch"
        );
    }

    function test_ValidJoinToken_LPContainingToken() public {
        // Should not revert
        ExtensionGroupAction action = new ExtensionGroupAction(
            address(mockGroupActionFactory),
            address(token),
            address(lpToken), // LP containing token
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        // Register extension to get actionId
        token.mint(address(this), 1e18);
        token.approve(address(mockFactory), type(uint256).max);
        mockFactory.registerExtension(address(action), address(token));
        prepareExtensionInit(address(action), address(token), ACTION_ID);

        // Get joinTokenAddress from extension config
        address joinTokenAddress = action.JOIN_TOKEN_ADDRESS();
        assertEq(joinTokenAddress, address(lpToken));
    }

    function test_JoinedAmount_WithLPToken() public {
        // Deploy action with LP as joinToken
        ExtensionGroupAction action = new ExtensionGroupAction(
            address(mockGroupActionFactory),
            address(token),
            address(lpToken),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        // Register extension in mockGroupActionFactory (not mockFactory)
        // because action.factory() returns mockGroupActionFactory
        token.mint(address(this), 1e18);
        token.approve(address(mockGroupActionFactory), type(uint256).max);
        mockGroupActionFactory.registerExtensionForTesting(
            address(action),
            address(token)
        );

        // Setup group owner
        uint256 groupId = setupGroupOwner(groupOwner1, 10000e18, "TestGroup");
        prepareExtensionInit(address(action), address(token), ACTION_ID);

        // Activate group
        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );
        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(action),
            groupId,
            "Group",
            0,
            1e18,
            0,
            0
        );

        // Increase LP token total supply to allow larger join amounts
        // Mint more LP tokens to increase totalSupply, so maxJoinAmount is large enough
        lpToken.mint(address(this), 1000e18); // Increase totalSupply to 1100e18

        // Calculate max join amount based on LP token totalSupply
        uint256 maxJoinAmount = groupManager.maxJoinAmount(address(action));

        // Use a join amount that's within the limit (use 80% of max to be safe)
        uint256 lpAmount = (maxJoinAmount * 80) / 100;
        if (lpAmount == 0) {
            // If maxJoinAmount is too small, mint more LP tokens
            lpToken.mint(address(this), 10000e18);
            maxJoinAmount = groupManager.maxJoinAmount(address(action));
            lpAmount = (maxJoinAmount * 80) / 100;
        }

        // User joins with LP tokens
        lpToken.mint(user1, lpAmount);
        vm.prank(user1);
        lpToken.approve(address(groupJoin), type(uint256).max);

        vm.prank(user1);
        groupJoin.join(address(action), groupId, lpAmount, new string[](0));

        // No conversion, directly return LP amount
        assertEq(
            action.joinedAmount(),
            lpAmount,
            "Total joinedAmount should be LP amount"
        );
        assertEq(
            action.joinedAmountByAccount(user1),
            lpAmount,
            "Account joinedAmount should be LP amount"
        );
    }
}
