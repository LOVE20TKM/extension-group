// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";
import {ILOVE20Launch} from "@core/interfaces/ILOVE20Launch.sol";
import {
    IERC721Enumerable
} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {IGroupManager} from "./interface/IGroupManager.sol";
import {IGroupAction} from "./interface/IGroupAction.sol";
import {
    IExtensionGroupActionFactory
} from "./interface/IExtensionGroupActionFactory.sol";
import {IGroupService} from "./interface/IGroupService.sol";
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

    ILOVE20Launch internal immutable _launch;
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

        _launch = ILOVE20Launch(_center.launchAddress());

        if (groupActionTokenAddress_ != tokenAddress_) {
            if (
                !_launch.isLOVE20Token(groupActionTokenAddress_) ||
                ILOVE20Token(groupActionTokenAddress_).parentTokenAddress() !=
                tokenAddress_
            ) {
                revert InvalidGroupActionTokenAddress();
            }
        }

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
        _checkActionId(actionId_);
        if (_group.ownerOf(groupId) != msg.sender) revert NotGroupOwner();

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

    function _calculateReward(
        uint256 round,
        address account
    ) internal view override returns (uint256) {
        uint256 totalServiceReward = reward(round);
        if (totalServiceReward == 0) return 0;

        uint256 generatedByVerifier = generatedActionRewardByVerifier(
            round,
            account
        );
        if (generatedByVerifier == 0) return 0;

        uint256 generatedTotal = generatedActionReward(round);
        if (generatedTotal == 0) return 0;

        return (totalServiceReward * generatedByVerifier) / generatedTotal;
    }

    function _calculateRewardByGroupId(
        uint256 round,
        uint256 actionId_,
        uint256 groupId
    ) internal view returns (uint256) {
        uint256 totalServiceReward = reward(round);
        if (totalServiceReward == 0) return 0;

        uint256 totalActionReward = generatedActionReward(round);
        if (totalActionReward == 0) return 0;

        address extension = _checkActionId(actionId_);

        uint256 groupReward = IGroupAction(extension).generatedRewardByGroupId(
            round,
            groupId
        );
        if (groupReward == 0) return 0;

        return (totalServiceReward * groupReward) / totalActionReward;
    }

    function _claimReward(
        uint256 round
    ) internal override returns (uint256 amount) {
        bool isMinted;
        (amount, isMinted) = rewardByAccount(round, msg.sender);
        if (isMinted) revert AlreadyClaimed();

        _claimed[round][msg.sender] = true;
        _claimedReward[round][msg.sender] = amount;

        if (amount > 0) {
            uint256 remaining = amount - _distributeToRecipients(round);
            if (remaining > 0)
                IERC20(TOKEN_ADDRESS).safeTransfer(msg.sender, remaining);
        }

        emit ClaimReward(TOKEN_ADDRESS, round, actionId, msg.sender, amount);
    }

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
            }
            unchecked {
                ++i;
            }
        }
    }
}
