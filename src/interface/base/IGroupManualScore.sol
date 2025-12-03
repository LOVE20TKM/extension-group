// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

/// @title IGroupSnapshot
/// @notice Interface for group snapshot management
interface IGroupSnapshot {
    // ============ Errors ============

    error SnapshotAlreadyExists();
    error NoSnapshotForFutureRound();

    // ============ Events ============

    event SnapshotCreated(uint256 indexed round, uint256 indexed groupId);

    // ============ Write Functions ============

    function snapshotIfNeeded(uint256 groupId) external;

    // ============ View Functions ============

    function snapshotAccountsByGroupId(
        uint256 round,
        uint256 groupId
    ) external view returns (address[] memory);

    function snapshotAmountByAccount(
        uint256 round,
        address account
    ) external view returns (uint256);

    function snapshotAmountByGroupId(
        uint256 round,
        uint256 groupId
    ) external view returns (uint256);

    function snapshotAmount(uint256 round) external view returns (uint256);

    function snapshotGroupIds(
        uint256 round
    ) external view returns (uint256[] memory);

    function snapshotGroupIdsCount(
        uint256 round
    ) external view returns (uint256);

    function snapshotGroupIdAtIndex(
        uint256 round,
        uint256 index
    ) external view returns (uint256);
}

// ============ Constants ============

uint256 constant MAX_ORIGIN_SCORE = 100;

/// @title IGroupScore
/// @notice Interface for group verification scoring
interface IGroupScore {
    // ============ Errors ============

    error NotVerifier();
    error ScoreExceedsMax();
    error ScoresCountMismatch();
    error VerifierCapacityExceeded();
    error VerificationAlreadySubmitted();
    error NoSnapshotForRound();

    // ============ Events ============

    event ScoreSubmitted(uint256 indexed round, uint256 indexed groupId);

    // ============ Write Functions ============

    function submitOriginScore(
        uint256 groupId,
        uint256[] calldata scores
    ) external;

    // ============ View Functions ============

    function originScoreByAccount(
        uint256 round,
        address account
    ) external view returns (uint256);

    function scoreByAccount(
        uint256 round,
        address account
    ) external view returns (uint256);

    function scoreByGroupId(
        uint256 round,
        uint256 groupId
    ) external view returns (uint256);

    function score(uint256 round) external view returns (uint256);
}

/// @title IGroupDistrust
/// @notice Interface for distrust voting mechanism against group owners
interface IGroupDistrust {
    // ============ Errors ============

    error NotGovernor();
    error DistrustVoteExceedsLimit();
    error AlreadyVotedDistrust();
    error InvalidReason();

    // ============ Events ============

    event DistrustVoted(
        uint256 indexed round,
        address indexed groupOwner,
        address indexed voter,
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
}

/// @title IGroupManualScore
/// @notice Combined interface for manual scoring functionality
interface IGroupManualScore is IGroupSnapshot, IGroupScore, IGroupDistrust {}
