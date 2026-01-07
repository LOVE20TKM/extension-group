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
import {IExtension} from "@extension/src/interface/IExtension.sol";
import {IJoin} from "@extension/src/interface/IJoin.sol";
import {IReward} from "@extension/src/interface/IReward.sol";
import {
    IExtensionFactory
} from "@extension/src/interface/IExtensionFactory.sol";
import {IExtensionCenter} from "@extension/src/interface/IExtensionCenter.sol";
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

contract ExtensionGroupService is ExtensionBaseRewardJoin, IGroupService {
    using RoundHistoryAddressArray for RoundHistoryAddressArray.History;
    using RoundHistoryUint256Array for RoundHistoryUint256Array.History;
    using SafeERC20 for IERC20;

    uint256 public constant BASIS_POINTS_BASE = 1e18;
    uint256 public constant DEFAULT_MAX_RECIPIENTS = 100;

    address public immutable GROUP_ACTION_TOKEN_ADDRESS;
    address public immutable GROUP_ACTION_FACTORY_ADDRESS;

    ILOVE20Launch internal immutable _launch;
    IGroupManager internal immutable _groupManager;
    IERC721Enumerable internal immutable _group;
    IExtensionGroupActionFactory internal immutable _actionFactory;

    // account => actionId => groupId => recipients
    mapping(address => mapping(uint256 => mapping(uint256 => RoundHistoryAddressArray.History)))
        internal _recipientsHistory;
    // account => actionId => groupId => basisPoints
    mapping(address => mapping(uint256 => mapping(uint256 => RoundHistoryUint256Array.History)))
        internal _basisPointsHistory;
    // account => actionIds
    mapping(address => RoundHistoryUint256Array.History)
        internal _actionIdsWithRecipients;
    // account => actionId => groupIds
    mapping(address => mapping(uint256 => RoundHistoryUint256Array.History))
        internal _groupIdsWithRecipients;

    constructor(
        address factory_,
        address tokenAddress_,
        address groupActionTokenAddress_,
        address groupActionFactoryAddress_
    ) ExtensionBaseRewardJoin(factory_, tokenAddress_) {
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

    function setRecipients(
        uint256 actionId_,
        uint256 groupId,
        address[] calldata addrs,
        uint256[] calldata basisPoints
    ) external {
        if (!_center.isAccountJoined(TOKEN_ADDRESS, actionId, msg.sender))
            revert NotJoined();

        address ext = _center.extension(GROUP_ACTION_TOKEN_ADDRESS, actionId_);
        if (!_actionFactory.exists(ext)) revert InvalidExtension();
        if (_group.ownerOf(groupId) != msg.sender) revert NotGroupOwner();

        _setRecipients(msg.sender, actionId_, groupId, addrs, basisPoints);
    }

    function recipients(
        address groupOwner,
        uint256 actionId_,
        uint256 groupId,
        uint256 round
    )
        external
        view
        returns (address[] memory addrs, uint256[] memory basisPoints)
    {
        addrs = _recipientsHistory[groupOwner][actionId_][groupId].values(
            round
        );
        basisPoints = _basisPointsHistory[groupOwner][actionId_][groupId]
            .values(round);
    }

    function recipientsLatest(
        address groupOwner,
        uint256 actionId_,
        uint256 groupId
    )
        external
        view
        returns (address[] memory addrs, uint256[] memory basisPoints)
    {
        addrs = _recipientsHistory[groupOwner][actionId_][groupId]
            .latestValues();
        basisPoints = _basisPointsHistory[groupOwner][actionId_][groupId]
            .latestValues();
    }

    function actionIdsWithRecipients(
        address account,
        uint256 round
    ) external view returns (uint256[] memory) {
        return _actionIdsWithRecipients[account].values(round);
    }

    function groupIdsWithRecipients(
        address account,
        uint256 actionId_,
        uint256 round
    ) external view returns (uint256[] memory) {
        return _groupIdsWithRecipients[account][actionId_].values(round);
    }

    function rewardByRecipient(
        uint256 round,
        address groupOwner,
        uint256 actionId_,
        uint256 groupId,
        address recipient
    ) external view returns (uint256) {
        uint256 groupReward = _calculateGroupServiceReward(
            round,
            groupOwner,
            actionId_,
            groupId
        );
        if (groupReward == 0) return 0;

        address[] memory addrs = _recipientsHistory[groupOwner][actionId_][
            groupId
        ].values(round);
        uint256[] memory bps = _basisPointsHistory[groupOwner][actionId_][
            groupId
        ].values(round);

        if (recipient == groupOwner) {
            (, uint256 distributed) = _calculateRecipientAmounts(
                groupReward,
                addrs,
                bps
            );
            return groupReward - distributed;
        }

        for (uint256 i; i < addrs.length; ) {
            if (addrs[i] == recipient) {
                return (groupReward * bps[i]) / BASIS_POINTS_BASE;
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
            uint256[] memory basisPoints,
            uint256[] memory amounts,
            uint256 ownerAmount
        )
    {
        GroupDistribution memory dist = _buildGroupDistribution(
            round,
            groupOwner,
            actionId_,
            groupId
        );
        return (
            dist.recipients,
            dist.basisPoints,
            dist.amounts,
            dist.ownerAmount
        );
    }

    function rewardDistributionAll(
        uint256 round,
        address groupOwner
    ) external view returns (GroupDistribution[] memory distributions) {
        uint256[] memory aids = _actionIdsWithRecipients[groupOwner].values(
            round
        );

        uint256 total;
        for (uint256 i; i < aids.length; ) {
            total += _groupIdsWithRecipients[groupOwner][aids[i]]
                .values(round)
                .length;
            unchecked {
                ++i;
            }
        }

        distributions = new GroupDistribution[](total);
        uint256 idx;
        for (uint256 i; i < aids.length; ) {
            uint256[] memory gids = _groupIdsWithRecipients[groupOwner][aids[i]]
                .values(round);
            for (uint256 j; j < gids.length; ) {
                distributions[idx++] = _buildGroupDistribution(
                    round,
                    groupOwner,
                    aids[i],
                    gids[j]
                );
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
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

    function joinedAmountTokenAddress()
        external
        view
        override(ExtensionBase)
        returns (address)
    {
        return GROUP_ACTION_TOKEN_ADDRESS;
    }

    function hasActiveGroups(address account) public view returns (bool) {
        return
            _groupManager.hasActiveGroups(GROUP_ACTION_TOKEN_ADDRESS, account);
    }

    function generatedRewardByVerifier(
        uint256 round,
        address verifier
    ) public view returns (uint256 accountReward, uint256 totalReward) {
        (, address[] memory exts) = _actionFactory.votedGroupActions(
            GROUP_ACTION_TOKEN_ADDRESS,
            round
        );
        for (uint256 i; i < exts.length; ) {
            IGroupAction ga = IGroupAction(exts[i]);
            accountReward += ga.generatedRewardByVerifier(round, verifier);
            totalReward += IReward(address(ga)).reward(round);
            unchecked {
                ++i;
            }
        }
    }

    function _setRecipients(
        address account,
        uint256 actionId_,
        uint256 groupId,
        address[] memory addrs,
        uint256[] memory basisPoints
    ) internal {
        uint256 len = addrs.length;
        if (len != basisPoints.length) revert ArrayLengthMismatch();
        if (len > DEFAULT_MAX_RECIPIENTS) revert TooManyRecipients();

        uint256 totalBps;
        for (uint256 i; i < len; ) {
            if (addrs[i] == address(0)) revert ZeroAddress();
            if (addrs[i] == account) revert RecipientCannotBeSelf();
            if (basisPoints[i] == 0) revert ZeroBasisPoints();
            totalBps += basisPoints[i];
            unchecked {
                ++i;
            }
        }
        if (totalBps > BASIS_POINTS_BASE) revert InvalidBasisPoints();
        _checkNoDuplicates(addrs);

        uint256 round = _verify.currentRound();
        _recipientsHistory[account][actionId_][groupId].record(round, addrs);
        _basisPointsHistory[account][actionId_][groupId].record(
            round,
            basisPoints
        );

        if (len > 0) {
            _actionIdsWithRecipients[account].add(round, actionId_);
            _groupIdsWithRecipients[account][actionId_].add(round, groupId);
        } else if (
            _groupIdsWithRecipients[account][actionId_].remove(round, groupId)
        ) {
            if (
                _groupIdsWithRecipients[account][actionId_]
                    .values(round)
                    .length == 0
            ) {
                _actionIdsWithRecipients[account].remove(round, actionId_);
            }
        }

        emit RecipientsUpdate(
            TOKEN_ADDRESS,
            round,
            actionId_,
            groupId,
            account,
            addrs,
            basisPoints
        );
    }

    function _checkNoDuplicates(address[] memory addrs) internal pure {
        uint256 len = addrs.length;
        if (len <= 1) return;
        for (uint256 i = 1; i < len; ) {
            address addr = addrs[i];
            for (uint256 j; j < i; ) {
                if (addrs[j] == addr) revert DuplicateAddress();
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    function _buildGroupDistribution(
        uint256 round,
        address groupOwner,
        uint256 actionId_,
        uint256 groupId
    ) internal view returns (GroupDistribution memory) {
        uint256 groupReward = _calculateGroupServiceReward(
            round,
            groupOwner,
            actionId_,
            groupId
        );
        address[] memory addrs = _recipientsHistory[groupOwner][actionId_][
            groupId
        ].values(round);
        uint256[] memory bps = _basisPointsHistory[groupOwner][actionId_][
            groupId
        ].values(round);

        (
            uint256[] memory amounts,
            uint256 distributed
        ) = _calculateRecipientAmounts(groupReward, addrs, bps);

        return
            GroupDistribution(
                actionId_,
                groupId,
                groupReward,
                addrs,
                bps,
                amounts,
                groupReward - distributed
            );
    }

    function _calculateRecipientAmounts(
        uint256 groupReward,
        address[] memory addrs,
        uint256[] memory bps
    ) internal pure returns (uint256[] memory amounts, uint256 distributed) {
        amounts = new uint256[](addrs.length);
        for (uint256 i; i < addrs.length; ) {
            amounts[i] = (groupReward * bps[i]) / BASIS_POINTS_BASE;
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
        if (!_center.isAccountJoined(TOKEN_ADDRESS, actionId, account))
            return 0;

        uint256 total = reward(round);
        if (total == 0) return 0;

        (uint256 accountR, uint256 allR) = generatedRewardByVerifier(
            round,
            account
        );
        if (accountR == 0 || allR == 0) return 0;

        return (total * accountR) / allR;
    }

    function _calculateGroupServiceReward(
        uint256 round,
        address groupOwner,
        uint256 actionId_,
        uint256 groupId
    ) internal view returns (uint256) {
        (uint256 ownerReward, ) = rewardByAccount(round, groupOwner);
        if (ownerReward == 0) return 0;

        (uint256 totalReward, ) = generatedRewardByVerifier(round, groupOwner);
        if (totalReward == 0) return 0;

        address ext = _center.extension(GROUP_ACTION_TOKEN_ADDRESS, actionId_);
        if (ext == address(0)) return 0;

        uint256 groupReward = IGroupAction(ext).generatedRewardByGroupId(
            round,
            groupId
        );
        if (groupReward == 0) return 0;

        return (ownerReward * groupReward) / totalReward;
    }

    function _claimReward(
        uint256 round
    ) internal override returns (uint256 amount) {
        bool isMinted;
        (amount, isMinted) = rewardByAccount(round, msg.sender);
        if (isMinted) revert AlreadyClaimed();

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
            uint256[] memory gids = _groupIdsWithRecipients[msg.sender][aids[i]]
                .values(round);
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
        uint256 groupReward = _calculateGroupServiceReward(
            round,
            msg.sender,
            actionId_,
            groupId
        );
        if (groupReward == 0) return 0;

        address[] memory addrs = _recipientsHistory[msg.sender][actionId_][
            groupId
        ].values(round);
        uint256[] memory bps = _basisPointsHistory[msg.sender][actionId_][
            groupId
        ].values(round);

        (uint256[] memory amounts, ) = _calculateRecipientAmounts(
            groupReward,
            addrs,
            bps
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
