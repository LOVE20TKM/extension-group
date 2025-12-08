// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

/// @title IGroupDistrust
/// @notice Interface for distrust voting mechanism against group owners
interface IGroupDistrust {
    // ============ Errors ============

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

    function distrustVote(
        address groupOwner,
        uint256 amount,
        string calldata reason
    ) external;

    // ============ View Functions ============

    function distrustVotesByGroupOwner(
        uint256 round,
        address groupOwner
    ) external view returns (uint256);

    function distrustVotesByGroupId(
        uint256 round,
        uint256 groupId
    ) external view returns (uint256);

    /// @notice Get distrust ratio components for a group owner
    /// @return distrustVotes Distrust votes received by the group owner (numerator)
    /// @return totalVerifyVotes Total non-abstain verify votes (denominator)
    function distrustRatioByGroupOwner(
        uint256 round,
        address groupOwner
    ) external view returns (uint256 distrustVotes, uint256 totalVerifyVotes);

    /// @notice Get distrust votes for a specific groupOwner by a voter
    function distrustVotesByVoterByGroupOwner(
        uint256 round,
        address voter,
        address groupOwner
    ) external view returns (uint256);

    /// @notice Get distrust reason for a specific groupOwner by a voter
    function distrustReason(
        uint256 round,
        address voter,
        address groupOwner
    ) external view returns (string memory);
}

