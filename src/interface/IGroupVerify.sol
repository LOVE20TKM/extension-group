// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

uint256 constant MAX_ORIGIN_SCORE = 100;
uint256 constant PRECISION = 1e18;

interface IGroupVerify {
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
    error ExtensionNotInitialized();

    event VerifyWithOriginScores(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        uint256 groupId,
        uint256 startIndex,
        uint256 count,
        bool isComplete
    );
    event SetGroupDelegatedVerifier(
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

    function initialize(address factory_) external;

    function FACTORY_ADDRESS() external view returns (address);

    function verifyWithOriginScores(
        address extension,
        uint256 groupId,
        uint256 startIndex,
        uint256[] calldata originScores
    ) external;

    function setGroupDelegatedVerifier(
        address extension,
        uint256 groupId,
        address delegatedVerifier
    ) external;

    function distrustVote(
        address extension,
        address groupOwner,
        uint256 amount,
        string calldata reason
    ) external;

    function originScoreByAccount(
        address extension,
        uint256 round,
        address account
    ) external view returns (uint256);

    function accountScore(
        address extension,
        uint256 round,
        address account
    ) external view returns (uint256);

    function totalAccountScore(
        address extension,
        uint256 round,
        uint256 groupId
    ) external view returns (uint256);

    function capacityReductionByGroupId(
        address extension,
        uint256 round,
        uint256 groupId
    ) external view returns (uint256);

    function scoreByGroupId(
        address extension,
        uint256 round,
        uint256 groupId
    ) external view returns (uint256);

    function score(
        address extension,
        uint256 round
    ) external view returns (uint256);

    function delegatedVerifierByGroupId(
        address extension,
        uint256 groupId
    ) external view returns (address);

    function canVerify(
        address extension,
        address account,
        uint256 groupId
    ) external view returns (bool);

    function verifiedAccountCount(
        address extension,
        uint256 round,
        uint256 groupId
    ) external view returns (uint256);

    function isVerified(
        address extension,
        uint256 round,
        uint256 groupId
    ) external view returns (bool);

    function verifiers(
        address extension,
        uint256 round
    ) external view returns (address[] memory);

    function verifiersCount(
        address extension,
        uint256 round
    ) external view returns (uint256);

    function verifiersAtIndex(
        address extension,
        uint256 round,
        uint256 index
    ) external view returns (address);

    function verifierByGroupId(
        address extension,
        uint256 round,
        uint256 groupId
    ) external view returns (address);

    function groupIdsByVerifier(
        address extension,
        uint256 round,
        address verifier
    ) external view returns (uint256[] memory);

    function groupIdsByVerifierCount(
        address extension,
        uint256 round,
        address verifier
    ) external view returns (uint256);

    function groupIdsByVerifierAtIndex(
        address extension,
        uint256 round,
        address verifier,
        uint256 index
    ) external view returns (uint256);

    function verifiedGroupIds(
        address extension,
        uint256 round
    ) external view returns (uint256[] memory);

    function distrustVotesByGroupOwner(
        address extension,
        uint256 round,
        address groupOwner
    ) external view returns (uint256);

    function distrustVotesByGroupId(
        address extension,
        uint256 round,
        uint256 groupId
    ) external view returns (uint256);

    function distrustVotesByVoterByGroupOwner(
        address extension,
        uint256 round,
        address voter,
        address groupOwner
    ) external view returns (uint256);

    function distrustReason(
        address extension,
        uint256 round,
        address voter,
        address groupOwner
    ) external view returns (string memory);
}
