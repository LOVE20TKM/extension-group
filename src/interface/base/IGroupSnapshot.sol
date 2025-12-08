// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

/// @title IGroupSnapshot
/// @notice Interface for group snapshot management
interface IGroupSnapshot {
    // ============ Errors ============

    error NoSnapshotForFutureRound();

    // ============ Events ============

    event SnapshotCreate(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        uint256 groupId
    );

    // ============ Write Functions ============

    function snapshotIfNeeded(uint256 groupId) external;

    // ============ View Functions ============

    // Accounts by GroupId

    function snapshotAccountsByGroupId(
        uint256 round,
        uint256 groupId
    ) external view returns (address[] memory);

    function snapshotAccountsByGroupIdCount(
        uint256 round,
        uint256 groupId
    ) external view returns (uint256);

    function snapshotAccountsByGroupIdAtIndex(
        uint256 round,
        uint256 groupId,
        uint256 index
    ) external view returns (address);

    // Amount

    function snapshotAmountByAccount(
        uint256 round,
        address account
    ) external view returns (uint256);

    function snapshotAmountByGroupId(
        uint256 round,
        uint256 groupId
    ) external view returns (uint256);

    function snapshotAmount(uint256 round) external view returns (uint256);

    // GroupIds

    function snapshotGroupIds(
        uint256 round
    ) external view returns (uint256[] memory);

    function snapshotGroupIdsCount(
        uint256 round
    ) external view returns (uint256);

    function snapshotGroupIdsAtIndex(
        uint256 round,
        uint256 index
    ) external view returns (uint256);
}

