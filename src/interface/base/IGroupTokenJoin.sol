// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

/// @title IGroupTokenJoin
/// @notice Interface for token-based group joining
interface IGroupTokenJoin {
    // ============ Errors ============

    error InvalidJoinTokenAddress();
    error JoinAmountZero();
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
        uint256 indexed round
    );
    event Exit(
        uint256 indexed groupId,
        address indexed account,
        uint256 amount,
        uint256 indexed round
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
    function accountsByGroupIdCount(
        uint256 groupId
    ) external view returns (uint256);
    function accountsByGroupIdAtIndex(
        uint256 groupId,
        uint256 index
    ) external view returns (address);

    function groupIdByAccountByRound(
        address account,
        uint256 round
    ) external view returns (uint256);

    function totalJoinedAmountByGroupIdByRound(
        uint256 groupId,
        uint256 round
    ) external view returns (uint256);

    function totalJoinedAmount() external view returns (uint256);
    function totalJoinedAmountByRound(
        uint256 round
    ) external view returns (uint256);
}
