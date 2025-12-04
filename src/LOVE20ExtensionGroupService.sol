// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ExtensionAccounts} from "@extension/src/base/ExtensionAccounts.sol";
import {ExtensionReward} from "@extension/src/base/ExtensionReward.sol";
import {
    ExtensionVerificationInfo
} from "@extension/src/base/ExtensionVerificationInfo.sol";
import {ILOVE20Extension} from "@extension/src/interface/ILOVE20Extension.sol";
import {IExtensionExit} from "@extension/src/interface/base/IExtensionExit.sol";
import {
    ILOVE20ExtensionGroupAction
} from "./interface/ILOVE20ExtensionGroupAction.sol";
import {
    ILOVE20ExtensionGroupService
} from "./interface/ILOVE20ExtensionGroupService.sol";
import {
    EnumerableSet
} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";
import {
    RoundHistoryAddressArray
} from "@extension/src/lib/RoundHistoryAddressArray.sol";
import {
    RoundHistoryUint256Array
} from "@extension/src/lib/RoundHistoryUint256Array.sol";

/// @title LOVE20ExtensionGroupService
/// @notice Extension contract for rewarding group service providers
/// @dev Service reward = Total service reward × (Account's group action reward / Group action total reward)
contract LOVE20ExtensionGroupService is
    ExtensionAccounts,
    ExtensionReward,
    ExtensionVerificationInfo,
    ILOVE20Extension
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using RoundHistoryAddressArray for RoundHistoryAddressArray.History;
    using RoundHistoryUint256Array for RoundHistoryUint256Array.History;

    // ============ Errors ============

    error NoActiveGroups();
    error AlreadyJoined();
    error NotJoined();
    error InvalidBasisPoints();
    error TooManyRecipients();
    error ZeroAddress();
    error ZeroBasisPoints();
    error ArrayLengthMismatch();

    // ============ Events ============

    event Join(address indexed account, uint256 joinedValue, uint256 round);
    event Exit(address indexed account, uint256 round);
    event RecipientsUpdated(
        address indexed account,
        uint256 round,
        address[] recipients,
        uint256[] basisPoints
    );

    // ============ Constants ============

    uint256 public constant BASIS_POINTS_BASE = 10000;

    // ============ Immutables ============

    address public immutable GROUP_ACTION_ADDRESS;
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
        address groupActionAddress_,
        uint256 maxRecipients_
    ) ExtensionReward(factory_, tokenAddress_) {
        GROUP_ACTION_ADDRESS = groupActionAddress_;
        MAX_RECIPIENTS = maxRecipients_;
    }

    // ============ Write Functions ============

    /// @notice Join the service reward action
    function join() external {
        _autoInitialize();

        if (_accounts.contains(msg.sender)) revert AlreadyJoined();

        uint256 stakedAmount = ILOVE20ExtensionGroupAction(GROUP_ACTION_ADDRESS)
            .totalStakedByOwner(msg.sender);
        if (stakedAmount == 0) revert NoActiveGroups();

        _addAccount(msg.sender);

        emit Join(msg.sender, stakedAmount, _join.currentRound());
    }

    /// @notice Set reward recipients for the caller
    function setRecipients(
        address[] calldata addrs,
        uint256[] calldata basisPoints
    ) external {
        if (!_accounts.contains(msg.sender)) revert NotJoined();
        _setRecipients(msg.sender, addrs, basisPoints);
    }

    /// @inheritdoc IExtensionExit
    function exit() external {
        _removeAccount(msg.sender);
        emit Exit(msg.sender, _join.currentRound());
    }

    function _setRecipients(
        address account,
        address[] memory addrs,
        uint256[] memory basisPoints
    ) internal {
        if (addrs.length != basisPoints.length) revert ArrayLengthMismatch();
        if (addrs.length > MAX_RECIPIENTS) revert TooManyRecipients();

        uint256 totalBasisPoints;
        for (uint256 i = 0; i < addrs.length; i++) {
            if (addrs[i] == address(0)) revert ZeroAddress();
            if (basisPoints[i] == 0) revert ZeroBasisPoints();
            totalBasisPoints += basisPoints[i];
        }
        if (totalBasisPoints > BASIS_POINTS_BASE) revert InvalidBasisPoints();

        uint256 currentRound = _join.currentRound();
        _recipientsHistory[account].record(currentRound, addrs);
        _basisPointsHistory[account].record(currentRound, basisPoints);

        emit RecipientsUpdated(account, currentRound, addrs, basisPoints);
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
        addrs = _recipientsHistory[groupOwner].value(round);
        basisPoints = _basisPointsHistory[groupOwner].value(round);
    }

    /// @notice Get latest recipients for a group owner
    function recipientsLatest(
        address groupOwner
    )
        external
        view
        returns (address[] memory addrs, uint256[] memory basisPoints)
    {
        addrs = _recipientsHistory[groupOwner].latestValue();
        basisPoints = _basisPointsHistory[groupOwner].latestValue();
    }

    /// @notice Get reward amount for a specific recipient at a round
    function rewardByRecipient(
        uint256 round,
        address groupOwner,
        address recipient
    ) external view returns (uint256) {
        (uint256 totalAmount, ) = rewardByAccount(round, groupOwner);
        if (totalAmount == 0) return 0;

        address[] memory addrs = _recipientsHistory[groupOwner].value(round);
        uint256[] memory basisPoints = _basisPointsHistory[groupOwner].value(
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

    // ============ IExtensionJoinedValue Implementation ============

    function isJoinedValueCalculated() external pure returns (bool) {
        return false;
    }

    function joinedValue() external view returns (uint256) {
        return ILOVE20ExtensionGroupAction(GROUP_ACTION_ADDRESS).totalStaked();
    }

    function joinedValueByAccount(
        address account
    ) external view returns (uint256) {
        if (!_accounts.contains(account)) return 0;
        return
            ILOVE20ExtensionGroupAction(GROUP_ACTION_ADDRESS)
                .totalStakedByOwner(account);
    }

    // ============ Internal Functions ============

    function _calculateReward(
        uint256 round,
        address account
    ) internal view override returns (uint256) {
        if (!_accounts.contains(account)) return 0;

        uint256 totalReward = _reward[round];
        if (totalReward == 0) return 0;

        uint256 groupActionReward = ILOVE20ExtensionGroupAction(
            GROUP_ACTION_ADDRESS
        ).rewardByGroupOwner(round, account);
        if (groupActionReward == 0) return 0;

        uint256 groupActionTotalReward = ILOVE20ExtensionGroupAction(
            GROUP_ACTION_ADDRESS
        ).reward(round);
        if (groupActionTotalReward == 0) return 0;

        return (totalReward * groupActionReward) / groupActionTotalReward;
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
            ILOVE20Token token = ILOVE20Token(tokenAddress);
            address[] memory addrs = _recipientsHistory[msg.sender].value(
                round
            );
            uint256[] memory basisPoints = _basisPointsHistory[msg.sender]
                .value(round);

            uint256 distributed;
            for (uint256 i = 0; i < addrs.length; i++) {
                uint256 recipientAmount = (amount * basisPoints[i]) /
                    BASIS_POINTS_BASE;
                if (recipientAmount > 0) {
                    token.transfer(addrs[i], recipientAmount);
                    distributed += recipientAmount;
                }
            }

            // Remaining to the original account
            uint256 remaining = amount - distributed;
            if (remaining > 0) {
                token.transfer(msg.sender, remaining);
            }
        }

        emit ClaimReward(tokenAddress, msg.sender, actionId, round, amount);
    }
}
