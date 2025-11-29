// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

/// @title IGroupTokenJoin
/// @notice Interface for token-based group joining
interface IGroupTokenJoin {
    // ============ Errors ============

    error InvalidAddress();
    error InvalidAmount();
    error AlreadyInOtherGroup();
    error NotInGroup();
    error AmountBelowMinimum();
    error AmountExceedsAccountCap();
    error GroupCapacityFull();
    error CannotJoinDeactivatedGroup();

    // ============ Events ============

    event Join(
        uint256 indexed groupId,
        address indexed account,
        uint256 amount,
        uint256 round
    );
    event Exit(
        uint256 indexed groupId,
        address indexed account,
        uint256 amount,
        uint256 round
    );

    // ============ Structs ============

    struct JoinInfo {
        uint256 groupId;
        uint256 amount;
        uint256 joinedRound;
    }

    // ============ Write Functions ============

    /// @notice Join a group with tokens (can add more tokens by calling again)
    function join(uint256 groupId, uint256 amount) external;

    // ============ View Functions ============

    function joinInfo(address account) external view returns (JoinInfo memory);

    function accountsByGroupId(
        uint256 groupId
    ) external view returns (address[] memory);

    function groupIdByAccountByRound(
        address account,
        uint256 round
    ) external view returns (uint256);

    function totalJoinedAmountByGroupIdByRound(
        uint256 groupId,
        uint256 round
    ) external view returns (uint256);
}
