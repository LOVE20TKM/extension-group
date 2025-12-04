// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    GroupTokenJoinSnapshotManualScore
} from "./GroupTokenJoinSnapshotManualScore.sol";
import {IGroupDistrust} from "../interface/base/IGroupManualScore.sol";
import {ILOVE20Group} from "@group/interfaces/ILOVE20Group.sol";

/// @title GroupTokenJoinSnapshotManualScoreDistrust
/// @notice Handles distrust voting mechanism against group owners
abstract contract GroupTokenJoinSnapshotManualScoreDistrust is
    GroupTokenJoinSnapshotManualScore,
    IGroupDistrust
{
    // ============ State ============

    /// @dev round => groupOwner => total distrust votes
    mapping(uint256 => mapping(address => uint256))
        internal _distrustVotesByGroupOwner;

    /// @dev round => voter => groupOwner => distrust votes for this groupOwner
    mapping(uint256 => mapping(address => mapping(address => uint256)))
        internal _distrustVotesByVoterByGroupOwner;

    /// @dev round => voter => groupOwner => reason
    mapping(uint256 => mapping(address => mapping(address => string)))
        internal _distrustReason;

    // ============ IGroupDistrust Implementation ============

    /// @inheritdoc IGroupDistrust
    function distrustVote(
        address groupOwner,
        uint256 amount,
        string calldata reason
    ) external {
        uint256 currentRound = _verify.currentRound();

        // Check caller has voted for extension contract (non-abstain vote)
        uint256 verifyVotes = _verify.scoreByVerifierByActionIdByAccount(
            tokenAddress,
            currentRound,
            msg.sender,
            actionId,
            address(this)
        );
        if (verifyVotes == 0) revert NotGovernor();

        // Check accumulated votes don't exceed verify votes
        if (
            _distrustVotesByVoterByGroupOwner[currentRound][msg.sender][
                groupOwner
            ] +
                amount >
            verifyVotes
        ) revert DistrustVoteExceedsLimit();

        if (bytes(reason).length == 0) revert InvalidReason();

        // Record vote
        _distrustVotesByVoterByGroupOwner[currentRound][msg.sender][
            groupOwner
        ] += amount;
        _distrustVotesByGroupOwner[currentRound][groupOwner] += amount;
        _distrustReason[currentRound][msg.sender][groupOwner] = reason;

        // Update distrust for all active groups owned by this owner
        _updateDistrustForOwnerGroups(currentRound, groupOwner);

        emit DistrustVoted(
            currentRound,
            groupOwner,
            msg.sender,
            amount,
            reason
        );
    }

    /// @inheritdoc IGroupDistrust
    function distrustVotesByGroupOwner(
        uint256 round,
        address groupOwner
    ) external view returns (uint256) {
        return _distrustVotesByGroupOwner[round][groupOwner];
    }

    /// @inheritdoc IGroupDistrust
    function distrustVotesByGroupId(
        uint256 round,
        uint256 groupId
    ) external view returns (uint256) {
        address groupOwner = ILOVE20Group(GROUP_ADDRESS).ownerOf(groupId);
        return _distrustVotesByGroupOwner[round][groupOwner];
    }

    /// @inheritdoc IGroupDistrust
    function distrustRatioByGroupOwner(
        uint256 round,
        address groupOwner
    ) external view returns (uint256 distrustVotes, uint256 totalVerifyVotes) {
        distrustVotes = _distrustVotesByGroupOwner[round][groupOwner];
        totalVerifyVotes = _getTotalNonAbstainVerifyVotes(round);
    }

    /// @inheritdoc IGroupDistrust
    function distrustVotesByVoterByGroupOwner(
        uint256 round,
        address voter,
        address groupOwner
    ) external view returns (uint256) {
        return _distrustVotesByVoterByGroupOwner[round][voter][groupOwner];
    }

    /// @inheritdoc IGroupDistrust
    function distrustReason(
        uint256 round,
        address voter,
        address groupOwner
    ) external view returns (string memory) {
        return _distrustReason[round][voter][groupOwner];
    }

    // ============ Internal Functions ============

    function _updateDistrustForOwnerGroups(
        uint256 round,
        address groupOwner
    ) internal {
        uint256 distrustVotes = _distrustVotesByGroupOwner[round][groupOwner];
        uint256 totalVerifyVotes = _getTotalNonAbstainVerifyVotes(round);

        uint256[] storage groupIds = _snapshotGroupIdsByVerifier[round][
            groupOwner
        ];
        for (uint256 i = 0; i < groupIds.length; i++) {
            uint256 groupId = groupIds[i];
            if (_scoreSubmitted[round][groupId]) {
                uint256 oldScore = _scoreByGroupId[round][groupId];
                uint256 groupAmount = _snapshotAmountByGroupId[round][groupId];

                uint256 newScore = totalVerifyVotes == 0
                    ? groupAmount
                    : (groupAmount * (totalVerifyVotes - distrustVotes)) /
                        totalVerifyVotes;

                _scoreByGroupId[round][groupId] = newScore;
                _score[round] = _score[round] - oldScore + newScore;
            }
        }
    }

    function _getTotalNonAbstainVerifyVotes(
        uint256 round
    ) internal view returns (uint256) {
        return
            _verify.scoreByActionIdByAccount(
                tokenAddress,
                round,
                actionId,
                address(this)
            );
    }

    // ============ Override Functions ============

    /// @dev Override to apply distrust ratio to group score
    function _calculateGroupScore(
        uint256 round,
        uint256 groupId
    ) internal view virtual override returns (uint256) {
        address groupOwner = ILOVE20Group(GROUP_ADDRESS).ownerOf(groupId);
        uint256 groupAmount = _snapshotAmountByGroupId[round][groupId];
        uint256 distrustVotes = _distrustVotesByGroupOwner[round][groupOwner];
        uint256 totalVerifyVotes = _getTotalNonAbstainVerifyVotes(round);

        return
            totalVerifyVotes == 0
                ? groupAmount
                : (groupAmount * (totalVerifyVotes - distrustVotes)) /
                    totalVerifyVotes;
    }
}
