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

    /// @dev account => recipient addresses history
    mapping(address => RoundHistoryAddressArray.History)
        internal _recipientsHistory;

    /// @dev account => basis points history
    mapping(address => RoundHistoryUint256Array.History)
        internal _basisPointsHistory;

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
        if (!_hasActiveGroups(msg.sender)) revert NoActiveGroups();

        super.join(verificationInfos);
    }

    /// @dev Check if account has staked in any valid group action
    function _hasActiveGroups(address account) internal view returns (bool) {
        ILOVE20Vote vote = ILOVE20Vote(_center.voteAddress());
        ILOVE20ExtensionFactory factory = ILOVE20ExtensionFactory(
            GROUP_ACTION_FACTORY_ADDRESS
        );
        uint256 currentRound = _join.currentRound();

        uint256 actionCount = vote.votedActionIdsCount(
            GROUP_ACTION_TOKEN_ADDRESS,
            currentRound
        );
        for (uint256 i = 0; i < actionCount; i++) {
            uint256 actionId = vote.votedActionIdsAtIndex(
                GROUP_ACTION_TOKEN_ADDRESS,
                currentRound,
                i
            );
            address extensionAddr = _center.extension(
                GROUP_ACTION_TOKEN_ADDRESS,
                actionId
            );
            if (extensionAddr == address(0) || !factory.exists(extensionAddr))
                continue;

            ILOVE20ExtensionGroupAction groupAction = ILOVE20ExtensionGroupAction(
                    extensionAddr
                );
            uint256 stakedAmount = ILOVE20GroupManager(
                groupAction.GROUP_MANAGER_ADDRESS()
            ).totalStakedByOwner(GROUP_ACTION_TOKEN_ADDRESS, actionId, account);
            if (stakedAmount > 0) return true;
        }
        return false;
    }

    /// @notice Set reward recipients for the caller
    function setRecipients(
        address[] calldata addrs,
        uint256[] calldata basisPoints
    ) external {
        if (!_center.isAccountJoined(tokenAddress, actionId, msg.sender)) {
            revert NotJoined();
        }
        _setRecipients(msg.sender, addrs, basisPoints);
    }

    function _setRecipients(
        address account,
        address[] memory addrs,
        uint256[] memory basisPoints
    ) internal {
        uint256 len = addrs.length;
        if (len != basisPoints.length) revert ArrayLengthMismatch();
        if (len > MAX_RECIPIENTS) revert TooManyRecipients();

        // Validate and calculate total basis points
        uint256 totalBasisPoints;
        for (uint256 i = 0; i < len; i++) {
            if (addrs[i] == address(0)) revert ZeroAddress();
            if (basisPoints[i] == 0) revert ZeroBasisPoints();
            totalBasisPoints += basisPoints[i];
        }
        if (totalBasisPoints > BASIS_POINTS_BASE) revert InvalidBasisPoints();

        // Check for duplicate addresses (separate loop for clarity)
        _checkNoDuplicates(addrs);

        uint256 currentRound = _verify.currentRound();
        _recipientsHistory[account].record(currentRound, addrs);
        _basisPointsHistory[account].record(currentRound, basisPoints);

        emit RecipientsUpdate(
            tokenAddress,
            currentRound,
            actionId,
            account,
            addrs,
            basisPoints
        );
    }

    /// @dev Check that address array has no duplicates
    /// @notice Uses O(n²) comparison which is acceptable for small arrays (MAX_RECIPIENTS is typically small)
    function _checkNoDuplicates(address[] memory addrs) internal pure {
        uint256 len = addrs.length;
        for (uint256 i = 1; i < len; i++) {
            address addr = addrs[i];
            for (uint256 j = 0; j < i; j++) {
                if (addrs[j] == addr) revert DuplicateAddress();
            }
        }
    }

    // ============ View Functions ============

    /// @notice Get effective recipients for a group owner at a specific round
    function recipients(
        address groupOwner,
        uint256 round
    )
        external
        view
        returns (address[] memory addrs, uint256[] memory basisPoints)
    {
        addrs = _recipientsHistory[groupOwner].values(round);
        basisPoints = _basisPointsHistory[groupOwner].values(round);
    }

    /// @notice Get latest recipients for a group owner
    function recipientsLatest(
        address groupOwner
    )
        external
        view
        returns (address[] memory addrs, uint256[] memory basisPoints)
    {
        addrs = _recipientsHistory[groupOwner].latestValues();
        basisPoints = _basisPointsHistory[groupOwner].latestValues();
    }

    /// @notice Get reward amount for a specific recipient at a round
    function rewardByRecipient(
        uint256 round,
        address groupOwner,
        address recipient
    ) external view returns (uint256) {
        (uint256 totalAmount, ) = rewardByAccount(round, groupOwner);
        if (totalAmount == 0) return 0;

        address[] memory addrs = _recipientsHistory[groupOwner].values(round);
        uint256[] memory basisPoints = _basisPointsHistory[groupOwner].values(
            round
        );

        uint256 totalBasisPoints;
        uint256 recipientBasisPoints;
        for (uint256 i = 0; i < addrs.length; i++) {
            totalBasisPoints += basisPoints[i];
            if (addrs[i] == recipient) {
                recipientBasisPoints = basisPoints[i];
            }
        }

        // If recipient is the groupOwner, return remaining after distribution
        if (recipient == groupOwner) {
            uint256 distributed = (totalAmount * totalBasisPoints) /
                BASIS_POINTS_BASE;
            return totalAmount - distributed;
        }

        return (totalAmount * recipientBasisPoints) / BASIS_POINTS_BASE;
    }

    /// @notice Get reward distribution for a group owner at a round
    function rewardDistribution(
        uint256 round,
        address groupOwner
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
        (uint256 totalAmount, ) = rewardByAccount(round, groupOwner);

        addrs = _recipientsHistory[groupOwner].values(round);
        basisPoints = _basisPointsHistory[groupOwner].values(round);
        amounts = new uint256[](addrs.length);

        uint256 distributed;
        for (uint256 i = 0; i < addrs.length; i++) {
            amounts[i] = (totalAmount * basisPoints[i]) / BASIS_POINTS_BASE;
            distributed += amounts[i];
        }
        ownerAmount = totalAmount - distributed;
    }

    // ============ IExtensionJoinedValue Implementation ============

    function isJoinedValueCalculated() external pure returns (bool) {
        return false;
    }

    function joinedValue() external view returns (uint256) {
        uint256 staked = _getTotalStakedFromAllActions();
        return _convertToParentTokenValue(staked);
    }

    function joinedValueByAccount(
        address account
    ) external view returns (uint256) {
        if (!_center.isAccountJoined(tokenAddress, actionId, account)) return 0;
        uint256 staked = _getTotalStakedByOwnerFromAllActions(account);
        return _convertToParentTokenValue(staked);
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

    /// @dev Get total staked from all valid group actions
    function _getTotalStakedFromAllActions()
        internal
        view
        returns (uint256 totalStaked)
    {
        ILOVE20Vote vote = ILOVE20Vote(_center.voteAddress());
        ILOVE20ExtensionFactory factory = ILOVE20ExtensionFactory(
            GROUP_ACTION_FACTORY_ADDRESS
        );
        uint256 currentRound = _verify.currentRound();

        uint256 actionCount = vote.votedActionIdsCount(
            GROUP_ACTION_TOKEN_ADDRESS,
            currentRound
        );
        for (uint256 i = 0; i < actionCount; i++) {
            uint256 actionId_ = vote.votedActionIdsAtIndex(
                GROUP_ACTION_TOKEN_ADDRESS,
                currentRound,
                i
            );
            address extensionAddr = _center.extension(
                GROUP_ACTION_TOKEN_ADDRESS,
                actionId_
            );
            if (extensionAddr == address(0) || !factory.exists(extensionAddr))
                continue;

            ILOVE20ExtensionGroupAction groupAction = ILOVE20ExtensionGroupAction(
                    extensionAddr
                );
            totalStaked += ILOVE20GroupManager(
                groupAction.GROUP_MANAGER_ADDRESS()
            ).totalStaked(GROUP_ACTION_TOKEN_ADDRESS, actionId_);
        }
    }

    /// @dev Get total staked by owner from all valid group actions
    function _getTotalStakedByOwnerFromAllActions(
        address account
    ) internal view returns (uint256 totalStaked) {
        ILOVE20Vote vote = ILOVE20Vote(_center.voteAddress());
        ILOVE20ExtensionFactory factory = ILOVE20ExtensionFactory(
            GROUP_ACTION_FACTORY_ADDRESS
        );
        uint256 currentRound = _verify.currentRound();

        uint256 actionCount = vote.votedActionIdsCount(
            GROUP_ACTION_TOKEN_ADDRESS,
            currentRound
        );
        for (uint256 i = 0; i < actionCount; i++) {
            uint256 actionId_ = vote.votedActionIdsAtIndex(
                GROUP_ACTION_TOKEN_ADDRESS,
                currentRound,
                i
            );
            address extensionAddr = _center.extension(
                GROUP_ACTION_TOKEN_ADDRESS,
                actionId_
            );
            if (extensionAddr == address(0) || !factory.exists(extensionAddr))
                continue;

            ILOVE20ExtensionGroupAction groupAction = ILOVE20ExtensionGroupAction(
                    extensionAddr
                );
            totalStaked += ILOVE20GroupManager(
                groupAction.GROUP_MANAGER_ADDRESS()
            ).totalStakedByOwner(
                    GROUP_ACTION_TOKEN_ADDRESS,
                    actionId_,
                    account
                );
        }
    }

    // ============ Internal Functions ============

    function _calculateReward(
        uint256 round,
        address account
    ) internal view override returns (uint256) {
        if (!_center.isAccountJoined(tokenAddress, actionId, account)) return 0;

        // Get total reward (from storage or expected from mint)
        uint256 totalReward = _reward[round];
        if (totalReward == 0) {
            (totalReward, ) = _mint.actionRewardByActionIdByAccount(
                tokenAddress,
                round,
                actionId,
                address(this)
            );
        }
        if (totalReward == 0) return 0;

        (
            uint256 accountTotalReward,
            uint256 allActionsTotalReward
        ) = _getRewardsFromAllActions(round, account);

        if (accountTotalReward == 0 || allActionsTotalReward == 0) return 0;

        return (totalReward * accountTotalReward) / allActionsTotalReward;
    }

    /// @dev Get account reward and total reward from all valid group actions
    function _getRewardsFromAllActions(
        uint256 round,
        address account
    ) internal view returns (uint256 accountReward, uint256 totalReward) {
        ILOVE20Vote vote = ILOVE20Vote(_center.voteAddress());
        ILOVE20ExtensionFactory factory = ILOVE20ExtensionFactory(
            GROUP_ACTION_FACTORY_ADDRESS
        );

        uint256 actionCount = vote.votedActionIdsCount(
            GROUP_ACTION_TOKEN_ADDRESS,
            round
        );
        for (uint256 i = 0; i < actionCount; i++) {
            uint256 actionId_ = vote.votedActionIdsAtIndex(
                GROUP_ACTION_TOKEN_ADDRESS,
                round,
                i
            );
            address extensionAddr = _center.extension(
                GROUP_ACTION_TOKEN_ADDRESS,
                actionId_
            );
            if (extensionAddr == address(0) || !factory.exists(extensionAddr))
                continue;

            ILOVE20ExtensionGroupAction groupAction = ILOVE20ExtensionGroupAction(
                    extensionAddr
                );
            accountReward += groupAction.generatedRewardByVerifier(
                round,
                account
            );
            totalReward += groupAction.reward(round);
        }
    }

    /// @dev Override to distribute reward to recipients
    function _claimReward(
        uint256 round
    ) internal override returns (uint256 amount) {
        bool isMinted;
        (amount, isMinted) = rewardByAccount(round, msg.sender);
        if (isMinted) revert AlreadyClaimed();

        _claimedReward[round][msg.sender] = amount;

        if (amount > 0) {
            IERC20 token = IERC20(tokenAddress);
            address[] memory addrs = _recipientsHistory[msg.sender].values(
                round
            );
            uint256[] memory basisPoints = _basisPointsHistory[msg.sender]
                .values(round);

            uint256 distributed;
            for (uint256 i = 0; i < addrs.length; i++) {
                uint256 recipientAmount = (amount * basisPoints[i]) /
                    BASIS_POINTS_BASE;
                if (recipientAmount > 0) {
                    token.safeTransfer(addrs[i], recipientAmount);
                    distributed += recipientAmount;
                }
            }

            // Remaining to the original account
            uint256 remaining = amount - distributed;
            if (remaining > 0) {
                token.safeTransfer(msg.sender, remaining);
            }
        }

        emit ClaimReward(tokenAddress, round, actionId, msg.sender, amount);
    }
}
