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

    modifier groupActive(uint256 groupId) {
        if (!_groupManager.isGroupActive(tokenAddress, actionId, groupId))
            revert ILOVE20GroupManager.GroupNotActive();
        _;
    }

    // ============ State ============

    /// @dev groupId => delegated verifier address
    mapping(uint256 => address) internal _delegatedVerifierByGroupId;

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

    // ============ IGroupScore Implementation ============

    /// @inheritdoc IGroupScore
    function setGroupDelegatedVerifier(
        uint256 groupId,
        address delegatedVerifier
    ) public virtual onlyGroupOwner(groupId) groupActive(groupId) {
        _delegatedVerifierByGroupId[groupId] = delegatedVerifier;
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
        uint256[] calldata originScores
    ) external virtual {
        _snapshotIfNeeded(groupId);

        uint256 currentRound = _verify.currentRound();

        // Get current NFT owner as the verifier
        address groupOwner = ILOVE20Group(GROUP_ADDRESS).ownerOf(groupId);

        // Check caller is the group owner or delegated verifier
        if (
            msg.sender != groupOwner &&
            msg.sender != _delegatedVerifierByGroupId[groupId]
        ) {
            revert NotVerifier();
        }

        if (_scoreSubmitted[currentRound][groupId]) {
            revert VerificationAlreadySubmitted();
        }

        if (!_hasSnapshot[currentRound][groupId]) {
            revert NoSnapshotForRound();
        }

        // Validate scores array length matches snapshot
        address[] storage accounts = _snapshotAccountsByGroupId[currentRound][
            groupId
        ];
        if (originScores.length != accounts.length) {
            revert ScoresCountMismatch();
        }

        // Check verifier capacity limit (using recorded verified groups)
        _checkVerifierCapacity(currentRound, groupOwner, groupId);

        // Record verifier (NFT owner, not delegated verifier)
        _verifierByGroupId[currentRound][groupId] = groupOwner;

        // Add verifier to list if first verified group for this verifier
        if (_groupIdsByVerifier[currentRound][groupOwner].length == 0) {
            _verifiers[currentRound].push(groupOwner);
        }
        _groupIdsByVerifier[currentRound][groupOwner].push(groupId);

        // Process scores and calculate total score
        uint256 totalScore = 0;
        for (uint256 i = 0; i < originScores.length; i++) {
            if (originScores[i] > MAX_ORIGIN_SCORE) revert ScoreExceedsMax();
            address account = accounts[i];
            _originScoreByAccount[currentRound][account] = originScores[i];
            totalScore +=
                originScores[i] *
                _snapshotAmountByAccount[currentRound][account];
        }

        _totalScoreByGroupId[currentRound][groupId] = totalScore;

        // Calculate group score (distrust applied by subclass)
        uint256 groupScore = _calculateGroupScore(currentRound, groupId);
        _scoreByGroupId[currentRound][groupId] = groupScore;
        _score[currentRound] += groupScore;

        _scoreSubmitted[currentRound][groupId] = true;
        _verifiedGroupIds[currentRound].push(groupId);

        emit ScoreSubmit(tokenAddress, currentRound, actionId, groupId);
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
        return _delegatedVerifierByGroupId[groupId];
    }

    /// @inheritdoc IGroupScore
    function canVerify(
        address account,
        uint256 groupId
    ) public view returns (bool) {
        address groupOwner = ILOVE20Group(GROUP_ADDRESS).ownerOf(groupId);
        return
            account == groupOwner ||
            account == _delegatedVerifierByGroupId[groupId];
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
