// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    LOVE20ExtensionBaseJoin
} from "@extension/src/LOVE20ExtensionBaseJoin.sol";
import {Join as JoinBase} from "@extension/src/base/Join.sol";
import {IJoin} from "@extension/src/interface/base/IJoin.sol";
import {
    ILOVE20ExtensionGroupAction
} from "./interface/ILOVE20ExtensionGroupAction.sol";
import {
    ILOVE20ExtensionGroupService
} from "./interface/ILOVE20ExtensionGroupService.sol";
import {ILOVE20GroupManager} from "./interface/ILOVE20GroupManager.sol";
import {
    EnumerableSet
} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    RoundHistoryAddressArray
} from "@extension/src/lib/RoundHistoryAddressArray.sol";
import {
    RoundHistoryUint256Array
} from "@extension/src/lib/RoundHistoryUint256Array.sol";
import {
    ILOVE20ExtensionFactory
} from "@extension/src/interface/ILOVE20ExtensionFactory.sol";
import {ILOVE20Vote} from "@core/interfaces/ILOVE20Vote.sol";
import {ILOVE20Launch} from "@core/interfaces/ILOVE20Launch.sol";
import {
    IUniswapV2Factory
} from "@core/uniswap-v2-core/interfaces/IUniswapV2Factory.sol";
import {
    IUniswapV2Pair
} from "@core/uniswap-v2-core/interfaces/IUniswapV2Pair.sol";
import {ILOVE20Group} from "@group/interfaces/ILOVE20Group.sol";

