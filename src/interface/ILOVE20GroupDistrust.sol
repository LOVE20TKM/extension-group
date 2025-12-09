// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

/// @title ILOVE20GroupDistrust
/// @notice Interface for singleton distrust voting contract
/// @dev Data is stored by extension address, queried by tokenAddress + actionId
interface ILOVE20GroupDistrust {
    // ============ Errors ============

    error NotRegisteredExtension();
    error NotGovernor();
    error DistrustVoteExceedsLimit();
    error InvalidReason();

    // ============ Events ============

    event DistrustVote(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        address groupOwner,
        address voter,
        uint256 amount,
        string reason
    );

    // ============ Write Functions ============

    /// @notice Submit a distrust vote against a group owner
    /// @param tokenAddress The token address
    /// @param actionId The action ID
    /// @param groupOwner The group owner being voted against
    /// @param amount The vote amount
    /// @param reason The reason for distrust
    function distrustVote(
        address tokenAddress,
        uint256 actionId,
        address groupOwner,
        uint256 amount,
        string calldata reason
    ) external;

    // ============ View Functions ============

    /// @notice Get total verify votes for an extension in a round
    function totalVerifyVotes(
        address tokenAddress,
        uint256 actionId,
        uint256 round
    ) external view returns (uint256);

    /// @notice Get total distrust votes for a group owner in a round
    function distrustVotesByGroupOwner(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        address groupOwner
    ) external view returns (uint256);

    /// @notice Get distrust votes by groupId (convenience method)
    function distrustVotesByGroupId(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        uint256 groupId
    ) external view returns (uint256);

    /// @notice Get distrust votes by a specific voter for a group owner
    function distrustVotesByVoterByGroupOwner(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        address voter,
        address groupOwner
    ) external view returns (uint256);

    /// @notice Get the distrust reason
    function distrustReason(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        address voter,
        address groupOwner
    ) external view returns (string memory);
}
