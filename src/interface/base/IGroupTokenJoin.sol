// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IGroupTokenJoin {
    // ============================================
    // ERRORS
    // ============================================

    error AlreadyInGroup();
    error NotInGroup();
    error NotInThisGroup();
    error AmountBelowMinimum();
    error AmountExceedsAccountCap();
    error GroupCapacityFull();
    error CannotJoinStoppedGroup();

    // ============================================
    // EVENTS
    // ============================================

    event JoinGroup(
        uint256 indexed groupId,
        address indexed account,
        uint256 amount,
        uint256 round
    );

    event ExitGroup(
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

    /// @notice Join a group
    function joinGroup(uint256 groupId, uint256 amount) external;

    /// @notice Exit from a group
    function exitGroup(uint256 groupId) external;

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
}
