// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {GroupTokenJoin} from "./GroupTokenJoin.sol";
import {IGroupSnapshot} from "../interface/base/IGroupSnapshot.sol";
import {ILOVE20GroupManager} from "../interface/ILOVE20GroupManager.sol";

/// @title GroupTokenJoinSnapshot
/// @notice Handles snapshot creation for token-join group participation data
abstract contract GroupTokenJoinSnapshot is GroupTokenJoin, IGroupSnapshot {
    // ============ State ============

    /// @dev round => groupId => accounts snapshot
    mapping(uint256 => mapping(uint256 => address[]))
        internal _snapshotAccountsByGroupId;

    /// @dev round => account => amount snapshot
    mapping(uint256 => mapping(address => uint256))
        internal _snapshotAmountByAccount;

    /// @dev round => groupId => total amount snapshot
    mapping(uint256 => mapping(uint256 => uint256))
        internal _snapshotAmountByGroupId;

    /// @dev round => total amount snapshot
    mapping(uint256 => uint256) internal _snapshotAmount;

    /// @dev round => groupId => whether snapshot exists
    mapping(uint256 => mapping(uint256 => bool)) internal _hasSnapshot;

    /// @dev round => list of snapshotted group ids
    mapping(uint256 => uint256[]) internal _snapshotGroupIds;

    // ============ IGroupSnapshot Implementation ============

    /// @inheritdoc IGroupSnapshot
    function snapshotIfNeeded(uint256 groupId) public {
        _snapshotIfNeeded(groupId);
    }

    /// @inheritdoc IGroupSnapshot
    function snapshotAccountsByGroupId(
        uint256 round,
        uint256 groupId
    ) external view returns (address[] memory) {
        return _snapshotAccountsByGroupId[round][groupId];
    }

    /// @inheritdoc IGroupSnapshot
    function snapshotAccountsByGroupIdCount(
        uint256 round,
        uint256 groupId
    ) external view returns (uint256) {
        return _snapshotAccountsByGroupId[round][groupId].length;
    }

    /// @inheritdoc IGroupSnapshot
    function snapshotAccountsByGroupIdAtIndex(
        uint256 round,
        uint256 groupId,
        uint256 index
    ) external view returns (address) {
        return _snapshotAccountsByGroupId[round][groupId][index];
    }

    /// @inheritdoc IGroupSnapshot
    function snapshotAmountByAccount(
        uint256 round,
        address account
    ) external view returns (uint256) {
        return _snapshotAmountByAccount[round][account];
    }

    /// @inheritdoc IGroupSnapshot
    function snapshotAmountByGroupId(
        uint256 round,
        uint256 groupId
    ) external view returns (uint256) {
        return _snapshotAmountByGroupId[round][groupId];
    }

    /// @inheritdoc IGroupSnapshot
    function snapshotAmount(uint256 round) external view returns (uint256) {
        return _snapshotAmount[round];
    }

    /// @inheritdoc IGroupSnapshot
    function snapshotGroupIds(
        uint256 round
    ) external view returns (uint256[] memory) {
        return _snapshotGroupIds[round];
    }

    /// @inheritdoc IGroupSnapshot
    function snapshotGroupIdsCount(
        uint256 round
    ) external view returns (uint256) {
        return _snapshotGroupIds[round].length;
    }

    /// @inheritdoc IGroupSnapshot
    function snapshotGroupIdsAtIndex(
        uint256 round,
        uint256 index
    ) external view returns (uint256) {
        return _snapshotGroupIds[round][index];
    }

    // ============ Internal Functions ============

    function _snapshotIfNeeded(uint256 groupId) internal {
        uint256 round = _verify.currentRound();
        if (_hasSnapshot[round][groupId]) return;
        if (!_groupManager.isGroupActive(tokenAddress, actionId, groupId))
            return;

        _hasSnapshot[round][groupId] = true;
        _snapshotGroupIds[round].push(groupId);

        // Snapshot accounts
        address[] storage currentAccounts = _accountsByGroupId[groupId];
        uint256 accountCount = currentAccounts.length;

        for (uint256 i = 0; i < accountCount; i++) {
            address account = currentAccounts[i];
            _snapshotAccountsByGroupId[round][groupId].push(account);

            uint256 amount = _joinInfo[account].amount;
            _snapshotAmountByAccount[round][account] = amount;
        }

        // Snapshot group amount
        uint256 groupAmount = _totalJoinedAmountByGroupId[groupId];
        _snapshotAmountByGroupId[round][groupId] = groupAmount;
        _snapshotAmount[round] += groupAmount;

        emit SnapshotCreate(tokenAddress, round, actionId, groupId);
    }

    // ============ Override Hooks ============

    function _beforeJoin(
        uint256 groupId,
        address /* account */
    ) internal virtual override {
        _snapshotIfNeeded(groupId);
    }

    function _beforeExit(
        uint256 groupId,
        address /* account */
    ) internal virtual override {
        _snapshotIfNeeded(groupId);
    }
}
