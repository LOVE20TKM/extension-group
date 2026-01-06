// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    IGroupVerify,
    MAX_ORIGIN_SCORE,
    PRECISION
} from "./interface/IGroupVerify.sol";
import {IGroupJoin} from "./interface/IGroupJoin.sol";
import {
    IExtensionGroupActionFactory
} from "./interface/IExtensionGroupActionFactory.sol";
import {IExtension} from "@extension/src/interface/IExtension.sol";
import {IExtensionCenter} from "@extension/src/interface/IExtensionCenter.sol";
import {IGroupManager} from "./interface/IGroupManager.sol";
import {
    IERC721Enumerable
} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {ILOVE20Verify} from "@core/interfaces/ILOVE20Verify.sol";
import {ILOVE20Vote} from "@core/interfaces/ILOVE20Vote.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract GroupVerify is IGroupVerify, ReentrancyGuard {
    IExtensionGroupActionFactory internal _factory;
    IExtensionCenter internal _center;
    IGroupManager internal _groupManager;
    IERC721Enumerable internal _group;
    ILOVE20Verify internal _verify;
    ILOVE20Vote internal _vote;
    IGroupJoin internal _groupJoin;

    address public FACTORY_ADDRESS;
    bool internal _initialized;

    // extension => groupId => delegatedVerifier
    mapping(address => mapping(uint256 => address))
        internal _delegatedVerifierByGroupId;
    // extension => groupId => group owner at the time of delegation
    mapping(address => mapping(uint256 => address))
        internal _delegatedVerifierOwnerByGroupId;
    // extension => round => account => score deduction (0 means full score 100, >0 means deduction from 100)
    mapping(address => mapping(uint256 => mapping(address => uint256)))
        internal _originScoreDeductionByAccount;
    // extension => round => groupId => verified account count
    mapping(address => mapping(uint256 => mapping(uint256 => uint256)))
        internal _verifiedAccountCount;
    // extension => round => groupId => accumulated total score
    mapping(address => mapping(uint256 => mapping(uint256 => uint256)))
        internal _batchTotalScore;
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

    // extension => round => groupId => capacity reduction factor
    mapping(address => mapping(uint256 => mapping(uint256 => uint256)))
        internal _capacityReductionByGroupId;

    // extension => round => groupOwner => total distrust votes
    mapping(address => mapping(uint256 => mapping(address => uint256)))
        internal _distrustVotesByGroupOwner;
    // extension => round => voter => groupOwner => distrust votes
    mapping(address => mapping(uint256 => mapping(address => mapping(address => uint256))))
        internal _distrustVotesByVoterByGroupOwner;
    // extension => round => voter => groupOwner => reason
    mapping(address => mapping(uint256 => mapping(address => mapping(address => string))))
        internal _distrustReason;

    function initialize(address factory_) external {
        require(_initialized == false, "Already initialized");
        require(factory_ != address(0), "Invalid factory");

        FACTORY_ADDRESS = factory_;
        _factory = IExtensionGroupActionFactory(factory_);
        _center = IExtensionCenter(_factory.CENTER_ADDRESS());
        _groupManager = IGroupManager(_factory.GROUP_MANAGER_ADDRESS());
        _group = IERC721Enumerable(_factory.GROUP_ADDRESS());
        _verify = ILOVE20Verify(_center.verifyAddress());
        _vote = ILOVE20Vote(_center.voteAddress());
        _groupJoin = IGroupJoin(_factory.GROUP_JOIN_ADDRESS());

        _initialized = true;
    }

    modifier onlyValidExtension(address extension) {
        if (!_factory.exists(extension)) {
            revert NotRegisteredExtension();
        }
        if (!IExtension(extension).initialized()) {
            revert ExtensionNotInitialized();
        }
        _;
    }

    modifier onlyGroupOwner(address extension, uint256 groupId) {
        if (_group.ownerOf(groupId) != msg.sender)
            revert IGroupManager.OnlyGroupOwner();
        _;
    }

    function setGroupDelegatedVerifier(
        address extension,
        uint256 groupId,
        address delegatedVerifier
    ) external override onlyGroupOwner(extension, groupId) {
        address tokenAddress = IExtension(extension).TOKEN_ADDRESS();
        uint256 actionId = IExtension(extension).actionId();
        _delegatedVerifierByGroupId[extension][groupId] = delegatedVerifier;
        _delegatedVerifierOwnerByGroupId[extension][
            groupId
        ] = delegatedVerifier == address(0) ? address(0) : msg.sender;
        emit SetGroupDelegatedVerifier(
            tokenAddress,
            _verify.currentRound(),
            actionId,
            groupId,
            delegatedVerifier
        );
    }

    function verifyWithOriginScores(
        address extension,
        uint256 groupId,
        uint256 startIndex,
        uint256[] calldata originScores
    ) external override onlyValidExtension(extension) {
        address tokenAddress = IExtension(extension).TOKEN_ADDRESS();
        uint256 actionId = IExtension(extension).actionId();
        uint256 currentRound = _verify.currentRound();

        _checkVerifier(extension, groupId);
        if (_isVerified[extension][currentRound][groupId]) {
            revert AlreadyVerified();
        }

        if (
            _groupJoin.accountsByGroupIdByRoundCount(
                extension,
                groupId,
                currentRound
            ) == 0
        ) {
            revert NoDataForRound();
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

        if (startIndex != verifiedCount[groupId]) {
            revert InvalidStartIndex();
        }

        uint256 accountCount = _groupJoin.accountsByGroupIdByRoundCount(
            extension,
            groupId,
            currentRound
        );
        if (startIndex + originScores.length > accountCount) {
            revert ScoresExceedAccountCount();
        }

        uint256 batchScore = _processScores(
            extension,
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
            _finalizeVerification(
                extension,
                currentRound,
                groupId,
                finalBatchScore
            );
        }
    }

    function distrustVote(
        address extension,
        address groupOwner,
        uint256 amount,
        string calldata reason
    ) external override onlyValidExtension(extension) {
        address tokenAddress = IExtension(extension).TOKEN_ADDRESS();
        uint256 actionId = IExtension(extension).actionId();
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

        uint256 verifyVotes = _verify.scoreByVerifierByActionIdByAccount(
            tokenAddress,
            currentRound,
            voter,
            actionId,
            extension
        );
        if (verifyVotes == 0) revert NotGovernor();

        mapping(address => uint256)
            storage voterVotes = _distrustVotesByVoterByGroupOwner[extension][
                currentRound
            ][voter];
        uint256 currentVotes = voterVotes[groupOwner];
        if (currentVotes + amount > verifyVotes)
            revert DistrustVoteExceedsLimit();

        if (bytes(reason).length == 0) revert InvalidReason();

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

        _updateDistrustForOwnerGroups(
            extension,
            tokenAddress,
            actionId,
            currentRound,
            groupOwner
        );
    }

    function originScoreByAccount(
        address extension,
        uint256 round,
        address account
    ) external view override returns (uint256) {
        return _getOriginScore(extension, round, account);
    }

    function accountScore(
        address extension,
        uint256 round,
        address account
    ) external view override returns (uint256) {
        return _calculateScoreByAccount(extension, round, account);
    }

    function scoreByGroupId(
        address extension,
        uint256 round,
        uint256 groupId
    ) external view override returns (uint256) {
        return _scoreByGroupId[extension][round][groupId];
    }

    function capacityReductionByGroupId(
        address extension,
        uint256 round,
        uint256 groupId
    ) external view override returns (uint256) {
        return _capacityReductionByGroupId[extension][round][groupId];
    }

    function score(
        address extension,
        uint256 round
    ) external view override returns (uint256) {
        return _score[extension][round];
    }

    function delegatedVerifierByGroupId(
        address extension,
        uint256 groupId
    ) external view override returns (address) {
        address groupOwner = _group.ownerOf(groupId);
        if (_delegatedVerifierOwnerByGroupId[extension][groupId] != groupOwner)
            return address(0);
        return _delegatedVerifierByGroupId[extension][groupId];
    }

    function canVerify(
        address extension,
        address account,
        uint256 groupId
    ) external view override returns (bool) {
        address groupOwner = _group.ownerOf(groupId);
        bool isValidDelegatedVerifier = account ==
            _delegatedVerifierByGroupId[extension][groupId] &&
            _delegatedVerifierOwnerByGroupId[extension][groupId] == groupOwner;
        return account == groupOwner || isValidDelegatedVerifier;
    }

    function verifiedAccountCount(
        address extension,
        uint256 round,
        uint256 groupId
    ) external view override returns (uint256) {
        return _verifiedAccountCount[extension][round][groupId];
    }

    function isVerified(
        address extension,
        uint256 round,
        uint256 groupId
    ) external view override returns (bool) {
        return _isVerified[extension][round][groupId];
    }

    function verifiers(
        address extension,
        uint256 round
    ) external view override returns (address[] memory) {
        return _verifiers[extension][round];
    }

    function verifiersCount(
        address extension,
        uint256 round
    ) external view override returns (uint256) {
        return _verifiers[extension][round].length;
    }

    function verifiersAtIndex(
        address extension,
        uint256 round,
        uint256 index
    ) external view override returns (address) {
        return _verifiers[extension][round][index];
    }

    function verifierByGroupId(
        address extension,
        uint256 round,
        uint256 groupId
    ) external view override returns (address) {
        return _verifierByGroupId[extension][round][groupId];
    }

    function groupIdsByVerifier(
        address extension,
        uint256 round,
        address verifier
    ) external view override returns (uint256[] memory) {
        return _groupIdsByVerifier[extension][round][verifier];
    }

    function groupIdsByVerifierCount(
        address extension,
        uint256 round,
        address verifier
    ) external view override returns (uint256) {
        return _groupIdsByVerifier[extension][round][verifier].length;
    }

    function groupIdsByVerifierAtIndex(
        address extension,
        uint256 round,
        address verifier,
        uint256 index
    ) external view override returns (uint256) {
        return _groupIdsByVerifier[extension][round][verifier][index];
    }

    function verifiedGroupIds(
        address extension,
        uint256 round
    ) external view override returns (uint256[] memory) {
        return _verifiedGroupIds[extension][round];
    }

    function totalAccountScore(
        address extension,
        uint256 round,
        uint256 groupId
    ) external view override returns (uint256) {
        return _totalScoreByGroupId[extension][round][groupId];
    }

    function distrustVotesByGroupOwner(
        address extension,
        uint256 round,
        address groupOwner
    ) external view override returns (uint256) {
        return _distrustVotesByGroupOwner[extension][round][groupOwner];
    }

    function distrustVotesByGroupId(
        address extension,
        uint256 round,
        uint256 groupId
    ) external view override returns (uint256) {
        address groupOwner = _group.ownerOf(groupId);
        return _distrustVotesByGroupOwner[extension][round][groupOwner];
    }

    function distrustVotesByVoterByGroupOwner(
        address extension,
        uint256 round,
        address voter,
        address groupOwner
    ) external view override returns (uint256) {
        return
            _distrustVotesByVoterByGroupOwner[extension][round][voter][
                groupOwner
            ];
    }

    function distrustReason(
        address extension,
        uint256 round,
        address voter,
        address groupOwner
    ) external view override returns (string memory) {
        return _distrustReason[extension][round][voter][groupOwner];
    }

    function _processScores(
        address extension,
        uint256 currentRound,
        uint256 groupId,
        uint256 startIndex,
        uint256[] calldata originScores
    ) internal returns (uint256 totalScore) {
        for (uint256 i = 0; i < originScores.length; i++) {
            if (originScores[i] > MAX_ORIGIN_SCORE) revert ScoreExceedsMax();
            address account = _groupJoin.accountsByGroupIdByRoundAtIndex(
                extension,
                groupId,
                currentRound,
                startIndex + i
            );

            // Store deduction instead of original score to save gas
            // If score is 100, don't store (remains 0)
            // If score < 100, store MAX_ORIGIN_SCORE - originScore
            if (originScores[i] < MAX_ORIGIN_SCORE) {
                _originScoreDeductionByAccount[extension][currentRound][
                    account
                ] = MAX_ORIGIN_SCORE - originScores[i];
            }

            totalScore +=
                originScores[i] *
                _groupJoin.amountByAccountByRound(
                    extension,
                    account,
                    currentRound
                );
        }
    }

    function _finalizeVerification(
        address extension,
        uint256 currentRound,
        uint256 groupId,
        uint256 totalScore
    ) internal {
        address groupOwner = _group.ownerOf(groupId);
        uint256 capacityReduction = _calculateCapacityReduction(
            extension,
            currentRound,
            groupOwner,
            groupId
        );
        _capacityReductionByGroupId[extension][currentRound][
            groupId
        ] = capacityReduction;

        // Record verifier (NFT owner, not delegated verifier)
        _verifierByGroupId[extension][currentRound][groupId] = groupOwner;

        if (
            _groupIdsByVerifier[extension][currentRound][groupOwner].length == 0
        ) {
            _verifiers[extension][currentRound].push(groupOwner);
        }
        _groupIdsByVerifier[extension][currentRound][groupOwner].push(groupId);

        _totalScoreByGroupId[extension][currentRound][groupId] = totalScore;

        uint256 groupScore = _calculateGroupScore(
            extension,
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
        uint256 round,
        address account
    ) internal view returns (uint256) {
        uint256 originScoreVal = _getOriginScore(extension, round, account);
        if (originScoreVal == 0) return 0;

        uint256 amount = _groupJoin.amountByAccountByRound(
            extension,
            account,
            round
        );
        return originScoreVal * amount;
    }

    function _getOriginScore(
        address extension,
        uint256 round,
        address account
    ) internal view returns (uint256) {
        uint256 groupId = _groupJoin.groupIdByAccountByRound(
            extension,
            account,
            round
        );

        // If account is not in any group, return 0
        if (groupId == 0) {
            return 0;
        }

        // if group is verified, return the deduction value
        if (_isVerified[extension][round][groupId]) {
            return
                MAX_ORIGIN_SCORE -
                _originScoreDeductionByAccount[extension][round][account];
        }

        uint256 verifiedCount = _verifiedAccountCount[extension][round][
            groupId
        ];

        // If group is not verified, return 0
        if (verifiedCount == 0) {
            return 0;
        }

        // Check if account is in the verified range
        // Accounts are verified in order from index 0 to verifiedCount - 1
        for (uint256 i = 0; i < verifiedCount; i++) {
            address verifiedAccount = _groupJoin
                .accountsByGroupIdByRoundAtIndex(extension, groupId, round, i);
            if (verifiedAccount == account) {
                // Account is verified, get deduction value
                uint256 deduction = _originScoreDeductionByAccount[extension][
                    round
                ][account];
                // If deduction is 0, score is 100 (full score)
                // Otherwise, score is MAX_ORIGIN_SCORE - deduction
                return
                    deduction == 0
                        ? MAX_ORIGIN_SCORE
                        : MAX_ORIGIN_SCORE - deduction;
            }
        }

        // Account is not in verified range, return 0
        return 0;
    }

    function _calculateCapacityReduction(
        address extension,
        uint256 round,
        address groupOwner,
        uint256 currentGroupId
    ) internal view returns (uint256) {
        uint256 verifiedCapacity = 0;
        uint256[] storage verifierGroupIds = _groupIdsByVerifier[extension][
            round
        ][groupOwner];
        for (uint256 i = 0; i < verifierGroupIds.length; i++) {
            verifiedCapacity += _groupJoin.totalJoinedAmountByGroupIdByRound(
                extension,
                verifierGroupIds[i],
                round
            );
        }

        uint256 maxVerifyCapacity = _groupManager.maxVerifyCapacityByOwner(
            extension,
            groupOwner
        );

        uint256 remainingCapacity = maxVerifyCapacity > verifiedCapacity
            ? maxVerifyCapacity - verifiedCapacity
            : 0;

        if (remainingCapacity == 0) {
            revert NoRemainingVerifyCapacity();
        }

        uint256 currentGroupCapacity = _groupJoin
            .totalJoinedAmountByGroupIdByRound(
                extension,
                currentGroupId,
                round
            );

        if (remainingCapacity >= currentGroupCapacity) {
            return PRECISION;
        }

        return (remainingCapacity * PRECISION) / currentGroupCapacity;
    }

    function _calculateGroupScore(
        address extension,
        uint256 round,
        uint256 groupId
    ) internal view returns (uint256) {
        address groupOwner = _group.ownerOf(groupId);
        uint256 groupAmount = _groupJoin.totalJoinedAmountByGroupIdByRound(
            extension,
            groupId,
            round
        );
        uint256 distrustVotes = _distrustVotesByGroupOwner[extension][round][
            groupOwner
        ];
        address tokenAddress = IExtension(extension).TOKEN_ADDRESS();
        uint256 actionId = IExtension(extension).actionId();
        uint256 total = _vote.votesNumByActionId(tokenAddress, round, actionId);
        uint256 capacityReduction = _capacityReductionByGroupId[extension][
            round
        ][groupId];

        if (total == 0) {
            return (groupAmount * capacityReduction) / PRECISION;
        }
        return
            (((groupAmount * (total - distrustVotes)) / total) *
                capacityReduction) / PRECISION;
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
        uint256 total = _vote.votesNumByActionId(tokenAddress, round, actionId);

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
                extension,
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
        address extension,
        uint256 groupId,
        uint256 round,
        uint256 total,
        uint256 distrustVotes,
        uint256 totalScore
    ) internal returns (uint256) {
        uint256 oldScore = scoreMap[groupId];
        uint256 groupAmount = _groupJoin.totalJoinedAmountByGroupIdByRound(
            extension,
            groupId,
            round
        );
        uint256 capacityReduction = capacityReductionMap[groupId];

        uint256 newScore;
        if (total == 0) {
            newScore = (groupAmount * capacityReduction) / PRECISION;
        } else {
            newScore =
                (((groupAmount * (total - distrustVotes)) / total) *
                    capacityReduction) /
                PRECISION;
        }

        scoreMap[groupId] = newScore;
        return totalScore - oldScore + newScore;
    }
}
