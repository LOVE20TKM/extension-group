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
    ILOVE20ExtensionGroupActionFactory
} from "./interface/ILOVE20ExtensionGroupActionFactory.sol";
import {
    ILOVE20ExtensionGroupService
} from "./interface/ILOVE20ExtensionGroupService.sol";
import {ILOVE20GroupManager} from "./interface/ILOVE20GroupManager.sol";
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
    using RoundHistoryAddressArray for RoundHistoryAddressArray.History;
    using RoundHistoryUint256Array for RoundHistoryUint256Array.History;
    using SafeERC20 for IERC20;

    // ============ Constants ============

    uint256 public constant BASIS_POINTS_BASE = 1e18;

    // ============ Immutables ============

    address public immutable GROUP_ACTION_TOKEN_ADDRESS;
    address public immutable GROUP_ACTION_FACTORY_ADDRESS;
    uint256 public immutable MAX_RECIPIENTS;

    // ============ Cached Interfaces ============

    ILOVE20GroupManager internal immutable _groupManager;
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
        address groupActionFactoryAddress_,
        uint256 maxRecipients_
    ) LOVE20ExtensionBaseJoin(factory_, tokenAddress_) {
        if (groupActionTokenAddress_ != tokenAddress_) {
            if (
                !ILOVE20Launch(_center.launchAddress()).isLOVE20Token(
                    groupActionTokenAddress_
                ) ||
                ILOVE20Token(groupActionTokenAddress_).parentTokenAddress() !=
                tokenAddress_
            ) {
                revert InvalidGroupActionTokenAddress();
            }
        }
        GROUP_ACTION_TOKEN_ADDRESS = groupActionTokenAddress_;
        GROUP_ACTION_FACTORY_ADDRESS = groupActionFactoryAddress_;
        MAX_RECIPIENTS = maxRecipients_;

        // Cache frequently used interfaces
        _actionFactory = ILOVE20ExtensionGroupActionFactory(
            groupActionFactoryAddress_
        );
        _groupManager = ILOVE20GroupManager(
            _actionFactory.GROUP_MANAGER_ADDRESS()
        );
        _group = ILOVE20Group(_groupManager.GROUP_ADDRESS());
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
        uint256 balance = _group.balanceOf(account);

        for (uint256 i = 0; i < balance; i++) {
            uint256 groupId = _group.tokenOfOwnerByIndex(account, i);
            if (
                _groupManager.actionIdsByGroupIdCount(
                    GROUP_ACTION_FACTORY_ADDRESS,
                    GROUP_ACTION_TOKEN_ADDRESS,
                    groupId
                ) > 0
            ) {
                return true;
            }
        }

        return false;
    }

    function validGroupActions(
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
        ILOVE20Group group = ILOVE20Group(
            ILOVE20GroupManager(
                ILOVE20ExtensionGroupAction(ext).GROUP_MANAGER_ADDRESS()
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

        uint256 totalBps;
        uint256 recipientBps;
        for (uint256 i; i < addrs.length; ) {
            totalBps += bps[i];
            if (addrs[i] == recipient) recipientBps = bps[i];
            unchecked {
                ++i;
            }
        }

        if (recipient == groupOwner)
            return groupReward - (groupReward * totalBps) / BASIS_POINTS_BASE;
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

        uint256[] memory amounts = new uint256[](addrs.length);
        uint256 distributed;
        for (uint256 i; i < addrs.length; ) {
            amounts[i] = (groupReward * bps[i]) / BASIS_POINTS_BASE;
            distributed += amounts[i];
            unchecked {
                ++i;
            }
        }

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
            address stakeToken = ILOVE20ExtensionGroupAction(exts[i])
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
        if (_isLPTokenContainingTarget(stakeToken)) {
            return _convertLPToTokenValue(stakeToken, amount);
        }

        // Case 3 & 4: Child token or any token with direct Uniswap pair to tokenAddress
        return _convertViaUniswap(stakeToken, tokenAddress, amount);
    }

    /// @dev Check if token is a Uniswap V2 LP token containing tokenAddress
    function _isLPTokenContainingTarget(
        address token
    ) internal view returns (bool) {
        try IUniswapV2Pair(token).token0() returns (address t0) {
            try IUniswapV2Pair(token).token1() returns (address t1) {
                return t0 == tokenAddress || t1 == tokenAddress;
            } catch {
                return false;
            }
        } catch {
            return false;
        }
    }

    /// @dev Convert LP token amount to tokenAddress value
    /// LP must contain tokenAddress; both sides have equal value in AMM
    function _convertLPToTokenValue(
        address lpToken,
        uint256 lpAmount
    ) internal view returns (uint256) {
        IUniswapV2Pair pair = IUniswapV2Pair(lpToken);
        uint256 totalSupply = pair.totalSupply();
        if (totalSupply == 0) return 0;

        (uint112 r0, uint112 r1, ) = pair.getReserves();

        // Get tokenAddress reserve (LP must contain tokenAddress)
        uint256 tokenReserve = pair.token0() == tokenAddress
            ? uint256(r0)
            : uint256(r1);

        // LP value = tokenAddress side * 2 (AMM ensures equal value on both sides)
        return (tokenReserve * lpAmount * 2) / totalSupply;
    }

    /// @dev Convert amount via Uniswap pair, returns 0 if no pair or no liquidity
    function _convertViaUniswap(
        address fromToken,
        address toToken,
        uint256 amount
    ) internal view returns (uint256) {
        if (amount == 0) return 0;

        address pairAddr = IUniswapV2Factory(_center.uniswapV2FactoryAddress())
            .getPair(fromToken, toToken);
        if (pairAddr == address(0)) return 0;

        IUniswapV2Pair pair = IUniswapV2Pair(pairAddr);
        (uint112 r0, uint112 r1, ) = pair.getReserves();
        if (r0 == 0 || r1 == 0) return 0;

        (uint256 toR, uint256 fromR) = pair.token0() == fromToken
            ? (uint256(r1), uint256(r0))
            : (uint256(r0), uint256(r1));
        return (amount * toR) / fromR;
    }

    // ============ Internal Functions ============

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

        IERC20 token = IERC20(tokenAddress);
        for (uint256 i; i < addrs.length; ) {
            uint256 amt = (groupReward * bps[i]) / BASIS_POINTS_BASE;
            if (amt > 0) {
                token.safeTransfer(addrs[i], amt);
                distributed += amt;
            }
            unchecked {
                ++i;
            }
        }
    }
}
