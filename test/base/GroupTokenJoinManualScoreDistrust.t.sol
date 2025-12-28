// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "../utils/BaseGroupTest.sol";
import {
    GroupTokenJoinManualScoreDistrust
} from "../../src/base/GroupTokenJoinManualScoreDistrust.sol";
import {
    GroupTokenJoinManualScore
} from "../../src/base/GroupTokenJoinManualScore.sol";
import {GroupTokenJoin} from "../../src/base/GroupTokenJoin.sol";
import {GroupCore} from "../../src/base/GroupCore.sol";
import {LOVE20GroupDistrust} from "../../src/LOVE20GroupDistrust.sol";
import {IGroupDistrust} from "../../src/interface/base/IGroupDistrust.sol";
import {
    ILOVE20GroupDistrust
} from "../../src/interface/ILOVE20GroupDistrust.sol";
import {ILOVE20GroupManager} from "../../src/interface/ILOVE20GroupManager.sol";

/**
 * @title MockGroupDistrustContract
 * @notice Concrete implementation for testing
 */
contract MockGroupDistrustContract is GroupTokenJoinManualScoreDistrust {
    constructor(
        address factory_,
        address tokenAddress_,
        address groupManagerAddress_,
        address groupDistrustAddress_,
        address stakeTokenAddress_,
        uint256 groupActivationStakeAmount_,
        uint256 maxJoinAmountRatio_,
        uint256 maxVerifyCapacityFactor_
    )
        GroupTokenJoinManualScoreDistrust(groupDistrustAddress_)
        GroupCore(
            factory_,
            tokenAddress_,
            groupManagerAddress_,
            stakeTokenAddress_,
            groupActivationStakeAmount_
        )
        GroupTokenJoin(
            tokenAddress_,
            maxJoinAmountRatio_,
            maxVerifyCapacityFactor_
        )
    {}

    function isJoinedValueCalculated() external pure returns (bool) {
        return false;
    }

    function joinedValue() external view returns (uint256) {
        return totalJoinedAmount();
    }

    function joinedValueByAccount(
        address account
    ) external view returns (uint256) {
        (, uint256 amount, ) = this.joinInfo(account);
        return amount;
    }

    function _calculateReward(
        uint256,
        address
    ) internal pure override returns (uint256) {
        return 0;
    }
}

/**
 * @title GroupTokenJoinManualScoreDistrustTest
 * @notice Test suite for GroupTokenJoinManualScoreDistrust
 */
