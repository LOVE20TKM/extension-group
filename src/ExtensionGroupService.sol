// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupManager} from "./interface/IGroupManager.sol";
import {IGroupAction} from "./interface/IGroupAction.sol";
import {IGroupVerify} from "./interface/IGroupVerify.sol";
import {
    IExtensionGroupActionFactory
} from "./interface/IExtensionGroupActionFactory.sol";
import {IGroupService} from "./interface/IGroupService.sol";
import {
    ExtensionBaseRewardJoin
} from "@extension/src/ExtensionBaseRewardJoin.sol";
import {ExtensionBase} from "@extension/src/ExtensionBase.sol";
import {IReward} from "@extension/src/interface/IReward.sol";
import {
    RoundHistoryAddressArray
} from "@extension/src/lib/RoundHistoryAddressArray.sol";
import {
    RoundHistoryUint256Array
} from "@extension/src/lib/RoundHistoryUint256Array.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    IERC721Enumerable
} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";
import {ILOVE20Stake} from "@core/interfaces/ILOVE20Stake.sol";

contract ExtensionGroupService is ExtensionBaseRewardJoin, IGroupService {
    using RoundHistoryAddressArray for RoundHistoryAddressArray.History;
    using RoundHistoryUint256Array for RoundHistoryUint256Array.History;
    using SafeERC20 for IERC20;

    uint256 public constant PRECISION = 1e18;
    uint256 public constant DEFAULT_MAX_RECIPIENTS = 10;

    address public immutable GROUP_ACTION_TOKEN_ADDRESS;
    address public immutable GROUP_ACTION_FACTORY_ADDRESS;
    uint256 public immutable GOV_RATIO_MULTIPLIER;

    IGroupManager internal immutable _groupManager;
    IERC721Enumerable internal immutable _group;
    IGroupVerify internal immutable _groupVerify;
    IExtensionGroupActionFactory internal immutable _actionFactory;
    ILOVE20Stake internal immutable _stake;

    // owner => actionId => groupId => recipients
    mapping(address => mapping(uint256 => mapping(uint256 => RoundHistoryAddressArray.History)))
        internal _recipientsHistory;
    // owner => actionId => groupId => ratios
    mapping(address => mapping(uint256 => mapping(uint256 => RoundHistoryUint256Array.History)))
        internal _ratiosHistory;
    // owner => actionIds
    mapping(address => RoundHistoryUint256Array.History)
        internal _actionIdsWithRecipients;
    // owner => actionId => groupIds
    mapping(address => mapping(uint256 => RoundHistoryUint256Array.History))
        internal _groupIdsByActionIdWithRecipients;

    constructor(
        address factory_,
        address tokenAddress_,
        address groupActionTokenAddress_,
        address groupActionFactoryAddress_,
        uint256 govRatioMultiplier_
    ) ExtensionBaseRewardJoin(factory_, tokenAddress_) {
        GROUP_ACTION_TOKEN_ADDRESS = groupActionTokenAddress_;
        GROUP_ACTION_FACTORY_ADDRESS = groupActionFactoryAddress_;
        GOV_RATIO_MULTIPLIER = govRatioMultiplier_;

        _actionFactory = IExtensionGroupActionFactory(
            groupActionFactoryAddress_
        );
        _groupManager = IGroupManager(_actionFactory.GROUP_MANAGER_ADDRESS());
        _group = IERC721Enumerable(_actionFactory.GROUP_ADDRESS());
        _groupVerify = IGroupVerify(_actionFactory.GROUP_VERIFY_ADDRESS());
        _stake = ILOVE20Stake(_center.stakeAddress());
    }

    function join(
        string[] memory verificationInfos
    ) public override(ExtensionBaseRewardJoin) {
        if (
            !_groupManager.hasActiveGroups(
                GROUP_ACTION_TOKEN_ADDRESS,
                msg.sender
            )
        ) revert NoActiveGroups();
        super.join(verificationInfos);
    }

    function _checkActionId(
        uint256 actionId_
    ) internal view returns (address extension) {
        extension = _center.extension(GROUP_ACTION_TOKEN_ADDRESS, actionId_);
        if (!_actionFactory.exists(extension)) revert InvalidExtension();
        return extension;
    }

    function setRecipients(
        uint256 actionId_,
        uint256 groupId,
        address[] calldata addrs,
        uint256[] calldata ratios
    ) external {
        address extension = _checkActionId(actionId_);
        if (_group.ownerOf(groupId) != msg.sender) revert NotGroupOwner();
        if (!_groupManager.isGroupActive(extension, groupId))
            revert GroupNotActive();

        _setRecipients(msg.sender, actionId_, groupId, addrs, ratios);
    }

    function recipients(
        address groupOwner,
        uint256 actionId_,
        uint256 groupId,
        uint256 round
    ) external view returns (address[] memory addrs, uint256[] memory ratios) {
        addrs = _recipientsHistory[groupOwner][actionId_][groupId].values(
            round
        );
        ratios = _ratiosHistory[groupOwner][actionId_][groupId].values(round);
    }

    function actionIdsWithRecipients(
        address account,
        uint256 round
    ) external view returns (uint256[] memory) {
        return _actionIdsWithRecipients[account].values(round);
    }

    function groupIdsByActionIdWithRecipients(
        address account,
        uint256 actionId_,
        uint256 round
    ) external view returns (uint256[] memory) {
        return
            _groupIdsByActionIdWithRecipients[account][actionId_].values(round);
    }

    function rewardByRecipient(
        uint256 round,
        address groupOwner,
        uint256 actionId_,
        uint256 groupId,
        address recipient
    ) external view returns (uint256) {
        uint256 groupReward = _calculateRewardByGroupId(
            round,
            actionId_,
            groupId
        );
        if (groupReward == 0) return 0;

        address[] memory addrs = _recipientsHistory[groupOwner][actionId_][
            groupId
        ].values(round);
        uint256[] memory ratios = _ratiosHistory[groupOwner][actionId_][groupId]
            .values(round);

        if (recipient == groupOwner) {
            (, uint256 distributed) = _calculateRecipientAmounts(
                groupReward,
                addrs,
                ratios
            );
            return groupReward - distributed;
        }

        uint256 len = addrs.length;
        for (uint256 i; i < len; ) {
            if (addrs[i] == recipient) {
                return (groupReward * ratios[i]) / PRECISION;
            }
            unchecked {
                ++i;
            }
        }
        return 0;
    }

    function rewardDistribution(
        uint256 round,
        address groupOwner,
        uint256 actionId_,
        uint256 groupId
    )
        external
        view
        returns (
            address[] memory addrs,
            uint256[] memory ratios,
            uint256[] memory amounts,
            uint256 ownerAmount
        )
    {
        uint256 groupReward = _calculateRewardByGroupId(
            round,
            actionId_,
            groupId
        );
        addrs = _recipientsHistory[groupOwner][actionId_][groupId].values(
            round
        );
        ratios = _ratiosHistory[groupOwner][actionId_][groupId].values(round);

        uint256 distributed;
        (amounts, distributed) = _calculateRecipientAmounts(
            groupReward,
            addrs,
            ratios
        );
        ownerAmount = groupReward - distributed;
    }

    function joinedAmountTokenAddress()
        external
        view
        override(ExtensionBase)
        returns (address)
    {
        return GROUP_ACTION_TOKEN_ADDRESS;
    }

    function joinedAmount()
        external
        view
        override(ExtensionBase)
        returns (uint256)
    {
        return _groupManager.totalStaked(GROUP_ACTION_TOKEN_ADDRESS);
    }

    function joinedAmountByAccount(
        address account
    ) external view override(ExtensionBase) returns (uint256) {
        return
            _groupManager.totalStakedByOwner(
                GROUP_ACTION_TOKEN_ADDRESS,
                account
            );
    }

    function hasActiveGroups(address owner) public view returns (bool) {
        return _groupManager.hasActiveGroups(GROUP_ACTION_TOKEN_ADDRESS, owner);
    }

    function generatedActionRewardByVerifier(
        uint256 round,
        address verifier
    ) public view override returns (uint256 amount) {
        uint256[] memory actionIds_ = _groupVerify.actionIdsByVerifier(
            GROUP_ACTION_TOKEN_ADDRESS,
            round,
            verifier
        );
        for (uint256 i; i < actionIds_.length; ) {
            address ext = _center.extension(
                GROUP_ACTION_TOKEN_ADDRESS,
                actionIds_[i]
            );
            amount += IGroupAction(ext).generatedActionRewardByVerifier(
                round,
                verifier
            );
            unchecked {
                ++i;
            }
        }
    }

    function generatedActionReward(
        uint256 round
    ) public view returns (uint256) {
        uint256[] memory actionIds_ = _groupVerify.actionIds(
            GROUP_ACTION_TOKEN_ADDRESS,
            round
        );
        uint256 totalReward;
        for (uint256 i; i < actionIds_.length; ) {
            address ext = _center.extension(
                GROUP_ACTION_TOKEN_ADDRESS,
                actionIds_[i]
            );
            totalReward += IReward(ext).reward(round);
            unchecked {
                ++i;
            }
        }
        return totalReward;
    }

    function _setRecipients(
        address account,
        uint256 actionId_,
        uint256 groupId,
        address[] memory addrs,
        uint256[] memory ratios
    ) internal {
        _validateRecipients(account, addrs, ratios);

        uint256 round = _verify.currentRound();
        _recipientsHistory[account][actionId_][groupId].record(round, addrs);
        _ratiosHistory[account][actionId_][groupId].record(round, ratios);

        if (addrs.length > 0) {
            _actionIdsWithRecipients[account].add(round, actionId_);
            _groupIdsByActionIdWithRecipients[account][actionId_].add(
                round,
                groupId
            );
        } else if (
            _groupIdsByActionIdWithRecipients[account][actionId_].remove(
                round,
                groupId
            )
        ) {
            if (
                _groupIdsByActionIdWithRecipients[account][actionId_]
                    .values(round)
                    .length == 0
            ) {
                _actionIdsWithRecipients[account].remove(round, actionId_);
            }
        }

        emit UpdateRecipients({
            tokenAddress: TOKEN_ADDRESS,
            round: round,
            actionId: actionId_,
            groupId: groupId,
            account: account,
            recipients: addrs,
            ratios: ratios
        });
    }

    function _validateRecipients(
        address account,
        address[] memory addrs,
        uint256[] memory ratios
    ) internal pure {
        uint256 len = addrs.length;
        if (len != ratios.length) revert ArrayLengthMismatch();
        if (len > DEFAULT_MAX_RECIPIENTS) revert TooManyRecipients();

        uint256 totalRatios;
        for (uint256 i; i < len; ) {
            if (addrs[i] == address(0)) revert ZeroAddress();
            if (addrs[i] == account) revert RecipientCannotBeSelf();
            if (ratios[i] == 0) revert ZeroRatio();
            totalRatios += ratios[i];

            if (i > 0) {
                address addr = addrs[i];
                for (uint256 j; j < i; ) {
                    if (addrs[j] == addr) revert DuplicateAddress();
                    unchecked {
                        ++j;
                    }
                }
            }

            unchecked {
                ++i;
            }
        }
        if (totalRatios > PRECISION) revert InvalidRatio();
    }

    function _calculateRecipientAmounts(
        uint256 groupReward,
        address[] memory addrs,
        uint256[] memory ratios
    ) internal pure returns (uint256[] memory amounts, uint256 distributed) {
        uint256 len = addrs.length;
        amounts = new uint256[](len);
        for (uint256 i; i < len; ) {
            amounts[i] = (groupReward * ratios[i]) / PRECISION;
            distributed += amounts[i];
            unchecked {
                ++i;
            }
        }
    }

    function _getRewardContext(
        uint256 round
    )
        internal
        view
        returns (uint256 totalServiceReward, uint256 totalActionReward)
    {
        totalServiceReward = reward(round);
        totalActionReward = generatedActionReward(round);
    }

    function _calculateReward(
        uint256 round,
        address account
    ) internal view override returns (uint256 mintReward, uint256 burnReward) {
        if (
            !_center.isAccountJoinedByRound(
                TOKEN_ADDRESS,
                actionId,
                account,
                round
            )
        ) return (0, 0);

        (
            uint256 totalServiceReward,
            uint256 totalActionReward
        ) = _getRewardContext(round);
        if (totalServiceReward == 0 || totalActionReward == 0) return (0, 0);

        uint256 generatedByVerifier = generatedActionRewardByVerifier(
            round,
            account
        );
        if (generatedByVerifier == 0) return (0, 0);

        // reward ratio = served mint / total action reward
        uint256 rewardRatio = (generatedByVerifier * PRECISION) /
            totalActionReward;
        // theory reward = total service reward × reward ratio
        uint256 theoryReward = (totalServiceReward * rewardRatio) / PRECISION;

        if (GOV_RATIO_MULTIPLIER == 0) {
            return (theoryReward, 0);
        }

        uint256 govTotal = _stake.govVotesNum(TOKEN_ADDRESS);
        if (govTotal == 0) {
            return (0, theoryReward);
        }
        uint256 govValid = _stake.validGovVotes(TOKEN_ADDRESS, account);
        // gov ratio cap = gov ratio × multiplier
        uint256 govRatioCap = (govValid * PRECISION * GOV_RATIO_MULTIPLIER) /
            govTotal;

        // effective ratio = MIN(reward ratio, gov ratio cap)
        uint256 effectiveRatio = rewardRatio < govRatioCap
            ? rewardRatio
            : govRatioCap;
        mintReward = (totalServiceReward * effectiveRatio) / PRECISION;
        burnReward = theoryReward - mintReward;

        return (mintReward, burnReward);
    }

    function _calculateRewardByGroupId(
        uint256 round,
        uint256 actionId_,
        uint256 groupId
    ) internal view returns (uint256) {
        (
            uint256 totalServiceReward,
            uint256 totalActionReward
        ) = _getRewardContext(round);
        if (totalServiceReward == 0 || totalActionReward == 0) return 0;

        address extension = _checkActionId(actionId_);

        uint256 groupReward = IGroupAction(extension)
            .generatedActionRewardByGroupId(round, groupId);
        if (groupReward == 0) return 0;

        return (totalServiceReward * groupReward) / totalActionReward;
    }

    function _claimReward(
        uint256 round
    ) internal override returns (uint256 mintReward, uint256 burnReward) {
        if (_claimedByAccount[round][msg.sender]) {
            revert AlreadyClaimed();
        }

        (mintReward, burnReward) = _calculateReward(round, msg.sender);

        _claimedByAccount[round][msg.sender] = true;
        _mintedRewardByAccount[round][msg.sender] = mintReward;
        _burnedRewardByAccount[round][msg.sender] = burnReward;

        // Burn overflow reward first
        if (burnReward > 0) {
            ILOVE20Token(TOKEN_ADDRESS).burn(burnReward);
        }

        uint256 distributed;
        uint256 remaining;
        if (mintReward > 0) {
            distributed = _distributeToRecipients(round);
            remaining = mintReward - distributed;
            if (remaining > 0)
                IERC20(TOKEN_ADDRESS).safeTransfer(msg.sender, remaining);
        }

        emit ClaimReward({
            tokenAddress: TOKEN_ADDRESS,
            round: round,
            actionId: actionId,
            account: msg.sender,
            mintAmount: mintReward,
            burnAmount: burnReward
        });
        emit ClaimRewardDistribution({
            tokenAddress: TOKEN_ADDRESS,
            round: round,
            actionId: actionId,
            account: msg.sender,
            mintAmount: mintReward,
            burnAmount: burnReward,
            distributed: distributed,
            remaining: remaining
        });
        return (mintReward, burnReward);
    }

    /// @notice Distributes rewards to all configured recipients for the caller
    /// @dev Iterates through all actionIds and groupIds where caller has set recipients,
    ///      calculates each group's reward share, and transfers to recipients based on ratios
    /// @param round The round to distribute rewards for
    /// @return distributed Total amount distributed to recipients
    function _distributeToRecipients(
        uint256 round
    ) internal returns (uint256 distributed) {
        uint256[] memory aids = _actionIdsWithRecipients[msg.sender].values(
            round
        );
        for (uint256 i; i < aids.length; ) {
            uint256[] memory gids = _groupIdsByActionIdWithRecipients[
                msg.sender
            ][aids[i]].values(round);
            for (uint256 j; j < gids.length; ) {
                distributed += _distributeForGroup(round, aids[i], gids[j]);
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    function _distributeForGroup(
        uint256 round,
        uint256 actionId_,
        uint256 groupId
    ) internal returns (uint256 distributed) {
        uint256 groupReward = _calculateRewardByGroupId(
            round,
            actionId_,
            groupId
        );
        if (groupReward == 0) return 0;

        address[] memory addrs = _recipientsHistory[msg.sender][actionId_][
            groupId
        ].values(round);
        uint256[] memory ratios = _ratiosHistory[msg.sender][actionId_][groupId]
            .values(round);

        (uint256[] memory amounts, ) = _calculateRecipientAmounts(
            groupReward,
            addrs,
            ratios
        );

        uint256 len = addrs.length;
        IERC20 token = IERC20(TOKEN_ADDRESS);
        for (uint256 i; i < len; ) {
            if (amounts[i] > 0) {
                token.safeTransfer(addrs[i], amounts[i]);
                distributed += amounts[i];
                emit DistributeRecipient({
                    tokenAddress: TOKEN_ADDRESS,
                    round: round,
                    actionId: actionId_,
                    groupId: groupId,
                    account: msg.sender,
                    recipient: addrs[i],
                    amount: amounts[i]
                });
            }
            unchecked {
                ++i;
            }
        }
    }
}
