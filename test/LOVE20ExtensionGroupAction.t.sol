// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "./utils/BaseGroupTest.sol";
import {
    LOVE20ExtensionGroupAction
} from "../src/LOVE20ExtensionGroupAction.sol";
import {LOVE20GroupManager} from "../src/LOVE20GroupManager.sol";
import {LOVE20GroupDistrust} from "../src/LOVE20GroupDistrust.sol";
import {ILOVE20GroupManager} from "../src/interface/ILOVE20GroupManager.sol";
import {IGroupCore} from "../src/interface/base/IGroupCore.sol";
import {IGroupTokenJoin} from "../src/interface/base/IGroupTokenJoin.sol";
import {
    IGroupScore,
    MAX_ORIGIN_SCORE
} from "../src/interface/base/IGroupScore.sol";
import {IGroupDistrust} from "../src/interface/base/IGroupDistrust.sol";
import {IGroupReward} from "../src/interface/base/IGroupReward.sol";
import {IGroupManualScore} from "../src/interface/base/IGroupManualScore.sol";
import {MockUniswapV2Pair} from "@extension/test/mocks/MockUniswapV2Pair.sol";

/**
 * @title LOVE20ExtensionGroupActionTest
 * @notice End-to-end test suite for LOVE20ExtensionGroupAction
 */
