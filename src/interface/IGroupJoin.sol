// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

/// @title IGroupJoin
/// @notice Interface for GroupJoin singleton contract
interface IGroupJoin {
    // ============ Errors ============

    error InvalidJoinTokenAddress();
    error JoinAmountZero();
    error AlreadyInOtherGroup();
    error NotInGroup();
    error AmountBelowMinimum();
    error AmountExceedsAccountCap();
    error OwnerCapacityExceeded();
    error GroupCapacityExceeded();
    error GroupAccountsFull();
    error CannotJoinDeactivatedGroup();
    error InvalidFactory();
    error AlreadyInitialized();

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

    // ============ Initialization ============

    /// @notice Initialize the contract with Factory address (can only be called once)
    function initialize(address factory_) external;

    /// @notice Get the Factory address
    function FACTORY_ADDRESS() external view returns (address);

    // ============ Write Functions ============

    /// @notice Join a group with tokens (can add more tokens by calling again)
    /// @param tokenAddress The token address
    /// @param actionId The action ID
    /// @param groupId The group ID
    /// @param amount The amount of tokens to join
    /// @param verificationInfos Verification information array
    function join(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        uint256 amount,
        string[] memory verificationInfos
    ) external;

    /// @notice Exit from the current group
    /// @param tokenAddress The token address
    /// @param actionId The action ID
    function exit(address tokenAddress, uint256 actionId) external;

    // ============ View Functions ============

    function joinInfo(
        address tokenAddress,
        uint256 actionId,
        address account
    )
        external
        view
        returns (uint256 joinedRound, uint256 amount, uint256 groupId);

    function accountsByGroupIdCount(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId
    ) external view returns (uint256);

    function accountsByGroupIdAtIndex(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        uint256 index
    ) external view returns (address);

    function groupIdByAccountByRound(
        address tokenAddress,
        uint256 actionId,
        address account,
        uint256 round
    ) external view returns (uint256);

    function totalJoinedAmountByGroupId(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId
    ) external view returns (uint256);

    function totalJoinedAmountByGroupIdByRound(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        uint256 round
    ) external view returns (uint256);

    function totalJoinedAmount(
        address tokenAddress,
        uint256 actionId
    ) external view returns (uint256);

    function totalJoinedAmountByRound(
        address tokenAddress,
        uint256 actionId,
        uint256 round
    ) external view returns (uint256);

    // ============ Round-based Query Functions ============

    /// @notice Get the number of accounts in a group at a specific round
    function accountCountByGroupIdByRound(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        uint256 round
    ) external view returns (uint256);

    /// @notice Get the account at a specific index in a group for a given round
    function accountByGroupIdAndIndexByRound(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        uint256 index,
        uint256 round
    ) external view returns (address);

    /// @notice Get the amount of tokens an account has at a specific round
    function amountByAccountByRound(
        address tokenAddress,
        uint256 actionId,
        address account,
        uint256 round
    ) external view returns (uint256);
}
