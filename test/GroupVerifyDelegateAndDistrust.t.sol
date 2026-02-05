// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {BaseGroupTest} from "./utils/BaseGroupTest.sol";
import {ExtensionGroupAction} from "../src/ExtensionGroupAction.sol";
import {IGroupVerify, IGroupVerifyErrors} from "../src/interface/IGroupVerify.sol";
import {IGroupManagerErrors} from "../src/interface/IGroupManager.sol";

/// @title GroupVerifyDelegateAndDistrustTest
/// @notice Boundary tests for GroupVerify delegate and distrust functionality.
/// @dev Covers: setGroupDelegate access control, delegate submission,
///      delegate replacement, distrust vote validations, and cumulative effects.
contract GroupVerifyDelegateAndDistrustTest is BaseGroupTest {
    uint256 constant MAX_ORIGIN_SCORE = 100;

    ExtensionGroupAction public groupAction;
    uint256 public groupId1;

    address public delegate1 = address(0xD1);
    address public delegate2 = address(0xD2);

    function setUp() public {
        setUpBase();

        // Approve factory to transfer registration tokens
        token.approve(address(mockGroupActionFactory), type(uint256).max);

        // Create extension via factory
        (
            address joinToken,
            uint256 stakeAmt,
            uint256 maxRatio,
            uint256 minGovRatio
        ) = createDefaultConfig();
        address ext = mockGroupActionFactory.createExtension(
            address(token),
            minGovRatio,
            stakeAmt,
            joinToken,
            maxRatio
        );
        groupAction = ExtensionGroupAction(ext);

        // Prepare extension init
        prepareExtensionInit(address(groupAction), address(token), ACTION_ID);

        // Setup activated group owned by groupOwner1
        groupId1 = _setupActivatedGroup(
            groupOwner1,
            address(groupAction),
            "DelegateTestGroup"
        );

        // Have a user join the group so scores can be submitted
        uint256 joinAmount = 10e18;
        setupUser(user1, joinAmount, address(groupJoin));
        vm.prank(user1);
        groupJoin.join(
            address(groupAction),
            groupId1,
            joinAmount,
            new string[](0)
        );
    }

    // ============================================================
    // Delegate Tests
    // ============================================================

    /// @notice Non-owner cannot set a delegate for a group they do not own
    function test_setGroupDelegate_NonOwnerReverts() public {
        vm.prank(user2);
        vm.expectRevert(IGroupVerifyErrors.OnlyGroupOwner.selector);
        groupVerify.setGroupDelegate(
            address(groupAction),
            groupId1,
            delegate1
        );
    }

    /// @notice Owner successfully sets a delegate; canVerify returns true for that delegate
    function test_setGroupDelegate_Success() public {
        // Before delegation, delegate1 cannot verify
        assertFalse(
            groupVerify.canVerify(address(groupAction), delegate1, groupId1),
            "delegate1 should not be able to verify before delegation"
        );

        // Owner sets delegate
        vm.prank(groupOwner1);
        groupVerify.setGroupDelegate(
            address(groupAction),
            groupId1,
            delegate1
        );

        // After delegation, delegate1 can verify
        assertTrue(
            groupVerify.canVerify(address(groupAction), delegate1, groupId1),
            "delegate1 should be able to verify after delegation"
        );

        // delegateByGroupId should return the delegate
        assertEq(
            groupVerify.delegateByGroupId(address(groupAction), groupId1),
            delegate1,
            "delegateByGroupId should return delegate1"
        );
    }

    /// @notice Delegate can submit origin scores on behalf of the owner
    function test_delegateCanSubmitScores() public {
        // Owner sets delegate
        vm.prank(groupOwner1);
        groupVerify.setGroupDelegate(
            address(groupAction),
            groupId1,
            delegate1
        );

        // Delegate submits scores
        uint256[] memory scores = new uint256[](1);
        scores[0] = 85;

        vm.prank(delegate1);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            0,
            scores
        );

        // Verify score was stored
        uint256 round = verify.currentRound();
        assertEq(
            groupVerify.originScoreByAccount(
                address(groupAction),
                round,
                user1
            ),
            85,
            "Score should be 85 as submitted by delegate"
        );
    }

    /// @notice After replacing delegate A with delegate B, A can no longer submit scores
    function test_replacedDelegateCannotSubmitScores() public {
        // Owner sets delegate1
        vm.prank(groupOwner1);
        groupVerify.setGroupDelegate(
            address(groupAction),
            groupId1,
            delegate1
        );

        // Confirm delegate1 can verify
        assertTrue(
            groupVerify.canVerify(address(groupAction), delegate1, groupId1),
            "delegate1 should be able to verify"
        );

        // Owner replaces delegate1 with delegate2
        vm.prank(groupOwner1);
        groupVerify.setGroupDelegate(
            address(groupAction),
            groupId1,
            delegate2
        );

        // delegate1 can no longer verify
        assertFalse(
            groupVerify.canVerify(address(groupAction), delegate1, groupId1),
            "delegate1 should not be able to verify after replacement"
        );

        // delegate2 can verify
        assertTrue(
            groupVerify.canVerify(address(groupAction), delegate2, groupId1),
            "delegate2 should be able to verify after replacement"
        );

        // delegate1 cannot submit scores
        uint256[] memory scores = new uint256[](1);
        scores[0] = 90;

        vm.prank(delegate1);
        vm.expectRevert(IGroupVerifyErrors.NotVerifier.selector);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            0,
            scores
        );
    }

    /// @notice Owner can still submit scores even after setting a delegate
    function test_ownerCanStillSubmitAfterDelegation() public {
        // Owner sets delegate
        vm.prank(groupOwner1);
        groupVerify.setGroupDelegate(
            address(groupAction),
            groupId1,
            delegate1
        );

        // Owner can still verify
        assertTrue(
            groupVerify.canVerify(address(groupAction), groupOwner1, groupId1),
            "Owner should still be able to verify after delegation"
        );

        // Owner submits scores
        uint256[] memory scores = new uint256[](1);
        scores[0] = 75;

        vm.prank(groupOwner1);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            0,
            scores
        );

        // Verify score was stored
        uint256 round = verify.currentRound();
        assertEq(
            groupVerify.originScoreByAccount(
                address(groupAction),
                round,
                user1
            ),
            75,
            "Score should be 75 as submitted by owner"
        );
    }

    // ============================================================
    // Distrust Vote Boundary Tests
    // ============================================================

    /// @notice distrustVote reverts when amount is 0
    function test_distrustVote_ZeroAmountReverts() public {
        address voter = user2;
        setupVerifyVotes(voter, ACTION_ID, address(groupAction), 100e18);

        vm.prank(voter, voter);
        vm.expectRevert(IGroupVerifyErrors.DistrustVoteZeroAmount.selector);
        groupVerify.distrustVote(
            address(groupAction),
            groupOwner1,
            0, // zero amount
            "Some reason"
        );
    }

    /// @notice distrustVote reverts when reason is empty
    function test_distrustVote_EmptyReasonReverts() public {
        address voter = user2;
        setupVerifyVotes(voter, ACTION_ID, address(groupAction), 100e18);

        vm.prank(voter, voter);
        vm.expectRevert(IGroupVerifyErrors.InvalidReason.selector);
        groupVerify.distrustVote(
            address(groupAction),
            groupOwner1,
            50e18,
            "" // empty reason
        );
    }

    /// @notice distrustVote reverts when voter has no verify votes
    function test_distrustVote_NoVerifyVotesReverts() public {
        // user3 has no verify votes set up
        vm.prank(user3, user3);
        vm.expectRevert(IGroupVerifyErrors.VerifyVotesZero.selector);
        groupVerify.distrustVote(
            address(groupAction),
            groupOwner1,
            50e18,
            "Bad behavior"
        );
    }

    /// @notice distrustVote reverts when amount exceeds voter's verify votes
    function test_distrustVote_ExceedsVerifyVotesReverts() public {
        address voter = user2;
        uint256 verifyVotes = 100e18;
        setupVerifyVotes(voter, ACTION_ID, address(groupAction), verifyVotes);

        vm.prank(voter, voter);
        vm.expectRevert(
            IGroupVerifyErrors.DistrustVoteExceedsVerifyVotes.selector
        );
        groupVerify.distrustVote(
            address(groupAction),
            groupOwner1,
            verifyVotes + 1, // exceeds verify votes
            "Bad behavior"
        );
    }

    /// @notice Cumulative distrust votes: vote X then vote Y, total should be X + Y
    function test_distrustVote_CumulativeEffect() public {
        // First verify the group so scores exist
        uint256[] memory scores = new uint256[](1);
        scores[0] = 80;
        vm.prank(groupOwner1);
        groupVerify.submitOriginScores(
            address(groupAction),
            groupId1,
            0,
            scores
        );

        address voter = user2;
        uint256 verifyVotes = 100e18;
        setupVerifyVotes(voter, ACTION_ID, address(groupAction), verifyVotes);

        uint256 round = verify.currentRound();
        uint256 firstVote = 30e18;
        uint256 secondVote = 40e18;

        // First distrust vote
        vm.prank(voter, voter);
        groupVerify.distrustVote(
            address(groupAction),
            groupOwner1,
            firstVote,
            "First reason"
        );

        assertEq(
            groupVerify.distrustVotesByVoterByGroupOwner(
                address(groupAction),
                round,
                voter,
                groupOwner1
            ),
            firstVote,
            "After first vote, voter distrust should be firstVote"
        );

        // Second distrust vote
        vm.prank(voter, voter);
        groupVerify.distrustVote(
            address(groupAction),
            groupOwner1,
            secondVote,
            "Second reason"
        );

        // Total should be cumulative
        assertEq(
            groupVerify.distrustVotesByVoterByGroupOwner(
                address(groupAction),
                round,
                voter,
                groupOwner1
            ),
            firstVote + secondVote,
            "After second vote, voter distrust should be firstVote + secondVote"
        );

        assertEq(
            groupVerify.distrustVotesByGroupOwner(
                address(groupAction),
                round,
                groupOwner1
            ),
            firstVote + secondVote,
            "Total distrust for groupOwner should be firstVote + secondVote"
        );
    }

    /// @notice Cumulative distrust votes revert when total exceeds verify votes
    function test_distrustVote_CumulativeExceedsReverts() public {
        address voter = user2;
        uint256 verifyVotes = 100e18;
        setupVerifyVotes(voter, ACTION_ID, address(groupAction), verifyVotes);

        uint256 firstVote = 60e18;
        uint256 secondVote = 50e18; // 60 + 50 = 110 > 100

        // First distrust vote succeeds
        vm.prank(voter, voter);
        groupVerify.distrustVote(
            address(groupAction),
            groupOwner1,
            firstVote,
            "First reason"
        );

        // Second vote should revert because cumulative (60 + 50 = 110) > verifyVotes (100)
        vm.prank(voter, voter);
        vm.expectRevert(
            IGroupVerifyErrors.DistrustVoteExceedsVerifyVotes.selector
        );
        groupVerify.distrustVote(
            address(groupAction),
            groupOwner1,
            secondVote,
            "Second reason"
        );
    }
}
