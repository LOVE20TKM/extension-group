// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {GroupTokenJoin} from "./GroupTokenJoin.sol";
import {MAX_ORIGIN_SCORE, IGroupScore} from "../interface/base/IGroupScore.sol";
import {ILOVE20Group} from "@group/interfaces/ILOVE20Group.sol";
import {ILOVE20GroupManager} from "../interface/ILOVE20GroupManager.sol";

/// @title GroupTokenJoinManualScore
/// @notice Handles manual verification scoring logic for token-join groups
abstract contract GroupTokenJoinManualScore is GroupTokenJoin, IGroupScore {
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

    /// @dev round => groupId => whether verification is complete
    mapping(uint256 => mapping(uint256 => bool)) internal _isVerified;

    /// @dev round => list of verified group ids
    mapping(uint256 => uint256[]) internal _verifiedGroupIds;

    /// @dev round => groupId => verifier address (recorded at verification time)
    mapping(uint256 => mapping(uint256 => address)) internal _verifierByGroupId;

    /// @dev round => verifier => list of verified group ids
    mapping(uint256 => mapping(address => uint256[]))
        internal _groupIdsByVerifier;

    /// @dev round => list of verifiers
    mapping(uint256 => address[]) internal _verifiers;

    /// @dev round => groupId => verified account count (for batch verification)
    mapping(uint256 => mapping(uint256 => uint256))
        internal _verifiedAccountCount;

    /// @dev round => groupId => accumulated total score (for batch submission)
    mapping(uint256 => mapping(uint256 => uint256)) internal _batchTotalScore;

    /// @dev round => groupId => capacity reduction factor (1e18 = 100%, no reduction)
    mapping(uint256 => mapping(uint256 => uint256))
        internal _capacityReductionByGroupId;

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
    function verifyWithOriginScores(
        uint256 groupId,
        uint256 startIndex,
        uint256[] calldata originScores
    ) external virtual {
        uint256 currentRound = _verify.currentRound();
        address groupOwner = _checkVerifierAndData(currentRound, groupId);

        // Validate start index matches verified count (sequential verification)
        if (startIndex != _verifiedAccountCount[currentRound][groupId]) {
            revert InvalidStartIndex();
        }

        // Get account count from RoundHistory
        uint256 accountCount = accountCountByGroupIdByRound(
            groupId,
            currentRound
        );
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

        _verifiedAccountCount[currentRound][groupId] += originScores.length;
        _batchTotalScore[currentRound][groupId] += batchScore;

        bool isComplete = _verifiedAccountCount[currentRound][groupId] ==
            accountCount;

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
    function capacityReductionByGroupId(
        uint256 round,
        uint256 groupId
    ) external view returns (uint256) {
        return _capacityReductionByGroupId[round][groupId];
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
    function verifiedAccountCount(
        uint256 round,
        uint256 groupId
    ) external view returns (uint256) {
        return _verifiedAccountCount[round][groupId];
    }

    /// @inheritdoc IGroupScore
    function isVerified(
        uint256 round,
        uint256 groupId
    ) external view returns (bool) {
        return _isVerified[round][groupId];
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

    /// @dev Check caller is valid verifier and has data to verify
    function _checkVerifierAndData(
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

        if (_isVerified[currentRound][groupId]) {
            revert AlreadyVerified();
        }

        // Check if group has members at this round
        if (accountCountByGroupIdByRound(groupId, currentRound) == 0) {
            revert NoDataForRound();
        }
    }

    /// @dev Process scores for given range and return total score
    function _processScores(
        uint256 currentRound,
        uint256 groupId,
        uint256 startIndex,
        uint256[] calldata originScores
    ) internal returns (uint256 totalScore) {
        for (uint256 i = 0; i < originScores.length; i++) {
            if (originScores[i] > MAX_ORIGIN_SCORE) revert ScoreExceedsMax();
            address account = accountByGroupIdAndIndexByRound(
                groupId,
                startIndex + i,
                currentRound
            );
            _originScoreByAccount[currentRound][account] = originScores[i];
            totalScore +=
                originScores[i] *
                amountByAccountByRound(account, currentRound);
        }
    }

    /// @dev Finalize verification: calculate capacity reduction, record verifier, update scores
    function _finalizeVerification(
        uint256 currentRound,
        uint256 groupId,
        address groupOwner,
        uint256 totalScore
    ) internal {
        // Calculate and store capacity reduction factor
        uint256 capacityReduction = _calculateCapacityReduction(
            currentRound,
            groupOwner,
            groupId
        );
        _capacityReductionByGroupId[currentRound][groupId] = capacityReduction;

        // Record verifier (NFT owner, not delegated verifier)
        _verifierByGroupId[currentRound][groupId] = groupOwner;

        // Add verifier to list if first verified group for this verifier
        if (_groupIdsByVerifier[currentRound][groupOwner].length == 0) {
            _verifiers[currentRound].push(groupOwner);
        }
        _groupIdsByVerifier[currentRound][groupOwner].push(groupId);

        _totalScoreByGroupId[currentRound][groupId] = totalScore;

        // Calculate group score (distrust and capacity reduction applied by subclass)
        uint256 groupScore = _calculateGroupScore(currentRound, groupId);
        _scoreByGroupId[currentRound][groupId] = groupScore;
        _score[currentRound] += groupScore;

        _isVerified[currentRound][groupId] = true;
        _verifiedGroupIds[currentRound].push(groupId);
    }

    function _calculateScoreByAccount(
        uint256 round,
        address account
    ) internal view returns (uint256) {
        uint256 originScoreVal = _originScoreByAccount[round][account];
        if (originScoreVal == 0) return 0;

        uint256 amount = amountByAccountByRound(account, round);
        return originScoreVal * amount;
    }

    /// @dev Calculate capacity reduction factor (1e18 = 100%, no reduction)
    /// @return reduction factor, reverts if no remaining capacity
    function _calculateCapacityReduction(
        uint256 round,
        address groupOwner,
        uint256 currentGroupId
    ) internal view returns (uint256) {
        // Sum capacity from already verified groups by this verifier
        uint256 verifiedCapacity = 0;
        uint256[] storage verifiedGroupIds = _groupIdsByVerifier[round][
            groupOwner
        ];
        for (uint256 i = 0; i < verifiedGroupIds.length; i++) {
            verifiedCapacity += totalJoinedAmountByGroupIdByRound(
                verifiedGroupIds[i],
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

        uint256 currentGroupCapacity = totalJoinedAmountByGroupIdByRound(
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

    /// @dev Calculate group score with capacity reduction - to be overridden by distrust logic
    function _calculateGroupScore(
        uint256 round,
        uint256 groupId
    ) internal view virtual returns (uint256) {
        uint256 groupAmount = totalJoinedAmountByGroupIdByRound(groupId, round);
        uint256 capacityReduction = _capacityReductionByGroupId[round][groupId];
        return (groupAmount * capacityReduction) / 1e18;
    }
}
