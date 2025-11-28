// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IGroupTokenJoin {
    // ============================================
    // ERRORS
    // ============================================

    error AlreadyInOtherGroup();
    error NotInGroup();
    error AmountBelowMinimum();
    error AmountExceedsAccountCap();
    error GroupCapacityFull();
    error CannotJoinStoppedGroup();

    // ============================================
    // EVENTS
    // ============================================

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

    // ============================================
    // STRUCTS
    // ============================================

    /// @notice Account participation information
    struct JoinInfo {
        uint256 groupId;
        uint256 amount;
        uint256 joinedRound;
    }

    // ============================================
    // FUNCTIONS
    // ============================================

    /// @notice Join a group (can be called multiple times to add more tokens)
    function join(uint256 groupId, uint256 amount) external;

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /// @notice Get account's participation information
    function getJoinInfo(
        address account
    ) external view returns (JoinInfo memory);

    /// @notice Get all accounts in a group
    function getGroupAccounts(
        uint256 groupId
    ) external view returns (address[] memory);

    /// @notice Check if account can join group
    function canAccountJoinGroup(
        address account,
        uint256 groupId,
        uint256 amount
    ) external view returns (bool canJoin, string memory reason);

    /// @notice Get which group an account was in during a specific round
    function getAccountGroupByRound(
        address account,
        uint256 round
    ) external view returns (uint256 groupId);

    /// @notice Get group's total joined amount during a specific round
    function getGroupTotalByRound(
        uint256 groupId,
        uint256 round
    ) external view returns (uint256);
}
