// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {GroupTokenJoinManualScore} from "./GroupTokenJoinManualScore.sol";
import {IGroupDistrust} from "../interface/base/IGroupDistrust.sol";
import {ILOVE20GroupDistrust} from "../interface/ILOVE20GroupDistrust.sol";
import {ILOVE20Group} from "@group/interfaces/ILOVE20Group.sol";

/// @title GroupTokenJoinManualScoreDistrust
/// @notice Handles distrust voting mechanism against group owners
/// @dev Delegates distrust logic and storage to LOVE20GroupDistrust singleton
abstract contract GroupTokenJoinManualScoreDistrust is
    GroupTokenJoinManualScore,
    IGroupDistrust
{
    // ============ Immutables ============

    address public immutable GROUP_DISTRUST_ADDRESS;
    ILOVE20GroupDistrust internal immutable _groupDistrust;

    // ============ Constructor ============

    constructor(address groupDistrustAddress_) {
        GROUP_DISTRUST_ADDRESS = groupDistrustAddress_;
        _groupDistrust = ILOVE20GroupDistrust(groupDistrustAddress_);
    }

    // ============ IGroupDistrust Implementation ============

    /// @inheritdoc IGroupDistrust
    function distrustVote(
        address groupOwner,
        uint256 amount,
        string calldata reason
    ) external {
        // Delegate to GroupDistrust (handles verification and event)
        _groupDistrust.distrustVote(
            tokenAddress,
            actionId,
            groupOwner,
            amount,
            reason,
            msg.sender
        );

        // Update distrust for all active groups owned by this owner
        _updateDistrustForOwnerGroups(_verify.currentRound(), groupOwner);
    }

    // ============ Internal Functions ============

    function _getDistrustVotes(
        uint256 round,
        address groupOwner
    ) internal view returns (uint256) {
        return
            _groupDistrust.distrustVotesByGroupOwner(
                tokenAddress,
                actionId,
                round,
                groupOwner
            );
    }

    function _updateDistrustForOwnerGroups(
        uint256 round,
        address groupOwner
    ) internal {
        uint256 distrustVotes = _getDistrustVotes(round, groupOwner);
        uint256 total = _totalVerifyVotes(round);

        uint256[] storage groupIds = _groupIdsByVerifier[round][groupOwner];
        for (uint256 i = 0; i < groupIds.length; i++) {
            uint256 groupId = groupIds[i];
            uint256 oldScore = _scoreByGroupId[round][groupId];
            uint256 groupAmount = totalJoinedAmountByGroupIdByRound(
                groupId,
                round
            );

            uint256 newScore = total == 0
                ? groupAmount
                : (groupAmount * (total - distrustVotes)) / total;

            _scoreByGroupId[round][groupId] = newScore;
            _score[round] = _score[round] - oldScore + newScore;
        }
    }

    function _totalVerifyVotes(uint256 round) internal view returns (uint256) {
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
        uint256 groupAmount = totalJoinedAmountByGroupIdByRound(groupId, round);
        uint256 distrustVotes = _getDistrustVotes(round, groupOwner);
        uint256 total = _totalVerifyVotes(round);

        return
            total == 0
                ? groupAmount
                : (groupAmount * (total - distrustVotes)) / total;
    }
}