contract LOVE20ExtensionGroupActionTest is BaseGroupTest {
    LOVE20ExtensionGroupAction public groupAction;
    LOVE20GroupDistrust public groupDistrust;

    uint256 public groupId1;
    uint256 public groupId2;

    function _groupStakedAmount(
        uint256 groupId
    ) internal view returns (uint256) {
        (bool ok, bytes memory data) = address(groupManager).staticcall(
            abi.encodeWithSelector(
                ILOVE20GroupManager.groupInfo.selector,
                address(token),
                ACTION_ID,
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
                ILOVE20GroupManager.groupInfo.selector,
                address(token),
                ACTION_ID,
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
                ILOVE20GroupManager.groupInfo.selector,
                address(token),
                ACTION_ID,
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
                ILOVE20GroupManager.groupInfo.selector,
                address(token),
                ACTION_ID,
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

        // Deploy GroupDistrust singleton
        groupDistrust = new LOVE20GroupDistrust(
            address(center),
            address(verify),
            address(group)
        );

        // Deploy the actual GroupAction contract
        groupAction = new LOVE20ExtensionGroupAction(
            address(mockFactory),
            address(token),
            address(groupManager),
            address(groupDistrust),
            address(token), // stakeTokenAddress
            address(token), // joinTokenAddress
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            CAPACITY_FACTOR
        );

        // Register extension
        token.mint(address(this), 1e18);
        token.approve(address(mockFactory), type(uint256).max);
        mockFactory.registerExtension(address(groupAction), address(token));

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
            address(token),
            ACTION_ID,
            groupId1,
            "Group1",
            0, // maxCapacity (0 = use owner's theoretical max)
            1e18, // minJoinAmount
            0,
            0
        );

        vm.prank(groupOwner2, groupOwner2);
        groupManager.activateGroup(
            address(token),
            ACTION_ID,
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
        setupUser(user1, joinAmount1, address(groupAction));
        setupUser(user2, joinAmount2, address(groupAction));

        vm.prank(user1);
        groupAction.join(groupId1, joinAmount1, new string[](0));

        vm.prank(user2);
        groupAction.join(groupId1, joinAmount2, new string[](0));

        // Verify join state
        assertEq(groupAction.totalJoinedAmount(), joinAmount1 + joinAmount2);
        assertEq(groupAction.accountsByGroupIdCount(groupId1), 2);

        // 2. Submit scores
        uint256[] memory scores = new uint256[](2);
        scores[0] = 80;
        scores[1] = 90;

        vm.prank(groupOwner1);
        groupAction.verifyWithOriginScores(groupId1, 0, scores);

        // 3. Verify scores
        uint256 round = verify.currentRound();
        assertEq(groupAction.originScoreByAccount(round, user1), 80);
        assertEq(groupAction.originScoreByAccount(round, user2), 90);

        // 4. User exits
        vm.prank(user1);
        groupAction.exit();

        assertEq(groupAction.totalJoinedAmount(), joinAmount2);
        assertEq(groupAction.accountsByGroupIdCount(groupId1), 1);
    }

    function test_GroupActivationAndDeactivation() public {
        assertTrue(
            groupManager.isGroupActive(address(token), ACTION_ID, groupId1)
        );

        advanceRound();
        // Setup actionIds for new round
        vote.setVotedActionIds(
            address(token),
            verify.currentRound(),
            ACTION_ID
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.deactivateGroup(address(token), ACTION_ID, groupId1);

        assertFalse(
            groupManager.isGroupActive(address(token), ACTION_ID, groupId1)
        );

        // Cannot join deactivated group
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupAction));

        vm.prank(user1);
        vm.expectRevert(IGroupTokenJoin.CannotJoinDeactivatedGroup.selector);
        groupAction.join(groupId1, joinAmount, new string[](0));
    }

    function test_DelegatedVerification() public {
        address delegatedVerifier = address(0x123);

        vm.prank(groupOwner1);
        groupAction.setGroupDelegatedVerifier(groupId1, delegatedVerifier);

        // User joins
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupAction));

        vm.prank(user1);
        groupAction.join(groupId1, joinAmount, new string[](0));

        // Delegated verifier can submit scores
        uint256[] memory scores = new uint256[](1);
        scores[0] = 85;

        vm.prank(delegatedVerifier);
        groupAction.verifyWithOriginScores(groupId1, 0, scores);

        uint256 round = verify.currentRound();
        assertEq(groupAction.originScoreByAccount(round, user1), 85);
    }

    function test_DistrustVoting() public {
        // Setup group with member
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupAction));

        vm.prank(user1);
        groupAction.join(groupId1, joinAmount, new string[](0));

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.prank(groupOwner1);
        groupAction.verifyWithOriginScores(groupId1, 0, scores);

        // Setup governor
        address governor = address(0x50);
        setupVerifyVotes(governor, ACTION_ID, address(groupAction), 100e18);

        uint256 round = verify.currentRound();
        uint256 scoreBefore = groupAction.scoreByGroupId(round, groupId1);

        // Cast distrust vote
        vm.prank(governor, governor);
        groupAction.distrustVote(groupOwner1, 50e18, "Bad behavior");

        uint256 scoreAfter = groupAction.scoreByGroupId(round, groupId1);
        assertTrue(scoreAfter < scoreBefore);
    }

    function test_MultipleGroupsWithDifferentOwners() public {
        // Both groups have members
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupAction));
        setupUser(user2, joinAmount, address(groupAction));

        vm.prank(user1);
        groupAction.join(groupId1, joinAmount, new string[](0));

        vm.prank(user2);
        groupAction.join(groupId2, joinAmount, new string[](0));

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.prank(groupOwner1);
        groupAction.verifyWithOriginScores(groupId1, 0, scores);

        vm.prank(groupOwner2);
        groupAction.verifyWithOriginScores(groupId2, 0, scores);

        uint256 round = verify.currentRound();
        assertEq(groupAction.verifiersCount(round), 2);
    }

    // ============ IExtensionJoinedValue Tests ============

    function test_IsJoinedValueCalculated() public view {
        // joinToken == tokenAddress, so no conversion needed
        assertFalse(groupAction.isJoinedValueCalculated());
    }

    function test_JoinedValue() public {
        uint256 joinAmount1 = 10e18;
        uint256 joinAmount2 = 20e18;
        setupUser(user1, joinAmount1, address(groupAction));
        setupUser(user2, joinAmount2, address(groupAction));

        vm.prank(user1);
        groupAction.join(groupId1, joinAmount1, new string[](0));

        vm.prank(user2);
        groupAction.join(groupId2, joinAmount2, new string[](0));

        assertEq(groupAction.joinedValue(), joinAmount1 + joinAmount2);
    }

    function test_JoinedValueByAccount() public {
        uint256 joinAmount = 15e18;
        setupUser(user1, joinAmount, address(groupAction));

        vm.prank(user1);
        groupAction.join(groupId1, joinAmount, new string[](0));

        assertEq(groupAction.joinedValueByAccount(user1), joinAmount);
        assertEq(groupAction.joinedValueByAccount(user2), 0);
    }

    // ============ IGroupManualScore Implementation Tests ============

    function test_ImplementsIGroupManualScore() public view {
        // Contract should properly implement the interface
        assertTrue(groupAction.canVerify(groupOwner1, groupId1));
        assertFalse(groupAction.canVerify(user1, groupId1));
    }

    // ============ Edge Cases ============

    function test_JoinThenExitThenRejoin() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount * 2, address(groupAction));

        // First join
        vm.prank(user1);
        groupAction.join(groupId1, joinAmount, new string[](0));

        assertEq(groupAction.totalJoinedAmount(), joinAmount);

        // Exit
        vm.prank(user1);
        groupAction.exit();

        assertEq(groupAction.totalJoinedAmount(), 0);

        // Rejoin (possibly different group)
        vm.prank(user1);
        groupAction.join(groupId2, joinAmount, new string[](0));

        assertEq(groupAction.totalJoinedAmount(), joinAmount);
        (, , uint256 groupId) = groupAction.joinInfo(user1);
        assertEq(groupId, groupId2);
    }

    function test_ScoreWithZeroAmount() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupAction));

        vm.prank(user1);
        groupAction.join(groupId1, joinAmount, new string[](0));

        uint256[] memory scores = new uint256[](1);
        scores[0] = 0;

        vm.prank(groupOwner1);
        groupAction.verifyWithOriginScores(groupId1, 0, scores);

        uint256 round = verify.currentRound();
        assertEq(groupAction.scoreByAccount(round, user1), 0);
    }

    function test_MaxScore() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupAction));

        vm.prank(user1);
        groupAction.join(groupId1, joinAmount, new string[](0));

        uint256[] memory scores = new uint256[](1);
        scores[0] = MAX_ORIGIN_SCORE;

        vm.prank(groupOwner1);
        groupAction.verifyWithOriginScores(groupId1, 0, scores);

        uint256 round = verify.currentRound();
        assertEq(
            groupAction.originScoreByAccount(round, user1),
            MAX_ORIGIN_SCORE
        );
    }

    function test_GroupInfoUpdate() public {
        string memory newDesc = "Updated description";
        uint256 newMin = 5e18;
        uint256 newMax = 50e18;

        vm.prank(groupOwner1, groupOwner1);
        groupManager.updateGroupInfo(
            address(token),
            ACTION_ID,
            groupId1,
            newDesc,
            0, // newMaxCapacity
            newMin,
            newMax,
            0
        );

        string memory desc = _groupDescription(groupId1);
        uint256 minJoin = _minJoinAmount(groupId1);
        uint256 maxJoin = _maxJoinAmount(groupId1);
        assertEq(desc, newDesc);
        assertEq(minJoin, newMin);
        assertEq(maxJoin, newMax);
    }

    // ============ Verifier Capacity Tests ============

    function test_VerifierCapacityLimit() public {
        // Test that verifier capacity is limited by governance votes

        // Get max verify capacity for owner
        uint256 maxCapacity = groupManager.maxVerifyCapacityByOwner(
            address(token),
            ACTION_ID,
            groupOwner1
        );
        uint256 maxPerAccount = groupManager.calculateJoinMaxAmount(
            address(token),
            ACTION_ID
        );
        assertTrue(maxCapacity > 0, "maxCapacity should be > 0");
        assertTrue(maxPerAccount > 0, "maxPerAccount should be > 0");

        // Use a small amount that's within limits (1e18 is the minStake from submit)
        uint256 joinAmount = 1e18;

        // Have users join group
        setupUser(user1, joinAmount, address(groupAction));

        vm.prank(user1);
        groupAction.join(groupId1, joinAmount, new string[](0));

        // Verify join was successful
        assertEq(groupAction.accountsByGroupIdCount(groupId1), 1);

        // Capacity check is done during verifyWithOriginScores, so let's test that path
        advanceRound();
        vote.setVotedActionIds(
            address(token),
            verify.currentRound(),
            ACTION_ID
        );

        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        // This should succeed since we're within capacity
        vm.prank(groupOwner1);
        groupAction.verifyWithOriginScores(groupId1, 0, scores);

        uint256 round = verify.currentRound();
        assertEq(groupAction.verifiersCount(round), 1);
    }

    // ============ Cross-Round Tests ============

    function test_CrossRoundBehavior() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupAction));

        vm.prank(user1);
        groupAction.join(groupId1, joinAmount, new string[](0));

        // Advance round to get fresh snapshot for round 1
        advanceRound();
        uint256 round1 = verify.currentRound();

        // Submit scores in round 1
        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;

        vm.prank(groupOwner1);
        groupAction.verifyWithOriginScores(groupId1, 0, scores);

        // Advance round
        advanceRound();
        uint256 round2 = verify.currentRound();

        // Scores should be specific to round
        assertEq(groupAction.originScoreByAccount(round1, user1), 80);
        assertEq(groupAction.originScoreByAccount(round2, user1), 0);

        // Submit scores in round 2
        uint256[] memory scores2 = new uint256[](1);
        scores2[0] = 90;

        vm.prank(groupOwner1);
        groupAction.verifyWithOriginScores(groupId1, 0, scores2);

        assertEq(groupAction.originScoreByAccount(round2, user1), 90);
    }
}