contract GroupTokenJoinManualScoreDistrustTest is BaseGroupTest {
    MockGroupDistrustContract public distrustContract;
    LOVE20GroupDistrust public groupDistrust;

    uint256 public groupId1;
    uint256 public groupId2;

    address public governor1 = address(0x30);
    address public governor2 = address(0x40);

    // Re-declare event for testing (must match interface definition exactly)
    event DistrustVote(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        address groupOwner,
        address voter,
        uint256 amount,
        string reason
    );

    function setUp() public {
        setUpBase();

        // Deploy GroupDistrust singleton
        groupDistrust = new LOVE20GroupDistrust(
            address(center),
            address(verify),
            address(group)
        );

        distrustContract = new MockGroupDistrustContract(
            address(mockFactory),
            address(token),
            address(groupManager),
            address(groupDistrust),
            address(token),
            GROUP_ACTIVATION_STAKE_AMOUNT,
            MAX_JOIN_AMOUNT_RATIO,
            CAPACITY_FACTOR
        );

        token.mint(address(this), 1e18);
        token.approve(address(mockFactory), type(uint256).max);
        mockFactory.registerExtension(
            address(distrustContract),
            address(token)
        );

        groupId1 = setupGroupOwner(groupOwner1, 10000e18, "TestGroup1");
        groupId2 = setupGroupOwner(groupOwner2, 10000e18, "TestGroup2");

        prepareExtensionInit(
            address(distrustContract),
            address(token),
            ACTION_ID
        );

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
            0, // maxCapacity
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
            0, // maxCapacity
            1e18, // minJoinAmount
            0,
            0
        );
    }

    /**
     * @notice Setup governor with verify votes
     */
    function setupGovernor(address governor, uint256 voteAmount) internal {
        setupVerifyVotes(
            governor,
            ACTION_ID,
            address(distrustContract),
            voteAmount
        );
    }

    /**
     * @notice Helper to submit scores for a group
     */
    function submitScores(
        uint256 groupId,
        address owner,
        uint256 numAccounts
    ) internal {
        uint256[] memory scores = new uint256[](numAccounts);
        for (uint256 i = 0; i < numAccounts; i++) {
            scores[i] = 80;
        }

        vm.prank(owner);
        distrustContract.verifyWithOriginScores(groupId, 0, scores);
    }

    // ============ distrustVote Tests ============

    function test_DistrustVote_Success() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(distrustContract));

        vm.prank(user1);
        distrustContract.join(groupId1, joinAmount, new string[](0));

        // Submit scores
        submitScores(groupId1, groupOwner1, 1);

        // Setup governor
        uint256 voteAmount = 100e18;
        setupGovernor(governor1, voteAmount);

        uint256 distrustAmount = 50e18;
        uint256 round = verify.currentRound();

        vm.prank(governor1, governor1);
        distrustContract.distrustVote(
            groupOwner1,
            distrustAmount,
            "Bad behavior"
        );

        assertEq(
            groupDistrust.distrustVotesByGroupId(
                address(token),
                ACTION_ID,
                round,
                groupId1
            ),
            distrustAmount
        );
    }

    function test_DistrustVote_AccumulateVotes() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(distrustContract));

        vm.prank(user1);
        distrustContract.join(groupId1, joinAmount, new string[](0));

        submitScores(groupId1, groupOwner1, 1);

        uint256 voteAmount = 100e18;
        setupGovernor(governor1, voteAmount);

        uint256 round = verify.currentRound();

        vm.startPrank(governor1, governor1);
        distrustContract.distrustVote(groupOwner1, 30e18, "First reason");
        distrustContract.distrustVote(groupOwner1, 20e18, "Second reason");
        vm.stopPrank();

        assertEq(
            groupDistrust.distrustVotesByGroupId(
                address(token),
                ACTION_ID,
                round,
                groupId1
            ),
            50e18
        );
    }

    function test_DistrustVote_MultipleGovernors() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(distrustContract));

        vm.prank(user1);
        distrustContract.join(groupId1, joinAmount, new string[](0));

        submitScores(groupId1, groupOwner1, 1);

        setupGovernor(governor1, 100e18);
        setupGovernor(governor2, 100e18);

        uint256 round = verify.currentRound();

        vm.prank(governor1, governor1);
        distrustContract.distrustVote(groupOwner1, 30e18, "Reason 1");

        vm.prank(governor2, governor2);
        distrustContract.distrustVote(groupOwner1, 40e18, "Reason 2");

        assertEq(
            groupDistrust.distrustVotesByGroupId(
                address(token),
                ACTION_ID,
                round,
                groupId1
            ),
            70e18
        );
    }

    function test_DistrustVote_RevertNotGovernor() public {
        // Setup: user joins first (triggers extension initialization)
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(distrustContract));

        vm.prank(user1);
        distrustContract.join(groupId1, joinAmount, new string[](0));

        submitScores(groupId1, groupOwner1, 1);

        // Non-governor tries to distrust vote (user3 has no verify votes)
        vm.prank(user3, user3);
        vm.expectRevert(ILOVE20GroupDistrust.NotGovernor.selector);
        distrustContract.distrustVote(groupOwner1, 10e18, "Reason");
    }

    function test_DistrustVote_RevertExceedsLimit() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(distrustContract));

        vm.prank(user1);
        distrustContract.join(groupId1, joinAmount, new string[](0));

        submitScores(groupId1, groupOwner1, 1);

        uint256 voteAmount = 100e18;
        setupGovernor(governor1, voteAmount);

        vm.prank(governor1, governor1);
        vm.expectRevert(ILOVE20GroupDistrust.DistrustVoteExceedsLimit.selector);
        distrustContract.distrustVote(groupOwner1, voteAmount + 1, "Reason");
    }

    function test_DistrustVote_RevertInvalidReason() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(distrustContract));

        vm.prank(user1);
        distrustContract.join(groupId1, joinAmount, new string[](0));

        submitScores(groupId1, groupOwner1, 1);

        setupGovernor(governor1, 100e18);

        vm.prank(governor1, governor1);
        vm.expectRevert(ILOVE20GroupDistrust.InvalidReason.selector);
        distrustContract.distrustVote(groupOwner1, 10e18, "");
    }

    // ============ Score Adjustment Tests ============

    function test_DistrustVote_AdjustsGroupScore() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(distrustContract));

        vm.prank(user1);
        distrustContract.join(groupId1, joinAmount, new string[](0));

        submitScores(groupId1, groupOwner1, 1);

        uint256 round = verify.currentRound();

        // Initial group score = joinAmount
        uint256 initialScore = distrustContract.scoreByGroupId(round, groupId1);
        assertEq(initialScore, joinAmount);

        // Setup governor and cast distrust vote
        uint256 totalVerifyVotes = 100e18;
        setupGovernor(governor1, totalVerifyVotes);

        uint256 distrustAmount = 50e18; // 50% distrust

        vm.prank(governor1, governor1);
        distrustContract.distrustVote(groupOwner1, distrustAmount, "Bad");

        // New score = groupAmount * (total - distrust) / total
        // = joinAmount * (100e18 - 50e18) / 100e18 = joinAmount * 0.5
        uint256 newScore = distrustContract.scoreByGroupId(round, groupId1);
        uint256 expectedScore = (joinAmount *
            (totalVerifyVotes - distrustAmount)) / totalVerifyVotes;
        assertEq(newScore, expectedScore);
    }

    function test_DistrustVote_AdjustsTotalScore() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(distrustContract));

        vm.prank(user1);
        distrustContract.join(groupId1, joinAmount, new string[](0));

        submitScores(groupId1, groupOwner1, 1);

        uint256 round = verify.currentRound();
        uint256 initialTotalScore = distrustContract.score(round);

        uint256 totalVerifyVotes = 100e18;
        setupGovernor(governor1, totalVerifyVotes);

        vm.prank(governor1, governor1);
        distrustContract.distrustVote(groupOwner1, 50e18, "Bad");

        uint256 newTotalScore = distrustContract.score(round);
        assertTrue(newTotalScore < initialTotalScore);
    }

    function test_DistrustVote_AffectsAllOwnerGroups() public {
        // Create another group for owner1
        uint256 groupId3 = group.mint(groupOwner1, "TestGroup3");

        // Increase governance votes to allow multiple groups
        stake.setValidGovVotes(address(token), groupOwner1, 30000e18);

        setupUser(
            groupOwner1,
            GROUP_ACTIVATION_STAKE_AMOUNT,
            address(groupManager)
        );

        vm.prank(groupOwner1, groupOwner1);
        groupManager.activateGroup(
            address(token),
            ACTION_ID,
            groupId3,
            "Group3",
            0, // maxCapacity
            1e18, // minJoinAmount
            0,
            0
        );

        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(distrustContract));
        setupUser(user2, joinAmount, address(distrustContract));

        vm.prank(user1);
        distrustContract.join(groupId1, joinAmount, new string[](0));

        vm.prank(user2);
        distrustContract.join(groupId3, joinAmount, new string[](0));

        // Submit scores for both groups
        submitScores(groupId1, groupOwner1, 1);

        uint256[] memory scores3 = new uint256[](1);
        scores3[0] = 80;
        vm.prank(groupOwner1);
        distrustContract.verifyWithOriginScores(groupId3, 0, scores3);

        uint256 round = verify.currentRound();

        uint256 initialScore1 = distrustContract.scoreByGroupId(
            round,
            groupId1
        );
        uint256 initialScore3 = distrustContract.scoreByGroupId(
            round,
            groupId3
        );

        uint256 totalVerifyVotes = 100e18;
        setupGovernor(governor1, totalVerifyVotes);

        vm.prank(governor1, governor1);
        distrustContract.distrustVote(groupOwner1, 50e18, "Bad");

        // Both groups should be affected
        uint256 newScore1 = distrustContract.scoreByGroupId(round, groupId1);
        uint256 newScore3 = distrustContract.scoreByGroupId(round, groupId3);

        assertTrue(newScore1 < initialScore1);
        assertTrue(newScore3 < initialScore3);
    }

    // ============ View Functions Tests ============

    function test_DistrustVotesByGroupId() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(distrustContract));

        vm.prank(user1);
        distrustContract.join(groupId1, joinAmount, new string[](0));

        submitScores(groupId1, groupOwner1, 1);

        setupGovernor(governor1, 100e18);

        vm.prank(governor1, governor1);
        distrustContract.distrustVote(groupOwner1, 30e18, "Bad");

        uint256 round = verify.currentRound();
        assertEq(
            groupDistrust.distrustVotesByGroupId(
                address(token),
                ACTION_ID,
                round,
                groupId1
            ),
            30e18
        );
    }

    // ============ Edge Cases ============

    function test_DistrustVote_ZeroTotalVerifyVotes() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(distrustContract));

        vm.prank(user1);
        distrustContract.join(groupId1, joinAmount, new string[](0));

        submitScores(groupId1, groupOwner1, 1);

        uint256 round = verify.currentRound();

        // Without any verify votes, group score should be groupAmount
        uint256 score = distrustContract.scoreByGroupId(round, groupId1);
        assertEq(score, joinAmount);
    }

    function test_DistrustVote_FullDistrust() public {
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(distrustContract));

        vm.prank(user1);
        distrustContract.join(groupId1, joinAmount, new string[](0));

        submitScores(groupId1, groupOwner1, 1);

        uint256 totalVerifyVotes = 100e18;
        setupGovernor(governor1, totalVerifyVotes);

        // 100% distrust
        vm.prank(governor1, governor1);
        distrustContract.distrustVote(
            groupOwner1,
            totalVerifyVotes,
            "Total distrust"
        );

        uint256 round = verify.currentRound();
        uint256 newScore = distrustContract.scoreByGroupId(round, groupId1);
        assertEq(newScore, 0);
    }
}
