// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

// ============ Constants ============

uint256 constant MAX_ORIGIN_SCORE = 100;

/// @title IGroupVerify
/// @notice Interface for GroupVerify singleton contract (combines IGroupScore and IGroupDistrust functionality)
/// @dev Note: Does not inherit IGroupScore directly due to function signature differences (adds tokenAddress and actionId parameters)
interface IGroupVerify {
    // ============ Errors ============

    error InvalidFactory();
    error AlreadyInitialized();
    error NotVerifier();
    error ScoreExceedsMax();
    error NoRemainingVerifyCapacity();
    error AlreadyVerified();
    error NoDataForRound();
    error InvalidStartIndex();
    error ScoresExceedAccountCount();
    error NotRegisteredExtension();
    error NotGovernor();
    error DistrustVoteExceedsLimit();
    error InvalidReason();

    // ============ Events ============

    event VerifyWithOriginScores(
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
    event DistrustVote(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        address groupOwner,
        address voter,
        uint256 amount,
        string reason
    );

    // ============ Initialization ============

    /// @notice Initialize the contract with Factory address (can only be called once)
    function initialize(address factory_) external;

    /// @notice Get the Factory address
    function FACTORY_ADDRESS() external view returns (address);

    // ============ Write Functions ============

    /// @notice Verify with origin scores (supports both full and batch submission)
    /// @param tokenAddress The token address
    /// @param actionId The action ID
    /// @param groupId The group ID
    /// @param startIndex Starting index in the accounts array (0 for first/full submission)
    /// @param originScores Array of scores for accounts starting at startIndex
    function verifyWithOriginScores(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        uint256 startIndex,
        uint256[] calldata originScores
    ) external;

    /// @notice Set delegated verifier for a group
    /// @param tokenAddress The token address
    /// @param actionId The action ID
    /// @param groupId The group ID
    /// @param delegatedVerifier The delegated verifier address
    function setGroupDelegatedVerifier(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        address delegatedVerifier
    ) external;

    // ============ Write Functions (Distrust) ============

    /// @notice Vote distrust against a group owner
    /// @param tokenAddress The token address
    /// @param actionId The action ID
    /// @param groupOwner The group owner address
    /// @param amount The amount of distrust votes
    /// @param reason The reason for distrust
    function distrustVote(
        address tokenAddress,
        uint256 actionId,
        address groupOwner,
        uint256 amount,
        string calldata reason
    ) external;

    // ============ View Functions ============

    function originScoreByAccount(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        address account
    ) external view returns (uint256);

    function scoreByAccount(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        address account
    ) external view returns (uint256);

    function scoreByGroupId(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        uint256 groupId
    ) external view returns (uint256);

    function capacityReductionByGroupId(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        uint256 groupId
    ) external view returns (uint256);

    function score(
        address tokenAddress,
        uint256 actionId,
        uint256 round
    ) external view returns (uint256);

    function delegatedVerifierByGroupId(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId
    ) external view returns (address);

    function canVerify(
        address tokenAddress,
        uint256 actionId,
        address account,
        uint256 groupId
    ) external view returns (bool);

    function verifiedAccountCount(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        uint256 groupId
    ) external view returns (uint256);

    function isVerified(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        uint256 groupId
    ) external view returns (bool);

    function verifiers(
        address tokenAddress,
        uint256 actionId,
        uint256 round
    ) external view returns (address[] memory);

    function verifiersCount(
        address tokenAddress,
        uint256 actionId,
        uint256 round
    ) external view returns (uint256);

    function verifiersAtIndex(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        uint256 index
    ) external view returns (address);

    function verifierByGroupId(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        uint256 groupId
    ) external view returns (address);

    function groupIdsByVerifier(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        address verifier
    ) external view returns (uint256[] memory);

    function groupIdsByVerifierCount(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        address verifier
    ) external view returns (uint256);

    function groupIdsByVerifierAtIndex(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        address verifier,
        uint256 index
    ) external view returns (uint256);

    /// @notice Get verified group IDs for a round
    function verifiedGroupIds(
        address tokenAddress,
        uint256 actionId,
        uint256 round
    ) external view returns (uint256[] memory);

    /// @notice Get total score of all accounts in a group (before distrust and capacity reduction)
    function totalScoreByGroupId(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        uint256 groupId
    ) external view returns (uint256);

    // ============ View Functions (Distrust) ============

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
