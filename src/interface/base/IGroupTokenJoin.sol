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
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        uint256 indexed groupId,
        address account,
        uint256 amount
    );
    event Exit(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        uint256 indexed groupId,
        address account,
        uint256 amount
    );

    // ============ Structs ============

    struct JoinInfo {
        uint256 joinedRound;
        uint256 amount;
        uint256 groupId;
    }

    // ============ Write Functions ============

    /// @notice Join a group with tokens (can add more tokens by calling again)
    function join(
        uint256 groupId,
        uint256 amount,
        string[] memory verificationInfos
    ) external;

    // ============ View Functions ============

    function joinInfo(
        address account
    )
        external
        view
        returns (uint256 joinedRound, uint256 amount, uint256 groupId);

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
