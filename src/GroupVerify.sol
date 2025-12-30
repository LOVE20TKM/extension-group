// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupVerify} from "./interface/IGroupVerify.sol";
import {IGroupJoin} from "./interface/IGroupJoin.sol";
import {
    ILOVE20ExtensionGroupActionFactory
} from "./interface/ILOVE20ExtensionGroupActionFactory.sol";
import {
    IExtensionCenter
} from "@extension/src/interface/IExtensionCenter.sol";
import {ILOVE20Submit, ActionInfo} from "@core/interfaces/ILOVE20Submit.sol";
import {IGroupManager} from "./interface/IGroupManager.sol";
import {ILOVE20Group} from "@group/interfaces/ILOVE20Group.sol";
import {ILOVE20Verify} from "@core/interfaces/ILOVE20Verify.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {MAX_ORIGIN_SCORE} from "./interface/IGroupVerify.sol";

/// @title GroupVerify
/// @notice Singleton contract handling verification scoring and distrust voting
/// @dev Users call directly, uses extension address from tokenAddress and actionId
contract GroupVerify is IGroupVerify, ReentrancyGuard {
    // ============ Immutables ============

    ILOVE20ExtensionGroupActionFactory internal _factory;
    IExtensionCenter internal _center;
    IGroupManager internal _groupManager;
    ILOVE20Group internal _group;
    ILOVE20Verify internal _verify;
    IGroupJoin internal _groupJoin;

    // ============ State ============

    address internal _factoryAddress;
    bool internal _initialized;

    // extension => groupId => delegated verifier address
    mapping(address => mapping(uint256 => address))
        internal _delegatedVerifierByGroupId;
    // extension => groupId => group owner at the time of delegation
    mapping(address => mapping(uint256 => address))
        internal _delegatedVerifierOwnerByGroupId;
    // extension => round => account => origin score [0-100]
    mapping(address => mapping(uint256 => mapping(address => uint256)))
        internal _originScoreByAccount;
    // extension => round => groupId => total score of all accounts in group
    mapping(address => mapping(uint256 => mapping(uint256 => uint256)))
        internal _totalScoreByGroupId;
    // extension => round => groupId => group score (with distrust applied)
    mapping(address => mapping(uint256 => mapping(uint256 => uint256)))
        internal _scoreByGroupId;
    // extension => round => total score of all verified groups
    mapping(address => mapping(uint256 => uint256)) internal _score;
    // extension => round => groupId => whether verification is complete
    mapping(address => mapping(uint256 => mapping(uint256 => bool)))
        internal _isVerified;
    // extension => round => list of verified group ids
    mapping(address => mapping(uint256 => uint256[]))
        internal _verifiedGroupIds;
    // extension => round => groupId => verifier address
    mapping(address => mapping(uint256 => mapping(uint256 => address)))
        internal _verifierByGroupId;
    // extension => round => verifier => list of verified group ids
    mapping(address => mapping(uint256 => mapping(address => uint256[])))
        internal _groupIdsByVerifier;
    // extension => round => list of verifiers
    mapping(address => mapping(uint256 => address[])) internal _verifiers;
    // extension => round => groupId => verified account count
    mapping(address => mapping(uint256 => mapping(uint256 => uint256)))
        internal _verifiedAccountCount;
    // extension => round => groupId => accumulated total score
    mapping(address => mapping(uint256 => mapping(uint256 => uint256)))
        internal _batchTotalScore;
    // extension => round => groupId => capacity reduction factor
    mapping(address => mapping(uint256 => mapping(uint256 => uint256)))
        internal _capacityReductionByGroupId;

    // Distrust state (from LOVE20GroupDistrust)
    // extension => round => groupOwner => total distrust votes
    mapping(address => mapping(uint256 => mapping(address => uint256)))
        internal _distrustVotesByGroupOwner;
    // extension => round => voter => groupOwner => distrust votes
    mapping(address => mapping(uint256 => mapping(address => mapping(address => uint256))))
        internal _distrustVotesByVoterByGroupOwner;
    // extension => round => voter => groupOwner => reason
    mapping(address => mapping(uint256 => mapping(address => mapping(address => string))))
        internal _distrustReason;

    // ============ Constructor ============

    constructor() {
        // Factory will be set via initialize()
    }

    // ============ Initialization ============

    /// @inheritdoc IGroupVerify
    function initialize(address factory_) external {
        if (_initialized) revert AlreadyInitialized();
        if (factory_ == address(0)) revert InvalidFactory();

        _factoryAddress = factory_;
        _factory = ILOVE20ExtensionGroupActionFactory(factory_);
        _center = IExtensionCenter(_factory.center());
        _groupManager = IGroupManager(_factory.GROUP_MANAGER_ADDRESS());
        _group = ILOVE20Group(_factory.GROUP_ADDRESS());
        _verify = ILOVE20Verify(_center.verifyAddress());
        _groupJoin = IGroupJoin(_factory.GROUP_JOIN_ADDRESS());

        _initialized = true;
    }

    // ============ Config Functions ============

    /// @inheritdoc IGroupVerify
    function FACTORY_ADDRESS() external view override returns (address) {
        return _factoryAddress;
    }

    // ============ Modifiers ============

    modifier onlyValidExtension(address tokenAddress, uint256 actionId) {
        ILOVE20Submit submit = ILOVE20Submit(_center.submitAddress());
        ActionInfo memory actionInfo = submit.actionInfo(
            tokenAddress,
            actionId
        );
        address extension = actionInfo.body.whiteListAddress;

        if (!_factory.exists(extension)) {
            revert InvalidFactory();
        }
        _;
    }

    modifier onlyGroupOwner(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId
    ) {
        address extension = _getExtension(tokenAddress, actionId);
        if (_group.ownerOf(groupId) != msg.sender)
            revert IGroupManager.OnlyGroupOwner();
        _;
    }

    // ============ Internal Helpers ============

    /// @dev Get extension address from tokenAddress and actionId
    function _getExtension(
        address tokenAddress,
        uint256 actionId
    ) internal view returns (address extension) {
        ILOVE20Submit submit = ILOVE20Submit(_center.submitAddress());
        ActionInfo memory actionInfo = submit.actionInfo(
            tokenAddress,
            actionId
        );
        extension = actionInfo.body.whiteListAddress;
        if (extension == address(0)) revert InvalidFactory();
    }

    // ============ Write Functions ============

    /// @inheritdoc IGroupVerify
    function setGroupDelegatedVerifier(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        address delegatedVerifier
    ) external override onlyGroupOwner(tokenAddress, actionId, groupId) {
        address extension = _getExtension(tokenAddress, actionId);
        _delegatedVerifierByGroupId[extension][groupId] = delegatedVerifier;
        _delegatedVerifierOwnerByGroupId[extension][
            groupId
        ] = delegatedVerifier == address(0) ? address(0) : msg.sender;
        emit GroupDelegatedVerifierSet(
            tokenAddress,
            _verify.currentRound(),
            actionId,
            groupId,
            delegatedVerifier
        );
    }

    /// @inheritdoc IGroupVerify
    function verifyWithOriginScores(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        uint256 startIndex,
        uint256[] calldata originScores
    ) external override onlyValidExtension(tokenAddress, actionId) {
        address extension = _getExtension(tokenAddress, actionId);
        uint256 currentRound = _verify.currentRound();

        _checkVerifier(extension, groupId);
        if (_isVerified[extension][currentRound][groupId]) {
            revert AlreadyVerified();
        }

        _processVerificationBatch(
            extension,
            tokenAddress,
            actionId,
            currentRound,
            groupId,
            startIndex,
            originScores
        );
    }

    function _checkVerifier(address extension, uint256 groupId) internal view {
        address groupOwner = _group.ownerOf(groupId);
        bool isValidDelegatedVerifier = msg.sender ==
            _delegatedVerifierByGroupId[extension][groupId] &&
            _delegatedVerifierOwnerByGroupId[extension][groupId] == groupOwner;
        if (msg.sender != groupOwner && !isValidDelegatedVerifier) {
            revert NotVerifier();
        }
    }

    function _processVerificationBatch(
        address extension,
        address tokenAddress,
        uint256 actionId,
        uint256 currentRound,
        uint256 groupId,
        uint256 startIndex,
        uint256[] calldata originScores
    ) internal {
        mapping(uint256 => uint256)
            storage verifiedCount = _verifiedAccountCount[extension][
                currentRound
            ];

        // Validate start index matches verified count (sequential verification)
        if (startIndex != verifiedCount[groupId]) {
            revert InvalidStartIndex();
        }

        // Get account count from GroupJoin
        uint256 accountCount = _groupJoin.accountCountByGroupIdByRound(
            tokenAddress,
            actionId,
            groupId,
            currentRound
        );
        if (startIndex + originScores.length > accountCount) {
            revert ScoresExceedAccountCount();
        }

        // Process scores
        uint256 batchScore = _processScores(
            extension,
            tokenAddress,
            actionId,
            currentRound,
            groupId,
            startIndex,
            originScores
        );

        mapping(uint256 => uint256) storage batchScoreMap = _batchTotalScore[
            extension
        ][currentRound];

        verifiedCount[groupId] += originScores.length;
        batchScoreMap[groupId] += batchScore;
        uint256 finalBatchScore = batchScoreMap[groupId];
        bool isComplete = verifiedCount[groupId] == accountCount;

        emit VerifyWithOriginScores(
            tokenAddress,
            currentRound,
            actionId,
            groupId,
            startIndex,
            originScores.length,
            isComplete
        );

        if (isComplete) {
            _finalizeVerificationComplete(
                extension,
                tokenAddress,
                actionId,
                currentRound,
                groupId,
                finalBatchScore
            );
        }
    }

    function _finalizeVerificationComplete(
        address extension,
        address tokenAddress,
        uint256 actionId,
        uint256 currentRound,
        uint256 groupId,
        uint256 totalScore
    ) internal {
        address groupOwner = _group.ownerOf(groupId);
        _finalizeVerification(
            extension,
            tokenAddress,
            actionId,
            currentRound,
            groupId,
            groupOwner,
            totalScore
        );
    }

    /// @inheritdoc IGroupVerify
    function distrustVote(
        address tokenAddress,
        uint256 actionId,
        address groupOwner,
        uint256 amount,
        string calldata reason
    ) external override onlyValidExtension(tokenAddress, actionId) {
        address extension = _getExtension(tokenAddress, actionId);
        _processDistrustVote(
            extension,
            tokenAddress,
            actionId,
            groupOwner,
            amount,
            reason
        );
    }

    function _processDistrustVote(
        address extension,
        address tokenAddress,
        uint256 actionId,
        address groupOwner,
        uint256 amount,
        string calldata reason
    ) internal {
        address voter = msg.sender;
        uint256 currentRound = _verify.currentRound();

        // Check voter has voted for GroupAction (extension)
        uint256 verifyVotes = _verify.scoreByVerifierByActionIdByAccount(
            tokenAddress,
            currentRound,
            voter,
            actionId,
            extension
        );
        if (verifyVotes == 0) revert NotGovernor();

        // Check accumulated votes don't exceed verify votes
        mapping(address => uint256)
            storage voterVotes = _distrustVotesByVoterByGroupOwner[extension][
                currentRound
            ][voter];
        uint256 currentVotes = voterVotes[groupOwner];
        if (currentVotes + amount > verifyVotes)
            revert DistrustVoteExceedsLimit();

        if (bytes(reason).length == 0) revert InvalidReason();

        // Record vote
        voterVotes[groupOwner] += amount;
        _distrustVotesByGroupOwner[extension][currentRound][
            groupOwner
        ] += amount;
        _distrustReason[extension][currentRound][voter][groupOwner] = reason;

        emit DistrustVote(
            tokenAddress,
            currentRound,
            actionId,
            groupOwner,
            voter,
            amount,
            reason
        );

        // Update distrust for all active groups owned by this owner
        _updateDistrustForOwnerGroups(
            extension,
            tokenAddress,
            actionId,
            currentRound,
            groupOwner
        );
    }

    // ============ View Functions ============

    /// @inheritdoc IGroupVerify
    function originScoreByAccount(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        address account
    ) external view override returns (uint256) {
        address extension = _getExtension(tokenAddress, actionId);
        return _originScoreByAccount[extension][round][account];
    }

    /// @inheritdoc IGroupVerify
    function scoreByAccount(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        address account
    ) external view override returns (uint256) {
        address extension = _getExtension(tokenAddress, actionId);
        return
            _calculateScoreByAccount(
                extension,
                tokenAddress,
                actionId,
                round,
                account
            );
    }

    /// @inheritdoc IGroupVerify
    function scoreByGroupId(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        uint256 groupId
    ) external view override returns (uint256) {
        address extension = _getExtension(tokenAddress, actionId);
        return _scoreByGroupId[extension][round][groupId];
    }

    /// @inheritdoc IGroupVerify
    function capacityReductionByGroupId(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        uint256 groupId
    ) external view override returns (uint256) {
        address extension = _getExtension(tokenAddress, actionId);
        return _capacityReductionByGroupId[extension][round][groupId];
    }

    /// @inheritdoc IGroupVerify
    function score(
        address tokenAddress,
        uint256 actionId,
        uint256 round
    ) external view override returns (uint256) {
        address extension = _getExtension(tokenAddress, actionId);
        return _score[extension][round];
    }

    /// @inheritdoc IGroupVerify
    function delegatedVerifierByGroupId(
        address tokenAddress,
        uint256 actionId,
        uint256 groupId
    ) external view override returns (address) {
        address extension = _getExtension(tokenAddress, actionId);
        address groupOwner = _group.ownerOf(groupId);
        if (_delegatedVerifierOwnerByGroupId[extension][groupId] != groupOwner)
            return address(0);
        return _delegatedVerifierByGroupId[extension][groupId];
    }

    /// @inheritdoc IGroupVerify
    function canVerify(
        address tokenAddress,
        uint256 actionId,
        address account,
        uint256 groupId
    ) external view override returns (bool) {
        address extension = _getExtension(tokenAddress, actionId);
        address groupOwner = _group.ownerOf(groupId);
        bool isValidDelegatedVerifier = account ==
            _delegatedVerifierByGroupId[extension][groupId] &&
            _delegatedVerifierOwnerByGroupId[extension][groupId] == groupOwner;
        return account == groupOwner || isValidDelegatedVerifier;
    }

    /// @inheritdoc IGroupVerify
    function verifiedAccountCount(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        uint256 groupId
    ) external view override returns (uint256) {
        address extension = _getExtension(tokenAddress, actionId);
        return _verifiedAccountCount[extension][round][groupId];
    }

    /// @inheritdoc IGroupVerify
    function isVerified(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        uint256 groupId
    ) external view override returns (bool) {
        address extension = _getExtension(tokenAddress, actionId);
        return _isVerified[extension][round][groupId];
    }

    /// @inheritdoc IGroupVerify
    function verifiers(
        address tokenAddress,
        uint256 actionId,
        uint256 round
    ) external view override returns (address[] memory) {
        address extension = _getExtension(tokenAddress, actionId);
        return _verifiers[extension][round];
    }

    /// @inheritdoc IGroupVerify
    function verifiersCount(
        address tokenAddress,
        uint256 actionId,
        uint256 round
    ) external view override returns (uint256) {
        address extension = _getExtension(tokenAddress, actionId);
        return _verifiers[extension][round].length;
    }

    /// @inheritdoc IGroupVerify
    function verifiersAtIndex(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        uint256 index
    ) external view override returns (address) {
        address extension = _getExtension(tokenAddress, actionId);
        return _verifiers[extension][round][index];
    }

    /// @inheritdoc IGroupVerify
    function verifierByGroupId(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        uint256 groupId
    ) external view override returns (address) {
        address extension = _getExtension(tokenAddress, actionId);
        return _verifierByGroupId[extension][round][groupId];
    }

    /// @inheritdoc IGroupVerify
    function groupIdsByVerifier(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        address verifier
    ) external view override returns (uint256[] memory) {
        address extension = _getExtension(tokenAddress, actionId);
        return _groupIdsByVerifier[extension][round][verifier];
    }

    /// @inheritdoc IGroupVerify
    function groupIdsByVerifierCount(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        address verifier
    ) external view override returns (uint256) {
        address extension = _getExtension(tokenAddress, actionId);
        return _groupIdsByVerifier[extension][round][verifier].length;
    }

    /// @inheritdoc IGroupVerify
    function groupIdsByVerifierAtIndex(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        address verifier,
        uint256 index
    ) external view override returns (uint256) {
        address extension = _getExtension(tokenAddress, actionId);
        return _groupIdsByVerifier[extension][round][verifier][index];
    }

    /// @inheritdoc IGroupVerify
    function verifiedGroupIds(
        address tokenAddress,
        uint256 actionId,
        uint256 round
    ) external view override returns (uint256[] memory) {
        address extension = _getExtension(tokenAddress, actionId);
        return _verifiedGroupIds[extension][round];
    }

    /// @inheritdoc IGroupVerify
    function totalScoreByGroupId(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        uint256 groupId
    ) external view override returns (uint256) {
        address extension = _getExtension(tokenAddress, actionId);
        return _totalScoreByGroupId[extension][round][groupId];
    }

    // ============ View Functions (Distrust) ============

    /// @inheritdoc IGroupVerify
    function totalVerifyVotes(
        address tokenAddress,
        uint256 actionId,
        uint256 round
    ) external view override returns (uint256) {
        address extension = _getExtension(tokenAddress, actionId);
        return
            _verify.scoreByActionIdByAccount(
                tokenAddress,
                round,
                actionId,
                extension
            );
    }

    /// @inheritdoc IGroupVerify
    function distrustVotesByGroupOwner(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        address groupOwner
    ) external view override returns (uint256) {
        address extension = _getExtension(tokenAddress, actionId);
        return _distrustVotesByGroupOwner[extension][round][groupOwner];
    }

    /// @inheritdoc IGroupVerify
    function distrustVotesByGroupId(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        uint256 groupId
    ) external view override returns (uint256) {
        address groupOwner = _group.ownerOf(groupId);
        address extension = _getExtension(tokenAddress, actionId);
        return _distrustVotesByGroupOwner[extension][round][groupOwner];
    }

    /// @inheritdoc IGroupVerify
    function distrustVotesByVoterByGroupOwner(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        address voter,
        address groupOwner
    ) external view override returns (uint256) {
        address extension = _getExtension(tokenAddress, actionId);
        return
            _distrustVotesByVoterByGroupOwner[extension][round][voter][
                groupOwner
            ];
    }

    /// @inheritdoc IGroupVerify
    function distrustReason(
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        address voter,
        address groupOwner
    ) external view override returns (string memory) {
        address extension = _getExtension(tokenAddress, actionId);
        return _distrustReason[extension][round][voter][groupOwner];
    }

    // ============ Internal Functions ============

    function _checkVerifierAndData(
        address extension,
        address tokenAddress,
        uint256 actionId,
        uint256 currentRound,
        uint256 groupId
    ) internal view returns (address groupOwner) {
        groupOwner = _group.ownerOf(groupId);

        bool isValidDelegatedVerifier = msg.sender ==
            _delegatedVerifierByGroupId[extension][groupId] &&
            _delegatedVerifierOwnerByGroupId[extension][groupId] == groupOwner;
        if (msg.sender != groupOwner && !isValidDelegatedVerifier) {
            revert NotVerifier();
        }

        if (_isVerified[extension][currentRound][groupId]) {
            revert AlreadyVerified();
        }

        // Check if group has members at this round
        if (
            _groupJoin.accountCountByGroupIdByRound(
                tokenAddress,
                actionId,
                groupId,
                currentRound
            ) == 0
        ) {
            revert NoDataForRound();
        }
    }

    function _processScores(
        address extension,
        address tokenAddress,
        uint256 actionId,
        uint256 currentRound,
        uint256 groupId,
        uint256 startIndex,
        uint256[] calldata originScores
    ) internal returns (uint256 totalScore) {
        for (uint256 i = 0; i < originScores.length; i++) {
            if (originScores[i] > MAX_ORIGIN_SCORE) revert ScoreExceedsMax();
            address account = _groupJoin.accountByGroupIdAndIndexByRound(
                tokenAddress,
                actionId,
                groupId,
                startIndex + i,
                currentRound
            );
            _originScoreByAccount[extension][currentRound][
                account
            ] = originScores[i];
            totalScore +=
                originScores[i] *
                _groupJoin.amountByAccountByRound(
                    tokenAddress,
                    actionId,
                    account,
                    currentRound
                );
        }
    }

    function _finalizeVerification(
        address extension,
        address tokenAddress,
        uint256 actionId,
        uint256 currentRound,
        uint256 groupId,
        address groupOwner,
        uint256 totalScore
    ) internal {
        // Calculate and store capacity reduction factor
        uint256 capacityReduction = _calculateCapacityReduction(
            extension,
            tokenAddress,
            actionId,
            currentRound,
            groupOwner,
            groupId
        );
        _capacityReductionByGroupId[extension][currentRound][
            groupId
        ] = capacityReduction;

        // Record verifier (NFT owner, not delegated verifier)
        _verifierByGroupId[extension][currentRound][groupId] = groupOwner;

        // Add verifier to list if first verified group for this verifier
        if (
            _groupIdsByVerifier[extension][currentRound][groupOwner].length == 0
        ) {
            _verifiers[extension][currentRound].push(groupOwner);
        }
        _groupIdsByVerifier[extension][currentRound][groupOwner].push(groupId);

        _totalScoreByGroupId[extension][currentRound][groupId] = totalScore;

        // Calculate group score (with distrust and capacity reduction)
        uint256 groupScore = _calculateGroupScore(
            extension,
            tokenAddress,
            actionId,
            currentRound,
            groupId
        );
        _scoreByGroupId[extension][currentRound][groupId] = groupScore;
        _score[extension][currentRound] += groupScore;

        _isVerified[extension][currentRound][groupId] = true;
        _verifiedGroupIds[extension][currentRound].push(groupId);
    }

    function _calculateScoreByAccount(
        address extension,
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        address account
    ) internal view returns (uint256) {
        uint256 originScoreVal = _originScoreByAccount[extension][round][
            account
        ];
        if (originScoreVal == 0) return 0;

        uint256 amount = _groupJoin.amountByAccountByRound(
            tokenAddress,
            actionId,
            account,
            round
        );
        return originScoreVal * amount;
    }

    function _calculateCapacityReduction(
        address extension,
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        address groupOwner,
        uint256 currentGroupId
    ) internal view returns (uint256) {
        // Sum capacity from already verified groups by this verifier
        uint256 verifiedCapacity = 0;
        uint256[] storage verifierGroupIds = _groupIdsByVerifier[extension][
            round
        ][groupOwner];
        for (uint256 i = 0; i < verifierGroupIds.length; i++) {
            verifiedCapacity += _groupJoin.totalJoinedAmountByGroupIdByRound(
                tokenAddress,
                actionId,
                verifierGroupIds[i],
                round
            );
        }

        uint256 maxVerifyCapacity = _groupManager.maxVerifyCapacityByOwner(
            tokenAddress,
            actionId,
            groupOwner
        );

        // Calculate remaining capacity
        uint256 remainingCapacity = maxVerifyCapacity > verifiedCapacity
            ? maxVerifyCapacity - verifiedCapacity
            : 0;

        // No remaining capacity - verification fails
        if (remainingCapacity == 0) {
            revert NoRemainingVerifyCapacity();
        }

        uint256 currentGroupCapacity = _groupJoin
            .totalJoinedAmountByGroupIdByRound(
                tokenAddress,
                actionId,
                currentGroupId,
                round
            );

        // Within capacity - no reduction (factor = 1e18)
        if (remainingCapacity >= currentGroupCapacity) {
            return 1e18;
        }

        // Exceeds capacity - apply reduction
        return (remainingCapacity * 1e18) / currentGroupCapacity;
    }

    function _calculateGroupScore(
        address extension,
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        uint256 groupId
    ) internal view returns (uint256) {
        address groupOwner = _group.ownerOf(groupId);
        uint256 groupAmount = _groupJoin.totalJoinedAmountByGroupIdByRound(
            tokenAddress,
            actionId,
            groupId,
            round
        );
        uint256 distrustVotes = _distrustVotesByGroupOwner[extension][round][
            groupOwner
        ];
        uint256 total = _verify.scoreByActionIdByAccount(
            tokenAddress,
            round,
            actionId,
            extension
        );
        uint256 capacityReduction = _capacityReductionByGroupId[extension][
            round
        ][groupId];

        // Apply both distrust ratio and capacity reduction
        if (total == 0) {
            return (groupAmount * capacityReduction) / 1e18;
        }
        return
            (groupAmount * (total - distrustVotes) * capacityReduction) /
            total /
            1e18;
    }

    function _updateDistrustForOwnerGroups(
        address extension,
        address tokenAddress,
        uint256 actionId,
        uint256 round,
        address groupOwner
    ) internal {
        uint256 distrustVotes = _distrustVotesByGroupOwner[extension][round][
            groupOwner
        ];
        uint256 total = _verify.scoreByActionIdByAccount(
            tokenAddress,
            round,
            actionId,
            extension
        );

        uint256[] storage groupIds = _groupIdsByVerifier[extension][round][
            groupOwner
        ];
        mapping(uint256 => uint256) storage scoreMap = _scoreByGroupId[
            extension
        ][round];
        mapping(uint256 => uint256)
            storage capacityReductionMap = _capacityReductionByGroupId[
                extension
            ][round];
        uint256 totalScore = _score[extension][round];

        for (uint256 i = 0; i < groupIds.length; i++) {
            uint256 groupId = groupIds[i];
            totalScore = _updateGroupScore(
                scoreMap,
                capacityReductionMap,
                tokenAddress,
                actionId,
                groupId,
                round,
                total,
                distrustVotes,
                totalScore
            );
        }

        _score[extension][round] = totalScore;
    }

    function _updateGroupScore(
        mapping(uint256 => uint256) storage scoreMap,
        mapping(uint256 => uint256) storage capacityReductionMap,
        address tokenAddress,
        uint256 actionId,
        uint256 groupId,
        uint256 round,
        uint256 total,
        uint256 distrustVotes,
        uint256 totalScore
    ) internal returns (uint256) {
        uint256 oldScore = scoreMap[groupId];
        uint256 groupAmount = _groupJoin.totalJoinedAmountByGroupIdByRound(
            tokenAddress,
            actionId,
            groupId,
            round
        );
        uint256 capacityReduction = capacityReductionMap[groupId];

        // Apply both distrust ratio and capacity reduction
        uint256 newScore;
        if (total == 0) {
            newScore = (groupAmount * capacityReduction) / 1e18;
        } else {
            newScore =
                (groupAmount * (total - distrustVotes) * capacityReduction) /
                total /
                1e18;
        }

        scoreMap[groupId] = newScore;
        return totalScore - oldScore + newScore;
    }
}
