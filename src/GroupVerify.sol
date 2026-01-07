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

    // extension => groupId => delegate
    mapping(address => mapping(uint256 => address)) internal _delegateByGroupId;
    // extension => groupId => group owner at the time of delegation
    mapping(address => mapping(uint256 => address))
        internal _delegateSetterByGroupId;
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
        internal _totalAccountScore;
    // extension => round => groupId => group score (with distrust applied)
    mapping(address => mapping(uint256 => mapping(uint256 => uint256)))
        internal _groupScore;
    // extension => round => total score of all verified groups
    mapping(address => mapping(uint256 => uint256)) internal _totalGroupScore;
    // extension => round => groupId => whether verification is complete
    mapping(address => mapping(uint256 => mapping(uint256 => bool)))
        internal _isVerified;
    // extension => round => list of verified group ids
    mapping(address => mapping(uint256 => uint256[]))
        internal _verifiedGroupIds;
    // extension => round => groupId => verifier address
    mapping(address => mapping(uint256 => mapping(uint256 => address)))
        internal _verifierByGroupId;
    // extension => round => groupId => submitter address who submitted the original scores
    mapping(address => mapping(uint256 => mapping(uint256 => address)))
        internal _submitterByGroupId;
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

    // extension => round => groupOwner => list of voters
    mapping(address => mapping(uint256 => mapping(address => address[])))
        internal _distrustVotersByGroupOwner;
    // extension => round => list of groupOwners
    mapping(address => mapping(uint256 => address[]))
        internal _distrustGroupOwners;

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

    modifier onlyGroupOwner(uint256 groupId) {
        if (_group.ownerOf(groupId) != msg.sender) revert OnlyGroupOwner();
        _;
    }

    function setGroupDelegate(
        address extension,
        uint256 groupId,
        address delegate
    ) external override onlyGroupOwner(groupId) {
        address tokenAddress = IExtension(extension).TOKEN_ADDRESS();
        uint256 actionId = IExtension(extension).actionId();
        _delegateByGroupId[extension][groupId] = delegate;
        _delegateSetterByGroupId[extension][groupId] = delegate == address(0)
            ? address(0)
            : msg.sender;
        emit SetGroupDelegate({
            tokenAddress: tokenAddress,
            round: _verify.currentRound(),
            actionId: actionId,
            groupId: groupId,
            delegate: delegate
        });
    }

    function submitOriginScores(
        address extension,
        uint256 groupId,
        uint256 startIndex,
        uint256[] calldata originScores
    ) external override onlyValidExtension(extension) {
        uint256 currentRound = _verify.currentRound();
        if (!canVerify(extension, msg.sender, groupId)) {
            revert NotVerifier();
        }

        if (originScores.length == 0) {
            revert OriginScoresEmpty();
        }

        address tokenAddress = IExtension(extension).TOKEN_ADDRESS();
        uint256 actionId = IExtension(extension).actionId();
        _processVerificationBatch(
            extension,
            tokenAddress,
            actionId,
            currentRound,
            groupId,
            startIndex,
            originScores,
            msg.sender
        );
    }

    function _processVerificationBatch(
        address extension,
        address tokenAddress,
        uint256 actionId,
        uint256 currentRound,
        uint256 groupId,
        uint256 startIndex,
        uint256[] calldata originScores,
        address submitter
    ) internal {
        if (_isVerified[extension][currentRound][groupId]) {
            revert AlreadyVerified();
        }

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
        batchScoreMap[groupId] += batchScore;
        verifiedCount[groupId] += originScores.length;

        bool isComplete = verifiedCount[groupId] == accountCount;

        if (isComplete) {
            _finalizeVerification(
                extension,
                currentRound,
                groupId,
                batchScoreMap[groupId],
                submitter
            );
        }

        emit SubmitOriginScores({
            tokenAddress: tokenAddress,
            round: currentRound,
            actionId: actionId,
            groupId: groupId,
            startIndex: startIndex,
            count: originScores.length,
            isComplete: isComplete
        });
    }

    function distrustVote(
        address extension,
        address groupOwner,
        uint256 amount,
        string calldata reason
    ) external override onlyValidExtension(extension) {
        if (amount == 0) revert DistrustVoteZeroAmount();
        if (bytes(reason).length == 0) revert InvalidReason();

        address voter = msg.sender;
        uint256 currentRound = _verify.currentRound();

        address tokenAddress = IExtension(extension).TOKEN_ADDRESS();
        uint256 actionId = IExtension(extension).actionId();

        _distrustReason[extension][currentRound][voter][groupOwner] = reason;
        _processDistrustVote(
            extension,
            tokenAddress,
            actionId,
            currentRound,
            voter,
            groupOwner,
            amount
        );

        emit DistrustVote({
            tokenAddress: tokenAddress,
            round: currentRound,
            actionId: actionId,
            groupOwner: groupOwner,
            voter: voter,
            amount: amount,
            reason: reason
        });
    }

    function _processDistrustVote(
        address extension,
        address tokenAddress,
        uint256 actionId,
        uint256 currentRound,
        address voter,
        address groupOwner,
        uint256 amount
    ) internal {
        uint256 verifyVotes = _verify.scoreByVerifierByActionIdByAccount(
            tokenAddress,
            currentRound,
            voter,
            actionId,
            extension
        );
        if (verifyVotes == 0) revert VerifyVotesZero();

        uint256 preVotes = _distrustVotesByVoterByGroupOwner[extension][
            currentRound
        ][voter][groupOwner];
        if (preVotes + amount > verifyVotes)
            revert DistrustVoteExceedsVerifyVotes();

        if (preVotes == 0) {
            _distrustVotersByGroupOwner[extension][currentRound][groupOwner]
                .push(voter);
        }

        if (
            _distrustVotesByGroupOwner[extension][currentRound][groupOwner] == 0
        ) {
            _distrustGroupOwners[extension][currentRound].push(groupOwner);
        }

        _distrustVotesByVoterByGroupOwner[extension][currentRound][voter][
            groupOwner
        ] += amount;
        _distrustVotesByGroupOwner[extension][currentRound][
            groupOwner
        ] += amount;

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
    ) public view override returns (uint256) {
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
                return MAX_ORIGIN_SCORE - deduction;
            }
        }

        // Account is not in verified range, return 0
        return 0;
    }

    function totalAccountScore(
        address extension,
        uint256 round,
        uint256 groupId
    ) external view override returns (uint256) {
        return _totalAccountScore[extension][round][groupId];
    }
    function accountScore(
        address extension,
        uint256 round,
        address account
    ) external view override returns (uint256) {
        uint256 originScoreVal = originScoreByAccount(
            extension,
            round,
            account
        );
        if (originScoreVal == 0) return 0;

        uint256 amount = _groupJoin.joinedAmountByAccountByRound(
            extension,
            account,
            round
        );
        return originScoreVal * amount;
    }

    function groupScore(
        address extension,
        uint256 round,
        uint256 groupId
    ) external view override returns (uint256) {
        return _groupScore[extension][round][groupId];
    }

    function capacityReductionByGroupId(
        address extension,
        uint256 round,
        uint256 groupId
    ) external view override returns (uint256) {
        return _capacityReductionByGroupId[extension][round][groupId];
    }

    function totalGroupScore(
        address extension,
        uint256 round
    ) external view override returns (uint256) {
        return _totalGroupScore[extension][round];
    }

    function delegateByGroupId(
        address extension,
        uint256 groupId
    ) external view override returns (address) {
        address groupOwner = _group.ownerOf(groupId);
        if (_delegateSetterByGroupId[extension][groupId] != groupOwner)
            return address(0);
        return _delegateByGroupId[extension][groupId];
    }

    function canVerify(
        address extension,
        address account,
        uint256 groupId
    ) public view override returns (bool) {
        address groupOwner = _group.ownerOf(groupId);
        bool isValidDelegate = account ==
            _delegateByGroupId[extension][groupId] &&
            _delegateSetterByGroupId[extension][groupId] == groupOwner;
        return account == groupOwner || isValidDelegate;
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

    function submitterByGroupId(
        address extension,
        uint256 round,
        uint256 groupId
    ) external view override returns (address) {
        return _submitterByGroupId[extension][round][groupId];
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

    function verifiedGroupIdsCount(
        address extension,
        uint256 round
    ) external view override returns (uint256) {
        return _verifiedGroupIds[extension][round].length;
    }

    function verifiedGroupIdsAtIndex(
        address extension,
        uint256 round,
        uint256 index
    ) external view override returns (uint256) {
        return _verifiedGroupIds[extension][round][index];
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

    function distrustVotersByGroupOwner(
        address extension,
        uint256 round,
        address groupOwner
    ) external view returns (address[] memory) {
        return _distrustVotersByGroupOwner[extension][round][groupOwner];
    }

    function distrustVotersByGroupOwnerCount(
        address extension,
        uint256 round,
        address groupOwner
    ) external view returns (uint256) {
        return _distrustVotersByGroupOwner[extension][round][groupOwner].length;
    }

    function distrustVotersByGroupOwnerAtIndex(
        address extension,
        uint256 round,
        address groupOwner,
        uint256 index
    ) external view returns (address) {
        return _distrustVotersByGroupOwner[extension][round][groupOwner][index];
    }

    function distrustGroupOwners(
        address extension,
        uint256 round
    ) external view returns (address[] memory) {
        return _distrustGroupOwners[extension][round];
    }

    function distrustGroupOwnersCount(
        address extension,
        uint256 round
    ) external view returns (uint256) {
        return _distrustGroupOwners[extension][round].length;
    }

    function distrustGroupOwnersAtIndex(
        address extension,
        uint256 round,
        uint256 index
    ) external view returns (address) {
        return _distrustGroupOwners[extension][round][index];
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
                _groupJoin.joinedAmountByAccountByRound(
                    extension,
                    account,
                    currentRound
                );
        }
        return totalScore;
    }

    function _finalizeVerification(
        address extension,
        uint256 currentRound,
        uint256 groupId,
        uint256 totalScore,
        address submitter
    ) internal {
        address groupOwner = _group.ownerOf(groupId);
        _capacityReductionByGroupId[extension][currentRound][
            groupId
        ] = _calculateCapacityReduction(
            extension,
            currentRound,
            groupOwner,
            groupId
        );

        // Record verifier (NFT owner, not delegated verifier)
        _verifierByGroupId[extension][currentRound][groupId] = groupOwner;

        // Record submitted verifier (actual submitter, may be delegated verifier)
        _submitterByGroupId[extension][currentRound][groupId] = submitter;

        if (
            _groupIdsByVerifier[extension][currentRound][groupOwner].length == 0
        ) {
            _verifiers[extension][currentRound].push(groupOwner);
        }

        _totalAccountScore[extension][currentRound][groupId] = totalScore;

        uint256 calculatedGroupScore = _calculateGroupScore(
            extension,
            currentRound,
            groupId
        );
        _groupScore[extension][currentRound][groupId] = calculatedGroupScore;
        _totalGroupScore[extension][currentRound] += calculatedGroupScore;

        _isVerified[extension][currentRound][groupId] = true;
        _groupIdsByVerifier[extension][currentRound][groupOwner].push(groupId);
        _verifiedGroupIds[extension][currentRound].push(groupId);
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
        uint256 totalVotes = _vote.votesNumByActionId(
            tokenAddress,
            round,
            actionId
        );
        uint256 capacityReduction = _capacityReductionByGroupId[extension][
            round
        ][groupId];

        if (totalVotes == 0) {
            return 0;
        }
        return
            (((groupAmount * (totalVotes - distrustVotes)) / totalVotes) *
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
        uint256 totalVotes = _vote.votesNumByActionId(
            tokenAddress,
            round,
            actionId
        );

        uint256[] storage groupIds = _groupIdsByVerifier[extension][round][
            groupOwner
        ];
        mapping(uint256 => uint256) storage scoreMap = _groupScore[extension][
            round
        ];
        mapping(uint256 => uint256)
            storage capacityReductionMap = _capacityReductionByGroupId[
                extension
            ][round];
        uint256 totalGroupScore_ = _totalGroupScore[extension][round];

        for (uint256 i = 0; i < groupIds.length; i++) {
            uint256 groupId = groupIds[i];
            totalGroupScore_ = _updateGroupScore(
                scoreMap,
                capacityReductionMap,
                extension,
                groupId,
                round,
                totalVotes,
                distrustVotes,
                totalGroupScore_
            );
        }

        _totalGroupScore[extension][round] = totalGroupScore_;
    }

    function _updateGroupScore(
        mapping(uint256 => uint256) storage scoreMap,
        mapping(uint256 => uint256) storage capacityReductionMap,
        address extension,
        uint256 groupId,
        uint256 round,
        uint256 totalVotes,
        uint256 distrustVotes,
        uint256 totalGroupScore_
    ) internal returns (uint256 newTotalGroupScore) {
        uint256 oldScore = scoreMap[groupId];
        uint256 groupAmount = _groupJoin.totalJoinedAmountByGroupIdByRound(
            extension,
            groupId,
            round
        );
        uint256 capacityReduction = capacityReductionMap[groupId];

        uint256 newScore = (((groupAmount * (totalVotes - distrustVotes)) /
            totalVotes) * capacityReduction) / PRECISION;

        scoreMap[groupId] = newScore;
        return totalGroupScore_ - oldScore + newScore;
    }
}
