// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupManager} from "./interface/IGroupManager.sol";
import {IGroupAction} from "./interface/IGroupAction.sol";
import {
    IExtensionGroupActionFactory
} from "./interface/IExtensionGroupActionFactory.sol";
import {IGroupService} from "./interface/IGroupService.sol";
import {ILOVE20Launch} from "@core/interfaces/ILOVE20Launch.sol";
import {
    ExtensionBaseRewardJoin
} from "@extension/src/ExtensionBaseRewardJoin.sol";
import {ExtensionBaseReward} from "@extension/src/ExtensionBaseReward.sol";
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
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ExtensionGroupService is ExtensionBaseRewardJoin, IGroupService {
    using RoundHistoryAddressArray for RoundHistoryAddressArray.History;
    using RoundHistoryUint256Array for RoundHistoryUint256Array.History;
    using SafeERC20 for IERC20;

    uint256 public constant PRECISION = 1e18;
    uint256 public constant DEFAULT_MAX_RECIPIENTS = 10;

    address public immutable GROUP_ACTION_TOKEN_ADDRESS;
    address public immutable GROUP_ACTION_FACTORY_ADDRESS;

    IGroupManager internal immutable _groupManager;
    IERC721Enumerable internal immutable _group;
    IExtensionGroupActionFactory internal immutable _actionFactory;

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
        address groupActionFactoryAddress_
    ) ExtensionBaseRewardJoin(factory_, tokenAddress_) {
        GROUP_ACTION_TOKEN_ADDRESS = groupActionTokenAddress_;
        GROUP_ACTION_FACTORY_ADDRESS = groupActionFactoryAddress_;

        _actionFactory = IExtensionGroupActionFactory(
            groupActionFactoryAddress_
        );
        _groupManager = IGroupManager(_actionFactory.GROUP_MANAGER_ADDRESS());
        _group = IERC721Enumerable(_actionFactory.GROUP_ADDRESS());
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

    function recipientsLatest(
        address groupOwner,
        uint256 actionId_,
        uint256 groupId
    ) external view returns (address[] memory addrs, uint256[] memory ratios) {
        addrs = _recipientsHistory[groupOwner][actionId_][groupId]
            .latestValues();
        ratios = _ratiosHistory[groupOwner][actionId_][groupId].latestValues();
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

        for (uint256 i; i < addrs.length; ) {
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
            _groupManager.totalStakedByAccount(
                GROUP_ACTION_TOKEN_ADDRESS,
                account
            );
    }

    function hasActiveGroups(address account) public view returns (bool) {
        return
            _groupManager.hasActiveGroups(GROUP_ACTION_TOKEN_ADDRESS, account);
    }

    function generatedActionRewardByVerifier(
        uint256 round,
        address verifier
    ) public view override returns (uint256 amount) {
        (, address[] memory exts) = _actionFactory.votedGroupActions(
            GROUP_ACTION_TOKEN_ADDRESS,
            round
        );
        for (uint256 i; i < exts.length; ) {
            IGroupAction ga = IGroupAction(exts[i]);
            amount += ga.generatedActionRewardByVerifier(round, verifier);
            unchecked {
                ++i;
            }
        }
    }

    function generatedActionReward(
        uint256 round
    ) public view returns (uint256) {
        (, address[] memory exts) = _actionFactory.votedGroupActions(
            GROUP_ACTION_TOKEN_ADDRESS,
            round
        );
        uint256 totalReward;
        for (uint256 i; i < exts.length; ) {
            totalReward += IReward(address(exts[i])).reward(round);
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
        amounts = new uint256[](addrs.length);
        for (uint256 i; i < addrs.length; ) {
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
    ) internal view override returns (uint256) {
        if (
            !_center.isAccountJoinedByRound(
                TOKEN_ADDRESS,
                actionId,
                account,
                round
            )
        ) return 0;

        (
            uint256 totalServiceReward,
            uint256 totalActionReward
        ) = _getRewardContext(round);
        if (totalServiceReward == 0 || totalActionReward == 0) return 0;

        uint256 generatedByVerifier = generatedActionRewardByVerifier(
            round,
            account
        );
        if (generatedByVerifier == 0) return 0;

        return (totalServiceReward * generatedByVerifier) / totalActionReward;
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
    ) internal override returns (uint256 amount) {
        bool claimed;
        (amount, claimed) = rewardByAccount(round, msg.sender);
        if (claimed) revert AlreadyClaimed();

        _claimedByAccount[round][msg.sender] = true;
        _claimedRewardByAccount[round][msg.sender] = amount;

        uint256 distributed;
        uint256 remaining;
        if (amount > 0) {
            distributed = _distributeToRecipients(round);
            remaining = amount - distributed;
            if (remaining > 0)
                IERC20(TOKEN_ADDRESS).safeTransfer(msg.sender, remaining);
        }

        emit ClaimReward({
            tokenAddress: TOKEN_ADDRESS,
            round: round,
            actionId: actionId,
            account: msg.sender,
            amount: amount
        });
        emit ClaimRewardDistribution({
            tokenAddress: TOKEN_ADDRESS,
            round: round,
            actionId: actionId,
            account: msg.sender,
            amount: amount,
            distributed: distributed,
            remaining: remaining
        });
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

        IERC20 token = IERC20(TOKEN_ADDRESS);
        for (uint256 i; i < addrs.length; ) {
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

    function _calculateBurnAmount(
        uint256 round,
        uint256 totalReward
    ) internal view override returns (uint256) {
        if (totalReward == 0) return 0;

        address[] memory accounts = _center.accountsByRound(
            TOKEN_ADDRESS,
            actionId,
            round
        );

        uint256 participatedReward;
        for (uint256 i; i < accounts.length; ) {
            (uint256 accountReward, ) = rewardByAccount(round, accounts[i]);
            participatedReward += accountReward;
            unchecked {
                ++i;
            }
        }

        return totalReward - participatedReward;
    }
}
