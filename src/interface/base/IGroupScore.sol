// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

// ============ Constants ============

uint256 constant MAX_ORIGIN_SCORE = 100;

/// @title IGroupScore
/// @notice Interface for group verification scoring
interface IGroupScore {
    // ============ Errors ============

    error NotVerifier();
    error ScoreExceedsMax();
    error NoRemainingVerifyCapacity();
    error VerificationAlreadySubmitted();
    error NoDataForRound();
    error InvalidStartIndex();
    error ScoresExceedAccountCount();

    // ============ Events ============

    event ScoreSubmit(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        uint256 groupId,
        uint256 startIndex,
        uint256 count,
        bool isComplete
    );
    event GroupDelegatedVerifierSet(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        uint256 indexed groupId,
        address delegatedVerifier
    );

    // ============ Write Functions ============

    /// @notice Submit origin scores (supports both full and batch submission)
    /// @param groupId The group ID
    /// @param startIndex Starting index in the accounts array (0 for first/full submission)
    /// @param originScores Array of scores for accounts starting at startIndex
    function submitOriginScore(
        uint256 groupId,
        uint256 startIndex,
        uint256[] calldata originScores
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

    function capacityReductionByGroupId(
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

    function submittedCount(
        uint256 round,
        uint256 groupId
    ) external view returns (uint256);

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