/**
 * @title LOVE20ExtensionGroupActionJoinTokenTest
 * @notice Tests for joinTokenAddress validation and LP token conversion
 */
contract LOVE20ExtensionGroupActionJoinTokenTest is BaseGroupTest {
    LOVE20GroupDistrust public groupDistrust;
    MockUniswapV2Pair public lpToken;

    function setUp() public {
        setUpBase();

        groupDistrust = new LOVE20GroupDistrust(
            address(center),
            address(verify),
            address(group)
        );

        // Create LP token containing token
        lpToken = new MockUniswapV2Pair(address(token), address(0x999));
        lpToken.setReserves(1000e18, 500e18); // 1000 token, 500 other
        lpToken.mint(address(this), 100e18); // LP total supply
    }

    function test_InvalidJoinToken_NotLPToken() public {
        // Using random address that's not an LP token
        address invalidToken = address(0x123);

        vm.expectRevert(); // Low-level call to non-contract returns no data
        new LOVE20ExtensionGroupAction(
            address(mockFactory),
            address(token),
            address(groupManager),
            address(groupDistrust),
            address(token), // stakeToken
            invalidToken, // invalid joinToken
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            CAPACITY_FACTOR
        );
    }

    function test_InvalidJoinToken_LPNotContainingToken() public {
        // Create LP with neither token being tokenAddress
        MockUniswapV2Pair badLp = new MockUniswapV2Pair(
            address(0x111),
            address(0x222)
        );

        vm.expectRevert(IGroupTokenJoin.InvalidJoinTokenAddress.selector);
        new LOVE20ExtensionGroupAction(
            address(mockFactory),
            address(token),
            address(groupManager),
            address(groupDistrust),
            address(token),
            address(badLp), // LP doesn't contain token
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            CAPACITY_FACTOR
        );
    }

    function test_ValidJoinToken_TokenItself() public {
        // Should not revert
        LOVE20ExtensionGroupAction action = new LOVE20ExtensionGroupAction(
            address(mockFactory),
            address(token),
            address(groupManager),
            address(groupDistrust),
            address(token),
            address(token), // joinToken = token
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            CAPACITY_FACTOR
        );

        assertEq(action.JOIN_TOKEN_ADDRESS(), address(token));
        assertEq(
            action.tokenAddress(),
            address(token),
            "tokenAddress mismatch"
        );
        assertFalse(action.isJoinedValueCalculated());
    }

    function test_ValidJoinToken_LPContainingToken() public {
        // Should not revert
        LOVE20ExtensionGroupAction action = new LOVE20ExtensionGroupAction(
            address(mockFactory),
            address(token),
            address(groupManager),
            address(groupDistrust),
            address(token),
            address(lpToken), // LP containing token
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            CAPACITY_FACTOR
        );

        assertEq(action.JOIN_TOKEN_ADDRESS(), address(lpToken));
        assertTrue(action.isJoinedValueCalculated());
    }

    function test_JoinedValue_WithLPToken() public {
        // Deploy action with LP as joinToken
        LOVE20ExtensionGroupAction action = new LOVE20ExtensionGroupAction(
            address(mockFactory),
            address(token),
            address(groupManager),
            address(groupDistrust),
            address(token),
            address(lpToken),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_MULTIPLIER,
            CAPACITY_FACTOR
        );

        // Register extension
        token.mint(address(this), 1e18);
        token.approve(address(mockFactory), type(uint256).max);
        mockFactory.registerExtension(address(action), address(token));

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
            address(token),
            ACTION_ID,
            groupId,
            "Group",
            0,
            1e18,
            0,
            0
        );

        // User joins with LP tokens
        uint256 lpAmount = 10e18;
        lpToken.mint(user1, lpAmount);
        vm.prank(user1);
        lpToken.approve(address(action), type(uint256).max);

        vm.prank(user1);
        action.join(groupId, lpAmount, new string[](0));

        // Calculate expected value:
        // LP total supply = 100e18 + 10e18 (minted to user) = 110e18
        // tokenReserve = 1000e18 (token is token0)
        // joinedValue = tokenReserve * lpAmount * 2 / totalSupply
        //             = 1000e18 * 10e18 * 2 / 110e18
        uint256 totalSupply = lpToken.totalSupply();
        uint256 expectedValue = (1000e18 * lpAmount * 2) / totalSupply;

        assertEq(
            action.joinedValue(),
            expectedValue,
            "Total joinedValue should be LP converted value"
        );
        assertEq(
            action.joinedValueByAccount(user1),
            expectedValue,
            "Account joinedValue should be LP converted value"
        );
    }
}
