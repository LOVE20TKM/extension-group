// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

/// @title IGroupSnapshot
/// @notice Interface for group snapshot management
interface IGroupSnapshot {
    // ============ Errors ============

    error NoSnapshotForFutureRound();

    // ============ Events ============

    event SnapshotCreated(uint256 indexed round, uint256 indexed groupId);

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
    event GroupDelegatedVerifierSet(
        uint256 indexed groupId,
        address indexed delegatedVerifier
    );

    // ============ Write Functions ============

    function submitOriginScore(
        uint256 groupId,
        uint256[] calldata scores
    ) external;

    function setGroupDelegatedVerifier(
        uint256 groupId,
        address delegatedVerifier
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

    function delegatedVerifierByGroupId(
        uint256 groupId
    ) external view returns (address);

    function canVerify(
        address account,
        uint256 groupId
    ) external view returns (bool);

    // Verifiers (recorded at verification time)

    function verifiers(uint256 round) external view returns (address[] memory);

    function verifiersCount(uint256 round) external view returns (uint256);

    function verifiersAtIndex(
        uint256 round,
        uint256 index
    ) external view returns (address);

    function verifierByGroupId(
        uint256 round,
        uint256 groupId
    ) external view returns (address);

    // GroupIds by Verifier

    function groupIdsByVerifier(
        uint256 round,
        address verifier
    ) external view returns (uint256[] memory);

    function groupIdsByVerifierCount(
        uint256 round,
        address verifier
    ) external view returns (uint256);

    function groupIdsByVerifierAtIndex(
        uint256 round,
        address verifier,
        uint256 index
    ) external view returns (uint256);
}

/// @title IGroupDistrust
/// @notice Interface for distrust voting mechanism against group owners
interface IGroupDistrust {
    // ============ Errors ============

    error NotGovernor();
    error DistrustVoteExceedsLimit();
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

/// @title IGroupManualScore
/// @notice Combined interface for manual scoring functionality
interface IGroupManualScore is IGroupSnapshot, IGroupScore, IGroupDistrust {}
