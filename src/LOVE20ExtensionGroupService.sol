// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

// OpenZeppelin
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Extension
import {
    ExtensionBaseJoin
} from "@extension/src/ExtensionBaseJoin.sol";
import {IExtensionJoin} from "@extension/src/interface/IExtensionJoin.sol";
import {
    RoundHistoryAddressArray
} from "@extension/src/lib/RoundHistoryAddressArray.sol";
import {
    RoundHistoryUint256Array
} from "@extension/src/lib/RoundHistoryUint256Array.sol";

// Core
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";
import {ILOVE20Launch} from "@core/interfaces/ILOVE20Launch.sol";

// Group
import {ILOVE20Group} from "@group/interfaces/ILOVE20Group.sol";

// Local
import {IGroupManager} from "./interface/IGroupManager.sol";
import {
    ILOVE20ExtensionGroupAction
} from "./interface/ILOVE20ExtensionGroupAction.sol";
import {
    ILOVE20ExtensionGroupActionFactory
} from "./interface/ILOVE20ExtensionGroupActionFactory.sol";
import {
    ILOVE20ExtensionGroupService
} from "./interface/ILOVE20ExtensionGroupService.sol";
import {TokenConversionLib} from "./lib/TokenConversionLib.sol";

/// @title LOVE20ExtensionGroupService
/// @notice Extension contract for rewarding group service providers
/// @dev Service reward = Total service reward × (Account's group action reward / Group action total reward)
contract LOVE20ExtensionGroupService is
    ExtensionBaseJoin,
    ILOVE20ExtensionGroupService
{
    using RoundHistoryAddressArray for RoundHistoryAddressArray.History;
    using RoundHistoryUint256Array for RoundHistoryUint256Array.History;
    using SafeERC20 for IERC20;

    // ============ Constants ============

    uint256 public constant BASIS_POINTS_BASE = 1e18;
    uint256 public constant DEFAULT_MAX_RECIPIENTS = 100;

    // ============ Immutables ============

    address public immutable GROUP_ACTION_TOKEN_ADDRESS;
    address public immutable GROUP_ACTION_FACTORY_ADDRESS;

    // ============ Cached Interfaces ============

    IGroupManager internal immutable _groupManager;
    ILOVE20Group internal immutable _group;
    ILOVE20ExtensionGroupActionFactory internal immutable _actionFactory;

    // ============ Storage ============

    /// @dev account => actionId => groupId => recipient addresses history
    mapping(address => mapping(uint256 => mapping(uint256 => RoundHistoryAddressArray.History)))
        internal _recipientsHistory;

    /// @dev account => actionId => groupId => basis points history
    mapping(address => mapping(uint256 => mapping(uint256 => RoundHistoryUint256Array.History)))
        internal _basisPointsHistory;

    /// @dev account => actionIds with recipients history
    mapping(address => RoundHistoryUint256Array.History)
        internal _actionIdsWithRecipients;

    /// @dev account => actionId => groupIds with recipients history
    mapping(address => mapping(uint256 => RoundHistoryUint256Array.History))
        internal _groupIdsWithRecipients;

    // ============ Constructor ============

    constructor(
        address factory_,
        address tokenAddress_,
        address groupActionTokenAddress_,
        address groupActionFactoryAddress_
    ) ExtensionBaseJoin(factory_, tokenAddress_) {
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

        // Cache frequently used interfaces
        _actionFactory = ILOVE20ExtensionGroupActionFactory(
            groupActionFactoryAddress_
        );
        _groupManager = IGroupManager(_actionFactory.GROUP_MANAGER_ADDRESS());
        _group = ILOVE20Group(_actionFactory.GROUP_ADDRESS());
    }

    // ============ Write Functions ============

    /// @notice Join the service reward action
    function join(
        string[] memory verificationInfos
    ) public override(IExtensionJoin, ExtensionBaseJoin) {
        if (
            !_groupManager.hasActiveGroups(
                GROUP_ACTION_FACTORY_ADDRESS,
                GROUP_ACTION_TOKEN_ADDRESS,
                msg.sender
            )
        ) revert NoActiveGroups();
        super.join(verificationInfos);
    }

    /// @notice Check if account has staked in any valid group action
    function hasActiveGroups(address account) public view returns (bool) {
        return
            _groupManager.hasActiveGroups(
                GROUP_ACTION_FACTORY_ADDRESS,
                GROUP_ACTION_TOKEN_ADDRESS,
                account
            );
    }

    function votedGroupActions(
        uint256 round
    )
        external
        view
        returns (uint256[] memory actionIds, address[] memory extensions)
    {
        (actionIds, extensions) = _groupManager.votedGroupActions(
            GROUP_ACTION_FACTORY_ADDRESS,
            GROUP_ACTION_TOKEN_ADDRESS,
            round
        );
    }

    /// @notice Set reward recipients for a specific action and group
    function setRecipients(
        uint256 actionId_,
        uint256 groupId,
        address[] calldata addrs,
        uint256[] calldata basisPoints
    ) external {
        if (!_center.isAccountJoined(tokenAddress, actionId, msg.sender))
            revert NotJoined();

        address ext = _center.extension(GROUP_ACTION_TOKEN_ADDRESS, actionId_);
        // Verify that the extension is created by the correct factory
        if (!_actionFactory.exists(ext)) revert InvalidExtension();
        if (_group.ownerOf(groupId) != msg.sender) revert NotGroupOwner();

        _setRecipients(msg.sender, actionId_, groupId, addrs, basisPoints);
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
            tokenAddress,
            round,
            actionId_,
            groupId,
            account,
            addrs,
            basisPoints
        );
    }

    /// @dev Check that address array has no duplicates
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

    // ============ View Functions ============

    /// @notice Get effective recipients for a group at a specific round
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

    /// @notice Get latest recipients for a group
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

    /// @notice Get actionIds that account has set recipients for at a round
    function actionIdsWithRecipients(
        address account,
        uint256 round
    ) external view returns (uint256[] memory) {
        return _actionIdsWithRecipients[account].values(round);
    }

    /// @notice Get groupIds that account has set recipients for at a round under specific actionId
    function groupIdsWithRecipients(
        address account,
        uint256 actionId_,
        uint256 round
    ) external view returns (uint256[] memory) {
        return _groupIdsWithRecipients[account][actionId_].values(round);
    }

    /// @notice Get reward amount for a specific recipient at a round for a specific group
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

        // If recipient is the group owner, return remaining after distribution
        if (recipient == groupOwner) {
            (, uint256 distributed) = _calculateRecipientAmounts(
                groupReward,
                addrs,
                bps
            );
            return groupReward - distributed;
        }

        // Find recipient's basis points and calculate their share
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

    /// @notice Get reward distribution for a specific group at a round
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

    /// @notice Get all group distributions for a group owner at a round
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

    /// @dev Build a single GroupDistribution struct
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

    // ============ IExtensionJoinedValue Implementation ============

    function isJoinedValueCalculated() external pure returns (bool) {
        return true;
    }

    function joinedValue() external view returns (uint256) {
        return _getTotalStaked(address(0));
    }

    function joinedValueByAccount(
        address account
    ) external view returns (uint256) {
        if (!_center.isAccountJoined(tokenAddress, actionId, account)) return 0;
        return _getTotalStaked(account);
    }

    /// @dev Get total staked from all valid group actions, converted to tokenAddress value
    function _getTotalStaked(
        address account
    ) internal view returns (uint256 total) {
        (uint256[] memory aids, address[] memory exts) = _groupManager
            .votedGroupActions(
                GROUP_ACTION_FACTORY_ADDRESS,
                GROUP_ACTION_TOKEN_ADDRESS,
                _join.currentRound()
            );
        for (uint256 i; i < exts.length; ) {
            address ext = _center.extension(
                GROUP_ACTION_TOKEN_ADDRESS,
                aids[i]
            );
            address stakeToken = ILOVE20ExtensionGroupAction(ext)
                .STAKE_TOKEN_ADDRESS();

            uint256 staked = account == address(0)
                ? _groupManager.totalStaked(GROUP_ACTION_TOKEN_ADDRESS, aids[i])
                : _groupManager.totalStakedByActionIdByOwner(
                    GROUP_ACTION_TOKEN_ADDRESS,
                    aids[i],
                    account
                );

            total += _convertToTokenValue(stakeToken, staked);
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Convert stakeToken amount to tokenAddress value
    /// Supports: 1) tokenAddress itself, 2) child token, 3) token with pair, 4) LP token
    function _convertToTokenValue(
        address stakeToken,
        uint256 amount
    ) internal view returns (uint256) {
        if (amount == 0) return 0;

        // Case 1: stakeToken is tokenAddress itself
        if (stakeToken == tokenAddress) return amount;

        // Case 2: LP token containing tokenAddress (check first, LP also has pair interface)
        if (
            TokenConversionLib.isLPTokenContainingTarget(
                stakeToken,
                tokenAddress
            )
        ) {
            return
                TokenConversionLib.convertLPToTokenValue(
                    stakeToken,
                    amount,
                    tokenAddress
                );
        }

        // Case 3 & 4: Child token or any token with direct Uniswap pair to tokenAddress
        return
            TokenConversionLib.convertViaUniswap(
                _center.uniswapV2FactoryAddress(),
                stakeToken,
                tokenAddress,
                amount
            );
    }

    // ============ Internal Functions ============

    /// @dev Calculate reward amounts for recipients based on group reward and basis points
    /// @param groupReward Total reward for the group
    /// @param addrs Array of recipient addresses
    /// @param bps Array of basis points corresponding to recipients
    /// @return amounts Array of reward amounts for each recipient
    /// @return distributed Total amount distributed to recipients
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
        if (!_center.isAccountJoined(tokenAddress, actionId, account)) return 0;

        uint256 total = reward(round);
        if (total == 0) return 0;

        (uint256 accountR, uint256 allR) = generatedRewardByVerifier(
            round,
            account
        );
        if (accountR == 0 || allR == 0) return 0;

        return (total * accountR) / allR;
    }

    /// @notice Get verifier reward and total reward from all valid group actions
    function generatedRewardByVerifier(
        uint256 round,
        address verifier
    ) public view returns (uint256 accountReward, uint256 totalReward) {
        (, address[] memory exts) = _groupManager.votedGroupActions(
            GROUP_ACTION_FACTORY_ADDRESS,
            GROUP_ACTION_TOKEN_ADDRESS,
            round
        );
        for (uint256 i; i < exts.length; ) {
            ILOVE20ExtensionGroupAction ga = ILOVE20ExtensionGroupAction(
                exts[i]
            );
            accountReward += ga.generatedRewardByVerifier(round, verifier);
            totalReward += ga.reward(round);
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Calculate service reward for a specific group
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

        uint256 groupReward = ILOVE20ExtensionGroupAction(ext)
            .generatedRewardByGroupId(round, groupId);
        if (groupReward == 0) return 0;

        return (ownerReward * groupReward) / totalReward;
    }

    /// @dev Override to distribute reward to recipients by group
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
                IERC20(tokenAddress).safeTransfer(msg.sender, remaining);
        }

        emit ClaimReward(tokenAddress, round, actionId, msg.sender, amount);
    }

    /// @dev Distribute reward to recipients and return total distributed amount
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

    /// @dev Distribute reward for a specific group
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

        IERC20 token = IERC20(tokenAddress);
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
