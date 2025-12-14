// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {GroupTokenJoinSnapshot} from "./GroupTokenJoinSnapshot.sol";
import {MAX_ORIGIN_SCORE, IGroupScore} from "../interface/base/IGroupScore.sol";
import {ILOVE20Group} from "@group/interfaces/ILOVE20Group.sol";
import {ILOVE20GroupManager} from "../interface/ILOVE20GroupManager.sol";

/// @title GroupTokenJoinSnapshotManualScore
/// @notice Handles manual verification scoring logic for token-join groups
abstract contract GroupTokenJoinSnapshotManualScore is
    GroupTokenJoinSnapshot,
    IGroupScore
{
    // ============ Modifiers ============

    modifier onlyGroupOwner(uint256 groupId) {
        if (ILOVE20Group(GROUP_ADDRESS).ownerOf(groupId) != msg.sender)
            revert ILOVE20GroupManager.OnlyGroupOwner();
        _;
    }

    // ============ State ============

    /// @dev groupId => delegated verifier address
    mapping(uint256 => address) internal _delegatedVerifierByGroupId;

    /// @dev groupId => group owner at the time of delegation (0 if none)
    mapping(uint256 => address) internal _delegatedVerifierOwnerByGroupId;

    /// @dev round => account => origin score [0-100]
    mapping(uint256 => mapping(address => uint256))
        internal _originScoreByAccount;

    /// @dev round => groupId => total score of all accounts in group
    mapping(uint256 => mapping(uint256 => uint256))
        internal _totalScoreByGroupId;

    /// @dev round => groupId => group score (with distrust applied)
    mapping(uint256 => mapping(uint256 => uint256)) internal _scoreByGroupId;

    /// @dev round => total score of all verified groups
    mapping(uint256 => uint256) internal _score;

    /// @dev round => groupId => whether score has been submitted
    mapping(uint256 => mapping(uint256 => bool)) internal _scoreSubmitted;

    /// @dev round => list of verified group ids
    mapping(uint256 => uint256[]) internal _verifiedGroupIds;

    /// @dev round => groupId => verifier address (recorded at verification time)
    mapping(uint256 => mapping(uint256 => address)) internal _verifierByGroupId;

    /// @dev round => verifier => list of verified group ids
    mapping(uint256 => mapping(address => uint256[]))
        internal _groupIdsByVerifier;

    /// @dev round => list of verifiers
    mapping(uint256 => address[]) internal _verifiers;

    /// @dev round => groupId => submitted account count (for batch submission)
    mapping(uint256 => mapping(uint256 => uint256)) internal _submittedCount;

    /// @dev round => groupId => accumulated total score (for batch submission)
    mapping(uint256 => mapping(uint256 => uint256)) internal _batchTotalScore;

    // ============ IGroupScore Implementation ============

    /// @inheritdoc IGroupScore
    function setGroupDelegatedVerifier(
        uint256 groupId,
        address delegatedVerifier
    ) public virtual onlyGroupOwner(groupId) {
        _delegatedVerifierByGroupId[groupId] = delegatedVerifier;
        _delegatedVerifierOwnerByGroupId[groupId] = delegatedVerifier ==
            address(0)
            ? address(0)
            : msg.sender;
        emit GroupDelegatedVerifierSet(
            tokenAddress,
            _join.currentRound(),
            actionId,
            groupId,
            delegatedVerifier
        );
    }

    /// @inheritdoc IGroupScore
    function submitOriginScore(
        uint256 groupId,
        uint256 startIndex,
        uint256[] calldata originScores
    ) external virtual {
        _snapshotIfNeeded(groupId);
        uint256 currentRound = _verify.currentRound();
        address groupOwner = _checkVerifierAndSnapshot(currentRound, groupId);

        // Validate start index matches submitted count (sequential submission)
        if (startIndex != _submittedCount[currentRound][groupId]) {
            revert InvalidStartIndex();
        }

        // Validate doesn't exceed account count
        uint256 accountCount = _snapshotAccountsByGroupId[currentRound][groupId]
            .length;
        if (startIndex + originScores.length > accountCount) {
            revert ScoresExceedAccountCount();
        }

        // Process scores
        uint256 batchScore = _processScores(
            currentRound,
            groupId,
            startIndex,
            originScores
        );

        _submittedCount[currentRound][groupId] += originScores.length;
        _batchTotalScore[currentRound][groupId] += batchScore;

        bool isComplete = _submittedCount[currentRound][groupId] ==
            accountCount;

        emit ScoreSubmit(
            tokenAddress,
            currentRound,
            actionId,
            groupId,
            startIndex,
            originScores.length,
            isComplete
        );

        if (isComplete) {
            _finalizeVerification(
                currentRound,
                groupId,
                groupOwner,
                _batchTotalScore[currentRound][groupId]
            );
        }
    }

    /// @inheritdoc IGroupScore
    function originScoreByAccount(
        uint256 round,
        address account
    ) external view returns (uint256) {
        return _originScoreByAccount[round][account];
    }

    /// @inheritdoc IGroupScore
    function scoreByAccount(
        uint256 round,
        address account
    ) external view returns (uint256) {
        return _calculateScoreByAccount(round, account);
    }

    /// @inheritdoc IGroupScore
    function scoreByGroupId(
        uint256 round,
        uint256 groupId
    ) external view returns (uint256) {
        return _scoreByGroupId[round][groupId];
    }

    /// @inheritdoc IGroupScore
    function score(uint256 round) external view returns (uint256) {
        return _score[round];
    }

    /// @inheritdoc IGroupScore
    function delegatedVerifierByGroupId(
        uint256 groupId
    ) external view returns (address) {
        address groupOwner = ILOVE20Group(GROUP_ADDRESS).ownerOf(groupId);
        if (_delegatedVerifierOwnerByGroupId[groupId] != groupOwner)
            return address(0);
        return _delegatedVerifierByGroupId[groupId];
    }

    /// @inheritdoc IGroupScore
    function canVerify(
        address account,
        uint256 groupId
    ) public view returns (bool) {
        address groupOwner = ILOVE20Group(GROUP_ADDRESS).ownerOf(groupId);
        bool isValidDelegatedVerifier = account ==
            _delegatedVerifierByGroupId[groupId] &&
            _delegatedVerifierOwnerByGroupId[groupId] == groupOwner;
        return account == groupOwner || isValidDelegatedVerifier;
    }

    /// @inheritdoc IGroupScore
    function submittedCount(
        uint256 round,
        uint256 groupId
    ) external view returns (uint256) {
        return _submittedCount[round][groupId];
    }

    /// @inheritdoc IGroupScore
    function verifiers(uint256 round) external view returns (address[] memory) {
        return _verifiers[round];
    }

    /// @inheritdoc IGroupScore
    function verifiersCount(uint256 round) external view returns (uint256) {
        return _verifiers[round].length;
    }

    /// @inheritdoc IGroupScore
    function verifiersAtIndex(
        uint256 round,
        uint256 index
    ) external view returns (address) {
        return _verifiers[round][index];
    }

    /// @inheritdoc IGroupScore
    function verifierByGroupId(
        uint256 round,
        uint256 groupId
    ) external view returns (address) {
        return _verifierByGroupId[round][groupId];
    }

    /// @inheritdoc IGroupScore
    function groupIdsByVerifier(
        uint256 round,
        address verifier
    ) external view returns (uint256[] memory) {
        return _groupIdsByVerifier[round][verifier];
    }

    /// @inheritdoc IGroupScore
    function groupIdsByVerifierCount(
        uint256 round,
        address verifier
    ) external view returns (uint256) {
        return _groupIdsByVerifier[round][verifier].length;
    }

    /// @inheritdoc IGroupScore
    function groupIdsByVerifierAtIndex(
        uint256 round,
        address verifier,
        uint256 index
    ) external view returns (uint256) {
        return _groupIdsByVerifier[round][verifier][index];
    }

    // ============ Internal Functions ============

    /// @dev Check caller is valid verifier and snapshot exists
    function _checkVerifierAndSnapshot(
        uint256 currentRound,
        uint256 groupId
    ) internal view returns (address groupOwner) {
        groupOwner = ILOVE20Group(GROUP_ADDRESS).ownerOf(groupId);

        bool isValidDelegatedVerifier = msg.sender ==
            _delegatedVerifierByGroupId[groupId] &&
            _delegatedVerifierOwnerByGroupId[groupId] == groupOwner;
        if (msg.sender != groupOwner && !isValidDelegatedVerifier) {
            revert NotVerifier();
        }

        if (_scoreSubmitted[currentRound][groupId]) {
            revert VerificationAlreadySubmitted();
        }

        if (!_hasSnapshot[currentRound][groupId]) {
            revert NoSnapshotForRound();
        }
    }

    /// @dev Process scores for given range and return total score
    function _processScores(
        uint256 currentRound,
        uint256 groupId,
        uint256 startIndex,
        uint256[] calldata originScores
    ) internal returns (uint256 totalScore) {
        address[] storage accounts = _snapshotAccountsByGroupId[currentRound][
            groupId
        ];

        for (uint256 i = 0; i < originScores.length; i++) {
            if (originScores[i] > MAX_ORIGIN_SCORE) revert ScoreExceedsMax();
            address account = accounts[startIndex + i];
            _originScoreByAccount[currentRound][account] = originScores[i];
            totalScore +=
                originScores[i] *
                _snapshotAmountByAccount[currentRound][account];
        }
    }

    /// @dev Finalize verification: check capacity, record verifier, update scores
    function _finalizeVerification(
        uint256 currentRound,
        uint256 groupId,
        address groupOwner,
        uint256 totalScore
    ) internal {
        _checkVerifierCapacity(currentRound, groupOwner, groupId);

        // Record verifier (NFT owner, not delegated verifier)
        _verifierByGroupId[currentRound][groupId] = groupOwner;

        // Add verifier to list if first verified group for this verifier
        if (_groupIdsByVerifier[currentRound][groupOwner].length == 0) {
            _verifiers[currentRound].push(groupOwner);
        }
        _groupIdsByVerifier[currentRound][groupOwner].push(groupId);

        _totalScoreByGroupId[currentRound][groupId] = totalScore;

        // Calculate group score (distrust applied by subclass)
        uint256 groupScore = _calculateGroupScore(currentRound, groupId);
        _scoreByGroupId[currentRound][groupId] = groupScore;
        _score[currentRound] += groupScore;

        _scoreSubmitted[currentRound][groupId] = true;
        _verifiedGroupIds[currentRound].push(groupId);
    }

    function _calculateScoreByAccount(
        uint256 round,
        address account
    ) internal view returns (uint256) {
        uint256 originScoreVal = _originScoreByAccount[round][account];
        if (originScoreVal == 0) return 0;

        uint256 amount = _snapshotAmountByAccount[round][account];
        return originScoreVal * amount;
    }

    function _checkVerifierCapacity(
        uint256 round,
        address groupOwner,
        uint256 currentGroupId
    ) internal view {
        // Sum capacity from already verified groups by this verifier
        uint256 verifiedCapacity = 0;
        uint256[] storage verifiedGroupIds = _groupIdsByVerifier[round][
            groupOwner
        ];
        for (uint256 i = 0; i < verifiedGroupIds.length; i++) {
            verifiedCapacity += _snapshotAmountByGroupId[round][
                verifiedGroupIds[i]
            ];
        }

        // Add current group's capacity
        verifiedCapacity += _snapshotAmountByGroupId[round][currentGroupId];

        uint256 maxCapacity = _groupManager.maxCapacityByOwner(
            tokenAddress,
            actionId,
            groupOwner
        );
        if (verifiedCapacity > maxCapacity) {
            revert VerifierCapacityExceeded();
        }
    }

    /// @dev Calculate group score - to be overridden by distrust logic
    function _calculateGroupScore(
        uint256 round,
        uint256 groupId
    ) internal view virtual returns (uint256) {
        return _snapshotAmountByGroupId[round][groupId];
    }
}
