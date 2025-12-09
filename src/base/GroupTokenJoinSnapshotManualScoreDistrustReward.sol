// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    GroupTokenJoinSnapshotManualScoreDistrust
} from "./GroupTokenJoinSnapshotManualScoreDistrust.sol";
import {IGroupReward} from "../interface/base/IGroupReward.sol";
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";

/// @title GroupTokenJoinSnapshotManualScoreDistrustReward
/// @notice Handles reward distribution for group-based actions
abstract contract GroupTokenJoinSnapshotManualScoreDistrustReward is
    GroupTokenJoinSnapshotManualScoreDistrust,
    IGroupReward
{
    // ============ Constructor ============

    constructor(
        address groupDistrustAddress_
    ) GroupTokenJoinSnapshotManualScoreDistrust(groupDistrustAddress_) {}
    // ============ State ============

    /// @dev round => burned amount
    mapping(uint256 => uint256) internal _burnedReward;

    // ============ IGroupReward Implementation ============

    /// @inheritdoc IGroupReward
    function burnUnclaimedReward(uint256 round) external {
        if (round >= _verify.currentRound()) revert RoundNotFinished();

        if (_verifiedGroupIds[round].length > 0) {
            revert RoundHasVerifiedGroups();
        }

        _prepareRewardIfNeeded(round);

        uint256 rewardAmount = _reward[round];
        if (rewardAmount > 0 && _burnedReward[round] == 0) {
            _burnedReward[round] = rewardAmount;
            ILOVE20Token(tokenAddress).burn(rewardAmount);
            emit UnclaimedRewardBurn(
                tokenAddress,
                round,
                actionId,
                rewardAmount
            );
        }
    }

    /// @inheritdoc IGroupReward
    function rewardByGroupId(
        uint256 round,
        uint256 groupId
    ) external view returns (uint256) {
        return _calculateRewardByGroupId(round, groupId);
    }

    /// @inheritdoc IGroupReward
    function rewardByVerifier(
        uint256 round,
        address verifier
    ) external view returns (uint256 amount) {
        uint256[] storage groupIds = _groupIdsByVerifier[round][verifier];
        for (uint256 i = 0; i < groupIds.length; i++) {
            amount += _calculateRewardByGroupId(round, groupIds[i]);
        }
    }

    // ============ Internal Functions ============

    function _calculateRewardByGroupId(
        uint256 round,
        uint256 groupId
    ) internal view returns (uint256) {
        uint256 totalReward = _reward[round];
        if (totalReward == 0) return 0;

        uint256 totalScore = _score[round];
        if (totalScore == 0) return 0;

        uint256 groupScore = _scoreByGroupId[round][groupId];
        return (totalReward * groupScore) / totalScore;
    }

    function _calculateReward(
        uint256 round,
        address account
    ) internal view override returns (uint256) {
        uint256 accountScore = _calculateScoreByAccount(round, account);
        if (accountScore == 0) return 0;

        uint256 groupId = groupIdByAccountByRound(account, round);
        if (groupId == 0) return 0;

        uint256 groupReward = _calculateRewardByGroupId(round, groupId);
        if (groupReward == 0) return 0;

        uint256 groupTotalScore = _totalScoreByGroupId[round][groupId];
        if (groupTotalScore == 0) return 0;

        return (groupReward * accountScore) / groupTotalScore;
    }
}
