// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    GroupTokenJoinSnapshotManualScoreDistrust
} from "./GroupTokenJoinSnapshotManualScoreDistrust.sol";
import {IGroupReward} from "../interface/base/IGroupReward.sol";
import {
    IExtensionReward
} from "@extension/src/interface/base/IExtensionReward.sol";
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";

/// @title GroupTokenJoinSnapshotManualScoreDistrustReward
/// @notice Handles reward distribution for group-based actions
abstract contract GroupTokenJoinSnapshotManualScoreDistrustReward is
    GroupTokenJoinSnapshotManualScoreDistrust,
    IGroupReward
{
    // ============ State ============

    /// @dev round => total reward for the round
    mapping(uint256 => uint256) internal _reward;

    /// @dev round => account => claimed reward
    mapping(uint256 => mapping(address => uint256)) internal _claimedReward;

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
            emit UnclaimedRewardBurned(round, rewardAmount);
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
    function rewardByGroupOwner(
        uint256 round,
        address groupOwner
    ) external view returns (uint256 amount) {
        uint256[] storage groupIds = _snapshotGroupIdsByVerifier[round][
            groupOwner
        ];
        for (uint256 i = 0; i < groupIds.length; i++) {
            amount += _calculateRewardByGroupId(round, groupIds[i]);
        }
    }

    /// @inheritdoc IExtensionReward
    function reward(uint256 round) external view returns (uint256) {
        return _reward[round];
    }

    // ============ IExtensionReward Implementation ============

    /// @inheritdoc IExtensionReward
    function rewardByAccount(
        uint256 round,
        address account
    ) public view returns (uint256 amount, bool isMinted) {
        uint256 claimed = _claimedReward[round][account];
        if (claimed > 0) {
            return (claimed, true);
        }
        return (_calculateReward(round, account), false);
    }

    /// @inheritdoc IExtensionReward
    function claimReward(uint256 round) external returns (uint256 amount) {
        if (round >= _verify.currentRound()) revert RoundNotFinished();

        _prepareRewardIfNeeded(round);

        bool isMinted;
        (amount, isMinted) = rewardByAccount(round, msg.sender);
        if (isMinted) revert AlreadyClaimed();

        _claimedReward[round][msg.sender] = amount;

        if (amount > 0) {
            ILOVE20Token(tokenAddress).transfer(msg.sender, amount);
        }

        emit ClaimReward(tokenAddress, msg.sender, actionId, round, amount);
    }

    // ============ Internal Functions ============

    function _prepareRewardIfNeeded(uint256 round) internal {
        if (_reward[round] > 0) return;

        uint256 totalActionReward = _mint.mintActionReward(
            tokenAddress,
            round,
            actionId
        );
        _reward[round] = totalActionReward;
    }

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
    ) internal view returns (uint256) {
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
