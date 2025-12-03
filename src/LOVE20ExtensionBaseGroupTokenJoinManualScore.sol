// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    LOVE20ExtensionBaseGroupTokenJoin
} from "./LOVE20ExtensionBaseGroupTokenJoin.sol";
import {
    MAX_ORIGIN_SCORE,
    IGroupSnapshot,
    IGroupScore,
    IGroupDistrust,
    IGroupManualScore
} from "./interface/base/IGroupManualScore.sol";
import {IGroupReward} from "./interface/base/IGroupReward.sol";
import {
    IExtensionReward
} from "@extension/src/interface/base/IExtensionReward.sol";
import {ILOVE20Group} from "@group/interfaces/ILOVE20Group.sol";
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";

/// @title LOVE20ExtensionBaseGroupTokenJoinManualScore
/// @notice Extension contract for manual scoring verification in group-based actions
/// @dev Implements snapshot, scoring, distrust voting and reward distribution
abstract contract LOVE20ExtensionBaseGroupTokenJoinManualScore is
    LOVE20ExtensionBaseGroupTokenJoin,
    IGroupManualScore,
    IGroupReward
{
    // ============ State - Snapshot ============

    /// @dev round => groupId => accounts snapshot
    mapping(uint256 => mapping(uint256 => address[]))
        internal _snapshotAccountsByGroupId;

    /// @dev round => account => amount snapshot
    mapping(uint256 => mapping(address => uint256))
        internal _snapshotAmountByAccount;

    /// @dev round => groupId => total amount snapshot
    mapping(uint256 => mapping(uint256 => uint256))
        internal _snapshotAmountByGroupId;

    /// @dev round => total amount snapshot
    mapping(uint256 => uint256) internal _snapshotAmount;

    /// @dev round => groupId => verifier address at snapshot time
    mapping(uint256 => mapping(uint256 => address))
        internal _snapshotVerifierByGroupId;

    /// @dev round => verifier => list of snapshotted group ids
    mapping(uint256 => mapping(address => uint256[]))
        internal _snapshotGroupIdsByVerifier;

    /// @dev round => groupId => whether snapshot exists
    mapping(uint256 => mapping(uint256 => bool)) internal _hasSnapshot;

    /// @dev round => list of snapshotted group ids
    mapping(uint256 => uint256[]) internal _snapshotGroupIds;

    /// @dev round => list of snapshotted verifiers
    mapping(uint256 => address[]) internal _snapshotVerifiers;

    // ============ State - Score ============

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

    // ============ State - Distrust ============

    /// @dev round => groupOwner => total distrust votes
    mapping(uint256 => mapping(address => uint256))
        internal _distrustVotesByGroupOwner;

    /// @dev round => voter => groupOwner => distrust votes for this groupOwner
    mapping(uint256 => mapping(address => mapping(address => uint256)))
        internal _distrustVotesByVoterByGroupOwner;

    /// @dev round => voter => groupOwner => reason
    mapping(uint256 => mapping(address => mapping(address => string)))
        internal _distrustReason;

    // ============ State - Reward ============

    /// @dev round => total reward for the round
    mapping(uint256 => uint256) internal _reward;

    /// @dev round => account => claimed reward
    mapping(uint256 => mapping(address => uint256)) internal _claimedReward;

    /// @dev round => burned amount
    mapping(uint256 => uint256) internal _burnedReward;

    // ============ Constructor ============

    constructor(
        address factory_,
        address tokenAddress_,
        address groupAddress_,
        address stakeTokenAddress_,
        address joinTokenAddress_,
        uint256 minGovernanceVoteRatio_,
        uint256 capacityMultiplier_,
        uint256 stakingMultiplier_,
        uint256 maxJoinAmountMultiplier_,
        uint256 minJoinAmount_
    )
        LOVE20ExtensionBaseGroupTokenJoin(
            factory_,
            tokenAddress_,
            groupAddress_,
            stakeTokenAddress_,
            joinTokenAddress_,
            minGovernanceVoteRatio_,
            capacityMultiplier_,
            stakingMultiplier_,
            maxJoinAmountMultiplier_,
            minJoinAmount_
        )
    {}

    // ============ IGroupSnapshot Implementation ============

    /// @inheritdoc IGroupSnapshot
    function snapshotIfNeeded(uint256 groupId) public {
        uint256 currentRound = _verify.currentRound();
        _snapshotIfNeeded(currentRound, groupId);
    }

    /// @inheritdoc IGroupSnapshot
    function snapshotAccountsByGroupId(
        uint256 round,
        uint256 groupId
    ) external view returns (address[] memory) {
        return _snapshotAccountsByGroupId[round][groupId];
    }

    /// @inheritdoc IGroupSnapshot
    function snapshotAccountsByGroupIdCount(
        uint256 round,
        uint256 groupId
    ) external view returns (uint256) {
        return _snapshotAccountsByGroupId[round][groupId].length;
    }

    /// @inheritdoc IGroupSnapshot
    function snapshotAccountsByGroupIdAtIndex(
        uint256 round,
        uint256 groupId,
        uint256 index
    ) external view returns (address) {
        return _snapshotAccountsByGroupId[round][groupId][index];
    }

    /// @inheritdoc IGroupSnapshot
    function snapshotAmountByAccount(
        uint256 round,
        address account
    ) external view returns (uint256) {
        return _snapshotAmountByAccount[round][account];
    }

    /// @inheritdoc IGroupSnapshot
    function snapshotAmountByGroupId(
        uint256 round,
        uint256 groupId
    ) external view returns (uint256) {
        return _snapshotAmountByGroupId[round][groupId];
    }

    /// @inheritdoc IGroupSnapshot
    function snapshotAmount(uint256 round) external view returns (uint256) {
        return _snapshotAmount[round];
    }

    function snapshotGroupIds(
        uint256 round
    ) external view returns (uint256[] memory) {
        return _snapshotGroupIds[round];
    }

    function snapshotGroupIdsCount(
        uint256 round
    ) external view returns (uint256) {
        return _snapshotGroupIds[round].length;
    }

    function snapshotGroupIdsAtIndex(
        uint256 round,
        uint256 index
    ) external view returns (uint256) {
        return _snapshotGroupIds[round][index];
    }

    /// @inheritdoc IGroupSnapshot
    function snapshotVerifiers(
        uint256 round
    ) external view returns (address[] memory) {
        return _snapshotVerifiers[round];
    }

    /// @inheritdoc IGroupSnapshot
    function snapshotVerifiersCount(
        uint256 round
    ) external view returns (uint256) {
        return _snapshotVerifiers[round].length;
    }

    /// @inheritdoc IGroupSnapshot
    function snapshotVerifiersAtIndex(
        uint256 round,
        uint256 index
    ) external view returns (address) {
        return _snapshotVerifiers[round][index];
    }

    /// @inheritdoc IGroupSnapshot
    function snapshotGroupIdsByVerifier(
        uint256 round,
        address verifier
    ) external view returns (uint256[] memory) {
        return _snapshotGroupIdsByVerifier[round][verifier];
    }

    /// @inheritdoc IGroupSnapshot
    function snapshotGroupIdsByVerifierCount(
        uint256 round,
        address verifier
    ) external view returns (uint256) {
        return _snapshotGroupIdsByVerifier[round][verifier].length;
    }

    /// @inheritdoc IGroupSnapshot
    function snapshotGroupIdsByVerifierAtIndex(
        uint256 round,
        address verifier,
        uint256 index
    ) external view returns (uint256) {
        return _snapshotGroupIdsByVerifier[round][verifier][index];
    }

    // ============ IGroupScore Implementation ============

    /// @inheritdoc IGroupScore
    function submitOriginScore(
        uint256 groupId,
        uint256[] calldata scores
    ) external {
        uint256 currentRound = _verify.currentRound();

        // Trigger snapshot first
        _snapshotIfNeeded(currentRound, groupId);

        // Check caller is the verifier at snapshot time
        address verifier = _snapshotVerifierByGroupId[currentRound][groupId];
        if (
            msg.sender != verifier &&
            msg.sender != _groupInfo[groupId].delegatedVerifier
        ) {
            revert NotVerifier();
        }

        // Check not already submitted
        if (_scoreSubmitted[currentRound][groupId]) {
            revert VerificationAlreadySubmitted();
        }

        // Check snapshot exists
        if (!_hasSnapshot[currentRound][groupId]) {
            revert NoSnapshotForRound();
        }

        // Validate scores array length matches snapshot
        address[] storage accounts = _snapshotAccountsByGroupId[currentRound][
            groupId
        ];
        if (scores.length != accounts.length) {
            revert ScoresCountMismatch();
        }

        // Check verifier capacity limit
        address groupOwner = ILOVE20Group(GROUP_ADDRESS).ownerOf(groupId);
        _checkVerifierCapacity(currentRound, groupOwner, groupId);

        // Process scores and calculate total score
        uint256 totalScore = 0;
        for (uint256 i = 0; i < scores.length; i++) {
            if (scores[i] > MAX_ORIGIN_SCORE) revert ScoreExceedsMax();
            address account = accounts[i];
            _originScoreByAccount[currentRound][account] = scores[i];
            totalScore +=
                scores[i] *
                _snapshotAmountByAccount[currentRound][account];
        }

        _totalScoreByGroupId[currentRound][groupId] = totalScore;

        // Calculate and store group score (considering existing distrust)
        uint256 groupAmount = _snapshotAmountByGroupId[currentRound][groupId];
        uint256 distrustVotes = _distrustVotesByGroupOwner[currentRound][
            groupOwner
        ];
        uint256 totalVerifyVotes = _getTotalNonAbstainVerifyVotes(currentRound);
        uint256 groupScore = totalVerifyVotes == 0
            ? groupAmount
            : (groupAmount * (totalVerifyVotes - distrustVotes)) /
                totalVerifyVotes;
        _scoreByGroupId[currentRound][groupId] = groupScore;
        _score[currentRound] += groupScore;

        _scoreSubmitted[currentRound][groupId] = true;
        _verifiedGroupIds[currentRound].push(groupId);

        emit ScoreSubmitted(currentRound, groupId);
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

    // ============ IGroupDistrust Implementation ============

    /// @inheritdoc IGroupDistrust
    function distrustVote(
        address groupOwner,
        uint256 amount,
        string calldata reason
    ) external {
        uint256 currentRound = _verify.currentRound();

        // Check caller has verified this action (is a governor who verified)
        uint256 verifyVotes = _verify.scoreByVerifierByActionId(
            tokenAddress,
            currentRound,
            msg.sender,
            actionId
        );
        if (verifyVotes == 0) revert NotGovernor();

        // Check accumulated votes for this groupOwner don't exceed verify votes
        if (
            _distrustVotesByVoterByGroupOwner[currentRound][msg.sender][
                groupOwner
            ] +
                amount >
            verifyVotes
        ) revert DistrustVoteExceedsLimit();

        // Check reason is not empty
        if (bytes(reason).length == 0) revert InvalidReason();

        // Record vote
        _distrustVotesByVoterByGroupOwner[currentRound][msg.sender][
            groupOwner
        ] += amount;
        _distrustVotesByGroupOwner[currentRound][groupOwner] += amount;
        _distrustReason[currentRound][msg.sender][groupOwner] = reason;

        // Update distrust for all active groups owned by this owner
        _updateDistrustForOwnerGroups(currentRound, groupOwner);

        emit DistrustVoted(
            currentRound,
            groupOwner,
            msg.sender,
            amount,
            reason
        );
    }

    /// @inheritdoc IGroupDistrust
    function distrustVotesByGroupOwner(
        uint256 round,
        address groupOwner
    ) external view returns (uint256) {
        return _distrustVotesByGroupOwner[round][groupOwner];
    }

    /// @inheritdoc IGroupDistrust
    function distrustVotesByGroupId(
        uint256 round,
        uint256 groupId
    ) external view returns (uint256) {
        address groupOwner = ILOVE20Group(GROUP_ADDRESS).ownerOf(groupId);
        return _distrustVotesByGroupOwner[round][groupOwner];
    }

    /// @inheritdoc IGroupDistrust
    function distrustRatioByGroupOwner(
        uint256 round,
        address groupOwner
    ) external view returns (uint256 distrustVotes, uint256 totalVerifyVotes) {
        distrustVotes = _distrustVotesByGroupOwner[round][groupOwner];
        totalVerifyVotes = _getTotalNonAbstainVerifyVotes(round);
    }

    /// @inheritdoc IGroupDistrust
    function distrustVotesByVoterByGroupOwner(
        uint256 round,
        address voter,
        address groupOwner
    ) external view returns (uint256) {
        return _distrustVotesByVoterByGroupOwner[round][voter][groupOwner];
    }

    /// @inheritdoc IGroupDistrust
    function distrustReason(
        uint256 round,
        address voter,
        address groupOwner
    ) external view returns (string memory) {
        return _distrustReason[round][voter][groupOwner];
    }

    // ============ IGroupReward Implementation ============

    /// @inheritdoc IGroupReward
    function burnUnclaimedReward(uint256 round) external {
        // Must be after verify phase
        if (round >= _verify.currentRound()) revert RoundNotFinished();

        // Check if any group verified this round
        if (_verifiedGroupIds[round].length > 0) {
            revert RoundHasVerifiedGroups();
        }

        // Prepare reward if needed
        _prepareRewardIfNeeded(round);

        uint256 rewardAmount = _reward[round];
        if (rewardAmount > 0 && _burnedReward[round] == 0) {
            _burnedReward[round] = rewardAmount;
            ILOVE20Token(tokenAddress).burn(rewardAmount);
            emit UnclaimedRewardBurned(round, rewardAmount);
        }
    }

    /// @inheritdoc IGroupReward
    function rewardByGroupId(
        uint256 round,
        uint256 groupId
    ) external view returns (uint256) {
        return _calculateRewardByGroupId(round, groupId);
    }

    /// @inheritdoc IGroupReward
    function rewardByGroupOwner(
        uint256 round,
        address groupOwner
    ) external view returns (uint256 reward) {
        uint256[] storage groupIds = _snapshotGroupIdsByVerifier[round][
            groupOwner
        ];
        for (uint256 i = 0; i < groupIds.length; i++) {
            reward += _calculateRewardByGroupId(round, groupIds[i]);
        }
    }

    // ============ IExtensionReward Implementation ============

    /// @inheritdoc IExtensionReward
    function rewardByAccount(
        uint256 round,
        address account
    ) public view returns (uint256 reward, bool isMinted) {
        uint256 claimed = _claimedReward[round][account];
        if (claimed > 0) {
            return (claimed, true);
        }
        return (_calculateRewardByAccount(round, account), false);
    }

    /// @inheritdoc IExtensionReward
    function claimReward(uint256 round) external returns (uint256 reward) {
        // Must be after verify phase
        if (round >= _verify.currentRound()) revert RoundNotFinished();

        // Prepare reward if needed
        _prepareRewardIfNeeded(round);

        // Calculate and claim
        bool isMinted;
        (reward, isMinted) = rewardByAccount(round, msg.sender);
        if (isMinted) revert AlreadyClaimed();

        _claimedReward[round][msg.sender] = reward;

        if (reward > 0) {
            ILOVE20Token(tokenAddress).transfer(msg.sender, reward);
        }

        emit ClaimReward(tokenAddress, msg.sender, actionId, round, reward);
    }

    // ============ Internal - Snapshot ============

    function _snapshotIfNeeded(uint256 round, uint256 groupId) internal {
        if (_hasSnapshot[round][groupId]) return;

        // Only create snapshot in verify phase (round > 0 and group was active)
        GroupInfo storage group = _groupInfo[groupId];
        if (!group.isActive) return;

        _hasSnapshot[round][groupId] = true;
        _snapshotGroupIds[round].push(groupId);

        // Snapshot accounts
        address[] storage currentAccounts = _accountsByGroupId[groupId];
        uint256 accountCount = currentAccounts.length;

        for (uint256 i = 0; i < accountCount; i++) {
            address account = currentAccounts[i];
            _snapshotAccountsByGroupId[round][groupId].push(account);

            uint256 amount = _joinInfo[account].amount;
            _snapshotAmountByAccount[round][account] = amount;
        }

        // Snapshot group amount
        uint256 groupAmount = group.totalJoinedAmount;
        _snapshotAmountByGroupId[round][groupId] = groupAmount;
        _snapshotAmount[round] += groupAmount;

        // Snapshot verifier and record groupId under verifier
        address owner = ILOVE20Group(GROUP_ADDRESS).ownerOf(groupId);
        _snapshotVerifierByGroupId[round][groupId] = owner;

        // Add verifier to list if first group for this verifier
        if (_snapshotGroupIdsByVerifier[round][owner].length == 0) {
            _snapshotVerifiers[round].push(owner);
        }
        _snapshotGroupIdsByVerifier[round][owner].push(groupId);

        emit SnapshotCreated(round, groupId);
    }

    // ============ Internal - Score Calculation ============

    function _calculateScoreByAccount(
        uint256 round,
        address account
    ) internal view returns (uint256) {
        uint256 originScoreVal = _originScoreByAccount[round][account];
        if (originScoreVal == 0) return 0;

        uint256 amount = _snapshotAmountByAccount[round][account];

        // score = originScore * amount
        return originScoreVal * amount;
    }

    // ============ Internal - Reward Calculation ============

    function _prepareRewardIfNeeded(uint256 round) internal {
        if (_reward[round] > 0) return;

        uint256 totalActionReward = _mint.mintActionReward(
            tokenAddress,
            round,
            actionId
        );
        _reward[round] = totalActionReward;
    }

    function _calculateRewardByGroupId(
        uint256 round,
        uint256 groupId
    ) internal view returns (uint256) {
        uint256 totalReward = _reward[round];
        if (totalReward == 0) return 0;

        uint256 totalScore = _score[round];
        if (totalScore == 0) return 0;

        uint256 groupScore = _scoreByGroupId[round][groupId];
        return (totalReward * groupScore) / totalScore;
    }

    function _calculateRewardByAccount(
        uint256 round,
        address account
    ) internal view returns (uint256) {
        uint256 accountScore = _calculateScoreByAccount(round, account);
        if (accountScore == 0) return 0;

        uint256 groupId = groupIdByAccountByRound(account, round);
        if (groupId == 0) return 0;

        // Get group reward
        uint256 groupReward = _calculateRewardByGroupId(round, groupId);
        if (groupReward == 0) return 0;

        // Use stored total score for the group
        uint256 groupTotalScore = _totalScoreByGroupId[round][groupId];
        if (groupTotalScore == 0) return 0;

        return (groupReward * accountScore) / groupTotalScore;
    }

    // ============ Internal - Distrust ============

    function _updateDistrustForOwnerGroups(
        uint256 round,
        address groupOwner
    ) internal {
        uint256 distrustVotes = _distrustVotesByGroupOwner[round][groupOwner];
        uint256 totalVerifyVotes = _getTotalNonAbstainVerifyVotes(round);

        uint256[] storage groupIds = _snapshotGroupIdsByVerifier[round][
            groupOwner
        ];
        for (uint256 i = 0; i < groupIds.length; i++) {
            uint256 groupId = groupIds[i];
            if (_scoreSubmitted[round][groupId]) {
                uint256 oldScore = _scoreByGroupId[round][groupId];
                uint256 groupAmount = _snapshotAmountByGroupId[round][groupId];

                // newScore = groupAmount * (1 - distrustRatio)
                uint256 newScore = totalVerifyVotes == 0
                    ? groupAmount
                    : (groupAmount * (totalVerifyVotes - distrustVotes)) /
                        totalVerifyVotes;

                _scoreByGroupId[round][groupId] = newScore;
                _score[round] = _score[round] - oldScore + newScore;
            }
        }
    }

    function _getTotalNonAbstainVerifyVotes(
        uint256 round
    ) internal view returns (uint256) {
        uint256 totalScore = _verify.scoreByActionId(
            tokenAddress,
            round,
            actionId
        );
        uint256 abstentionScore = _verify.scoreByActionIdByAccount(
            tokenAddress,
            round,
            actionId,
            address(0)
        );
        return totalScore - abstentionScore;
    }

    // ============ Internal - Verifier Capacity Check ============

    function _checkVerifierCapacity(
        uint256 round,
        address groupOwner,
        uint256 currentGroupId
    ) internal view {
        uint256 verifiedCapacity = 0;
        uint256 nftBalance = ILOVE20Group(GROUP_ADDRESS).balanceOf(groupOwner);

        for (uint256 i = 0; i < nftBalance; i++) {
            uint256 groupId = ILOVE20Group(GROUP_ADDRESS).tokenOfOwnerByIndex(
                groupOwner,
                i
            );
            if (groupId != currentGroupId && _scoreSubmitted[round][groupId]) {
                verifiedCapacity += _snapshotAmountByGroupId[round][groupId];
            }
        }

        // Add current group capacity
        verifiedCapacity += _snapshotAmountByGroupId[round][currentGroupId];

        // Check against max capacity
        uint256 maxCapacity = _calculateMaxCapacityForOwner(groupOwner);
        if (verifiedCapacity > maxCapacity) {
            revert VerifierCapacityExceeded();
        }
    }

    // ============ Override Hooks ============

    function _beforeJoin(
        uint256 groupId,
        address /* account */
    ) internal virtual override {
        // Trigger snapshot when joining during verify phase
        uint256 currentRound = _verify.currentRound();
        _snapshotIfNeeded(currentRound, groupId);
    }

    function _beforeExit(
        uint256 groupId,
        address /* account */
    ) internal virtual override {
        // Trigger snapshot when exiting during verify phase
        uint256 currentRound = _verify.currentRound();
        _snapshotIfNeeded(currentRound, groupId);
    }
}