/// @title LOVE20ExtensionGroupService
/// @notice Extension contract for rewarding group service providers
/// @dev Service reward = Total service reward × (Account's group action reward / Group action total reward)
contract LOVE20ExtensionGroupService is
    LOVE20ExtensionBaseJoin,
    ILOVE20ExtensionGroupService
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using RoundHistoryAddressArray for RoundHistoryAddressArray.History;
    using RoundHistoryUint256Array for RoundHistoryUint256Array.History;
    using SafeERC20 for IERC20;

    // ============ Constants ============

    uint256 public constant BASIS_POINTS_BASE = 10000;

    // ============ Immutables ============

    address public immutable GROUP_ACTION_TOKEN_ADDRESS;
    address public immutable GROUP_ACTION_FACTORY_ADDRESS;
    uint256 public immutable MAX_RECIPIENTS;

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
        address groupActionFactoryAddress_,
        uint256 maxRecipients_
    ) LOVE20ExtensionBaseJoin(factory_, tokenAddress_) {
        // Validate groupActionTokenAddress: must be tokenAddress or its child token
        if (groupActionTokenAddress_ != tokenAddress_) {
            ILOVE20Launch launch = ILOVE20Launch(_center.launchAddress());
            if (!launch.isLOVE20Token(groupActionTokenAddress_)) {
                revert InvalidGroupActionTokenAddress();
            }
            if (
                ILOVE20Token(groupActionTokenAddress_).parentTokenAddress() !=
                tokenAddress_
            ) {
                revert InvalidGroupActionTokenAddress();
            }
        }

        GROUP_ACTION_TOKEN_ADDRESS = groupActionTokenAddress_;
        GROUP_ACTION_FACTORY_ADDRESS = groupActionFactoryAddress_;
        MAX_RECIPIENTS = maxRecipients_;
    }

    // ============ Write Functions ============

    /// @notice Join the service reward action
    function join(
        string[] memory verificationInfos
    ) public override(IJoin, JoinBase) {
        if (!hasActiveGroups(msg.sender)) revert NoActiveGroups();
        super.join(verificationInfos);
    }

    /// @notice Check if account has staked in any valid group action
    function hasActiveGroups(address account) public view returns (bool) {
        uint256 round = _join.currentRound();
        (
            address[] memory extensions,
            uint256[] memory actionIds_
        ) = _getValidGroupActions(round);

        uint256 len = extensions.length;
        for (uint256 i; i < len; ) {
            uint256 staked = ILOVE20GroupManager(
                ILOVE20ExtensionGroupAction(extensions[i])
                    .GROUP_MANAGER_ADDRESS()
            ).totalStakedByOwner(
                    GROUP_ACTION_TOKEN_ADDRESS,
                    actionIds_[i],
                    account
                );
            if (staked > 0) return true;
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @dev Get all valid group action extensions and their actionIds for a round
    function _getValidGroupActions(
        uint256 round
    )
        internal
        view
        returns (address[] memory extensions, uint256[] memory actionIds_)
    {
        ILOVE20Vote vote = ILOVE20Vote(_center.voteAddress());
        ILOVE20ExtensionFactory factory = ILOVE20ExtensionFactory(
            GROUP_ACTION_FACTORY_ADDRESS
        );

        uint256 actionCount = vote.votedActionIdsCount(
            GROUP_ACTION_TOKEN_ADDRESS,
            round
        );
        if (actionCount == 0) return (extensions, actionIds_);

        // Temp arrays (max size = actionCount)
        address[] memory tempExt = new address[](actionCount);
        uint256[] memory tempIds = new uint256[](actionCount);
        uint256 validCount;

        for (uint256 i; i < actionCount; ) {
            uint256 aid = vote.votedActionIdsAtIndex(
                GROUP_ACTION_TOKEN_ADDRESS,
                round,
                i
            );
            address ext = _center.extension(GROUP_ACTION_TOKEN_ADDRESS, aid);
            if (ext != address(0) && factory.exists(ext)) {
                tempExt[validCount] = ext;
                tempIds[validCount] = aid;
                unchecked {
                    ++validCount;
                }
            }
            unchecked {
                ++i;
            }
        }

        // Copy to correctly sized arrays
        extensions = new address[](validCount);
        actionIds_ = new uint256[](validCount);
        for (uint256 i; i < validCount; ) {
            extensions[i] = tempExt[i];
            actionIds_[i] = tempIds[i];
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Set reward recipients for a specific action and group
    function setRecipients(
        uint256 actionId_,
        uint256 groupId,
        address[] calldata addrs,
        uint256[] calldata basisPoints
    ) external {
        if (!_center.isAccountJoined(tokenAddress, actionId, msg.sender)) {
            revert NotJoined();
        }
        // Verify caller is the group owner
        ILOVE20Group group = ILOVE20Group(
            ILOVE20GroupManager(
                ILOVE20ExtensionGroupAction(
                    _center.extension(GROUP_ACTION_TOKEN_ADDRESS, actionId_)
                ).GROUP_MANAGER_ADDRESS()
            ).GROUP_ADDRESS()
        );
        if (group.ownerOf(groupId) != msg.sender) revert NotGroupOwner();

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
        if (len > MAX_RECIPIENTS) revert TooManyRecipients();

        // Validate and calculate total basis points
        uint256 totalBasisPoints;
        for (uint256 i; i < len; ) {
            if (addrs[i] == address(0)) revert ZeroAddress();
            if (addrs[i] == account) revert RecipientCannotBeSelf();
            if (basisPoints[i] == 0) revert ZeroBasisPoints();
            totalBasisPoints += basisPoints[i];
            unchecked {
                ++i;
            }
        }
        if (totalBasisPoints > BASIS_POINTS_BASE) revert InvalidBasisPoints();

        // Check for duplicate addresses
        _checkNoDuplicates(addrs);

        uint256 currentRound = _verify.currentRound();
        _recipientsHistory[account][actionId_][groupId].record(
            currentRound,
            addrs
        );
        _basisPointsHistory[account][actionId_][groupId].record(
            currentRound,
            basisPoints
        );

        // Maintain indexes
        if (len > 0) {
            _addToIndex(
                _actionIdsWithRecipients[account],
                actionId_,
                currentRound
            );
            _addToIndex(
                _groupIdsWithRecipients[account][actionId_],
                groupId,
                currentRound
            );
        } else {
            // Remove groupId, and if no groups left, remove actionId
            if (
                _removeFromIndex(
                    _groupIdsWithRecipients[account][actionId_],
                    groupId,
                    currentRound
                )
            ) {
                if (
                    _groupIdsWithRecipients[account][actionId_]
                        .values(currentRound)
                        .length == 0
                ) {
                    _removeFromIndex(
                        _actionIdsWithRecipients[account],
                        actionId_,
                        currentRound
                    );
                }
            }
        }

        emit RecipientsUpdate(
            tokenAddress,
            currentRound,
            actionId_,
            groupId,
            account,
            addrs,
            basisPoints
        );
    }

    /// @dev Add value to index if not exists
    function _addToIndex(
        RoundHistoryUint256Array.History storage history,
        uint256 value,
        uint256 round
    ) internal {
        uint256[] memory existing = history.values(round);
        uint256 len = existing.length;
        for (uint256 i; i < len; ) {
            if (existing[i] == value) return; // Already exists
            unchecked {
                ++i;
            }
        }
        uint256[] memory updated = new uint256[](len + 1);
        for (uint256 i; i < len; ) {
            updated[i] = existing[i];
            unchecked {
                ++i;
            }
        }
        updated[len] = value;
        history.record(round, updated);
    }

    /// @dev Remove value from index, returns true if removed
    function _removeFromIndex(
        RoundHistoryUint256Array.History storage history,
        uint256 value,
        uint256 round
    ) internal returns (bool removed) {
        uint256[] memory existing = history.values(round);
        uint256 len = existing.length;
        uint256 idx = type(uint256).max;
        for (uint256 i; i < len; ) {
            if (existing[i] == value) {
                idx = i;
                break;
            }
            unchecked {
                ++i;
            }
        }
        if (idx == type(uint256).max) return false;

        uint256[] memory updated = new uint256[](len - 1);
        for (uint256 i; i < idx; ) {
            updated[i] = existing[i];
            unchecked {
                ++i;
            }
        }
        for (uint256 i = idx + 1; i < len; ) {
            updated[i - 1] = existing[i];
            unchecked {
                ++i;
            }
        }
        history.record(round, updated);
        return true;
    }

    /// @dev Check that address array has no duplicates
    function _checkNoDuplicates(address[] memory addrs) internal pure {
        uint256 len = addrs.length;
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

        uint256 totalBps;
        uint256 recipientBps;
        uint256 len = addrs.length;
        for (uint256 i; i < len; ) {
            totalBps += bps[i];
            if (addrs[i] == recipient) recipientBps = bps[i];
            unchecked {
                ++i;
            }
        }

        // If recipient is the groupOwner, return remaining after distribution
        if (recipient == groupOwner) {
            return groupReward - (groupReward * totalBps) / BASIS_POINTS_BASE;
        }
        return (groupReward * recipientBps) / BASIS_POINTS_BASE;
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
        uint256 groupReward = _calculateGroupServiceReward(
            round,
            groupOwner,
            actionId_,
            groupId
        );
        addrs = _recipientsHistory[groupOwner][actionId_][groupId].values(
            round
        );
        basisPoints = _basisPointsHistory[groupOwner][actionId_][groupId]
            .values(round);

        uint256 len = addrs.length;
        amounts = new uint256[](len);
        uint256 distributed;
        for (uint256 i; i < len; ) {
            amounts[i] = (groupReward * basisPoints[i]) / BASIS_POINTS_BASE;
            distributed += amounts[i];
            unchecked {
                ++i;
            }
        }
        ownerAmount = groupReward - distributed;
    }

    /// @notice Get all group distributions for a group owner at a round
    function rewardDistributionAll(
        uint256 round,
        address groupOwner
    ) external view returns (GroupDistribution[] memory distributions) {
        uint256[] memory ownerActionIds = _actionIdsWithRecipients[groupOwner]
            .values(round);
        uint256 actionLen = ownerActionIds.length;

        // Count total groups
        uint256 totalGroups;
        for (uint256 i; i < actionLen; ) {
            totalGroups += _groupIdsWithRecipients[groupOwner][
                ownerActionIds[i]
            ].values(round).length;
            unchecked {
                ++i;
            }
        }

        // Build distributions
        distributions = new GroupDistribution[](totalGroups);
        uint256 idx;
        for (uint256 i; i < actionLen; ) {
            uint256[] memory gids = _groupIdsWithRecipients[groupOwner][
                ownerActionIds[i]
            ].values(round);
            uint256 gidLen = gids.length;
            for (uint256 j; j < gidLen; ) {
                distributions[idx] = _buildGroupDistribution(
                    round,
                    groupOwner,
                    ownerActionIds[i],
                    gids[j]
                );
                unchecked {
                    ++idx;
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
    ) internal view returns (GroupDistribution memory dist) {
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

        uint256 len = addrs.length;
        uint256[] memory amounts = new uint256[](len);
        uint256 distributed;
        for (uint256 i; i < len; ) {
            amounts[i] = (groupReward * bps[i]) / BASIS_POINTS_BASE;
            distributed += amounts[i];
            unchecked {
                ++i;
            }
        }

        dist = GroupDistribution({
            actionId: actionId_,
            groupId: groupId,
            groupReward: groupReward,
            recipients: addrs,
            basisPoints: bps,
            amounts: amounts,
            ownerAmount: groupReward - distributed
        });
    }

    // ============ IExtensionJoinedValue Implementation ============

    function isJoinedValueCalculated() external view returns (bool) {
        return GROUP_ACTION_TOKEN_ADDRESS != tokenAddress;
    }

    function joinedValue() external view returns (uint256) {
        return _convertToParentTokenValue(_getTotalStaked(address(0)));
    }

    function joinedValueByAccount(
        address account
    ) external view returns (uint256) {
        if (!_center.isAccountJoined(tokenAddress, actionId, account)) return 0;
        return _convertToParentTokenValue(_getTotalStaked(account));
    }

    /// @dev Convert child token amount to parent token value using Uniswap V2 price
    function _convertToParentTokenValue(
        uint256 amount
    ) internal view returns (uint256) {
        if (amount == 0 || GROUP_ACTION_TOKEN_ADDRESS == tokenAddress) {
            return amount;
        }

        // Get Uniswap V2 pair
        IUniswapV2Factory uniswapFactory = IUniswapV2Factory(
            _center.uniswapV2FactoryAddress()
        );
        address pairAddress = uniswapFactory.getPair(
            tokenAddress,
            GROUP_ACTION_TOKEN_ADDRESS
        );
        if (pairAddress == address(0)) return 0;

        // Get reserves and calculate price
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        if (reserve0 == 0 || reserve1 == 0) return 0;

        // Determine which reserve is which token
        address token0 = pair.token0();
        uint256 parentReserve;
        uint256 childReserve;
        if (token0 == tokenAddress) {
            parentReserve = reserve0;
            childReserve = reserve1;
        } else {
            parentReserve = reserve1;
            childReserve = reserve0;
        }

        // Convert: parentValue = childAmount * parentReserve / childReserve
        return (amount * parentReserve) / childReserve;
    }

    /// @dev Get total staked from all valid group actions (account=address(0) for total)
    function _getTotalStaked(
        address account
    ) internal view returns (uint256 totalStaked) {
        (
            address[] memory extensions,
            uint256[] memory actionIds_
        ) = _getValidGroupActions(_verify.currentRound());

        uint256 len = extensions.length;
        for (uint256 i; i < len; ) {
            ILOVE20GroupManager manager = ILOVE20GroupManager(
                ILOVE20ExtensionGroupAction(extensions[i])
                    .GROUP_MANAGER_ADDRESS()
            );
            if (account == address(0)) {
                totalStaked += manager.totalStaked(
                    GROUP_ACTION_TOKEN_ADDRESS,
                    actionIds_[i]
                );
            } else {
                totalStaked += manager.totalStakedByOwner(
                    GROUP_ACTION_TOKEN_ADDRESS,
                    actionIds_[i],
                    account
                );
            }
            unchecked {
                ++i;
            }
        }
    }

    // ============ Internal Functions ============

    function _calculateReward(
        uint256 round,
        address account
    ) internal view override returns (uint256) {
        if (!_center.isAccountJoined(tokenAddress, actionId, account)) return 0;

        // Get total reward (from storage or expected from mint)
        uint256 totalReward = reward(round);
        if (totalReward == 0) return 0;

        (
            uint256 accountTotalReward,
            uint256 allActionsTotalReward
        ) = generatedRewardByVerifier(round, account);

        if (accountTotalReward == 0 || allActionsTotalReward == 0) return 0;

        return (totalReward * accountTotalReward) / allActionsTotalReward;
    }

    /// @notice Get verifier reward and total reward from all valid group actions
    function generatedRewardByVerifier(
        uint256 round,
        address verifier
    ) public view returns (uint256 accountReward, uint256 totalReward) {
        (address[] memory extensions, ) = _getValidGroupActions(round);

        uint256 len = extensions.length;
        for (uint256 i; i < len; ) {
            ILOVE20ExtensionGroupAction groupAction = ILOVE20ExtensionGroupAction(
                    extensions[i]
                );
            accountReward += groupAction.generatedRewardByVerifier(
                round,
                verifier
            );
            totalReward += groupAction.reward(round);
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
        (uint256 totalOwnerReward, ) = rewardByAccount(round, groupOwner);
        if (totalOwnerReward == 0) return 0;

        (uint256 accountTotalReward, ) = generatedRewardByVerifier(
            round,
            groupOwner
        );
        if (accountTotalReward == 0) return 0;

        // Get this group's reward from the group action
        address extensionAddr = _center.extension(
            GROUP_ACTION_TOKEN_ADDRESS,
            actionId_
        );
        if (extensionAddr == address(0)) return 0;

        ILOVE20ExtensionGroupAction groupAction = ILOVE20ExtensionGroupAction(
            extensionAddr
        );
        uint256 groupReward = groupAction.generatedRewardByGroupId(
            round,
            groupId
        );
        if (groupReward == 0) return 0;

        // Calculate this group's share of service reward
        return (totalOwnerReward * groupReward) / accountTotalReward;
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
            uint256 totalDistributed = _distributeToRecipients(round, amount);

            // Remaining to the original account
            uint256 remaining = amount - totalDistributed;
            if (remaining > 0) {
                IERC20(tokenAddress).safeTransfer(msg.sender, remaining);
            }
        }

        emit ClaimReward(tokenAddress, round, actionId, msg.sender, amount);
    }

    /// @dev Distribute reward to recipients and return total distributed amount
    function _distributeToRecipients(
        uint256 round,
        uint256 /* totalAmount */
    ) internal returns (uint256 totalDistributed) {
        address sender = msg.sender;
        uint256[] memory aids = _actionIdsWithRecipients[sender].values(round);
        uint256 aidLen = aids.length;

        for (uint256 i; i < aidLen; ) {
            uint256[] memory gids = _groupIdsWithRecipients[sender][aids[i]]
                .values(round);
            uint256 gidLen = gids.length;
            for (uint256 j; j < gidLen; ) {
                totalDistributed += _distributeForGroup(
                    round,
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

    /// @dev Distribute reward for a specific group
    function _distributeForGroup(
        uint256 round,
        uint256 actionId_,
        uint256 groupId
    ) internal returns (uint256 distributed) {
        address sender = msg.sender;
        uint256 groupReward = _calculateGroupServiceReward(
            round,
            sender,
            actionId_,
            groupId
        );
        if (groupReward == 0) return 0;

        address[] memory addrs = _recipientsHistory[sender][actionId_][groupId]
            .values(round);
        uint256[] memory bps = _basisPointsHistory[sender][actionId_][groupId]
            .values(round);

        IERC20 token = IERC20(tokenAddress);
        uint256 len = addrs.length;
        for (uint256 k; k < len; ) {
            uint256 amt = (groupReward * bps[k]) / BASIS_POINTS_BASE;
            if (amt > 0) {
                token.safeTransfer(addrs[k], amt);
                distributed += amt;
            }
            unchecked {
                ++k;
            }
        }
    }
}
