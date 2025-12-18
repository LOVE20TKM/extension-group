// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupTokenJoin} from "../interface/base/IGroupTokenJoin.sol";
import {GroupCore} from "./GroupCore.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {RoundHistoryUint256} from "@extension/src/lib/RoundHistoryUint256.sol";
import {RoundHistoryAddress} from "@extension/src/lib/RoundHistoryAddress.sol";
import {ILOVE20GroupManager} from "../interface/ILOVE20GroupManager.sol";
import {ILOVE20Group} from "@group/interfaces/ILOVE20Group.sol";

using RoundHistoryUint256 for RoundHistoryUint256.History;
using RoundHistoryAddress for RoundHistoryAddress.History;
using SafeERC20 for IERC20;

/// @title GroupTokenJoin
/// @notice Handles token-based group joining and exiting
abstract contract GroupTokenJoin is
    GroupCore,
    ReentrancyGuard,
    IGroupTokenJoin
{
    // ============ Immutables ============

    address public immutable JOIN_TOKEN_ADDRESS;
    IERC20 internal immutable _joinToken;

    // ============ Account State ============

    mapping(address => uint256) internal _joinedRoundByAccount;
    mapping(address => RoundHistoryUint256.History)
        internal _groupIdHistoryByAccount;
    mapping(address => RoundHistoryUint256.History)
        internal _amountHistoryByAccount;

    // ============ Group Members History ============

    mapping(uint256 => RoundHistoryUint256.History)
        internal _accountCountByGroupIdHistory;
    mapping(uint256 => mapping(uint256 => RoundHistoryAddress.History))
        internal _accountByGroupIdAndIndexHistory;
    mapping(uint256 => mapping(address => RoundHistoryUint256.History))
        internal _accountIndexInGroupHistory;

    // ============ Group Total Amount History ============

    mapping(uint256 => RoundHistoryUint256.History)
        internal _totalJoinedAmountHistoryByGroupId;
    RoundHistoryUint256.History internal _totalJoinedAmountHistory;

    // ============ Constructor ============

    constructor(address joinTokenAddress_) {
        if (joinTokenAddress_ == address(0)) revert InvalidJoinTokenAddress();
        JOIN_TOKEN_ADDRESS = joinTokenAddress_;
        _joinToken = IERC20(joinTokenAddress_);
    }

    // ============ Write Functions ============

    function join(
        uint256 groupId,
        uint256 amount,
        string[] memory verificationInfos
    ) public virtual nonReentrant {
        _autoInitialize();

        if (amount == 0) revert JoinAmountZero();

        uint256 joinedGroupId = _groupIdHistoryByAccount[msg.sender]
            .latestValue();
        bool isFirstJoin = joinedGroupId == 0;
        uint256 prevAmount = _amountHistoryByAccount[msg.sender].latestValue();
        uint256 newTotal = prevAmount + amount;

        _validateJoin(groupId, amount, isFirstJoin, joinedGroupId, newTotal);
        _validateOwnerCapacity(groupId, amount);

        // Transfer tokens
        _joinToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 currentRound = _join.currentRound();

        // Update totalJoinedAmount history
        _totalJoinedAmountHistoryByGroupId[groupId].record(
            currentRound,
            _totalJoinedAmountHistoryByGroupId[groupId].latestValue() + amount
        );
        _totalJoinedAmountHistory.record(
            currentRound,
            _totalJoinedAmountHistory.latestValue() + amount
        );

        // Update amount history for account
        _amountHistoryByAccount[msg.sender].record(currentRound, newTotal);

        if (isFirstJoin) {
            _joinedRoundByAccount[msg.sender] = currentRound;
            _groupIdHistoryByAccount[msg.sender].record(currentRound, groupId);
            _addAccountToGroup(currentRound, groupId, msg.sender);
            _center.addAccount(
                tokenAddress,
                actionId,
                msg.sender,
                verificationInfos
            );
        } else if (verificationInfos.length > 0) {
            _center.updateVerificationInfo(
                tokenAddress,
                actionId,
                msg.sender,
                verificationInfos
            );
        }

        emit Join(
            tokenAddress,
            currentRound,
            actionId,
            groupId,
            msg.sender,
            amount
        );
    }

    function _validateJoin(
        uint256 groupId,
        uint256 amount,
        bool isFirstJoin,
        uint256 joinedGroupId,
        uint256 newTotal
    ) internal view {
        (
            ,
            ,
            uint256 maxCapacity,
            uint256 minJoinAmount,
            uint256 maxJoinAmount,
            uint256 maxAccounts,
            bool isActive,
            ,

        ) = _groupManager.groupInfo(tokenAddress, actionId, groupId);

        if (!isFirstJoin && joinedGroupId != groupId)
            revert AlreadyInOtherGroup();
        if (!isActive) revert CannotJoinDeactivatedGroup();

        if (isFirstJoin) {
            if (
                maxAccounts > 0 &&
                _accountCountByGroupIdHistory[groupId].latestValue() >=
                maxAccounts
            ) revert GroupAccountsFull();

            if (amount < minJoinAmount) revert AmountBelowMinimum();
        }

        if (maxJoinAmount > 0 && newTotal > maxJoinAmount) {
            revert AmountExceedsAccountCap();
        }
        if (
            newTotal >
            _groupManager.calculateJoinMaxAmount(tokenAddress, actionId)
        ) revert AmountExceedsAccountCap();

        // Check group's max capacity (if set)
        if (maxCapacity > 0) {
            if (
                _totalJoinedAmountHistoryByGroupId[groupId].latestValue() +
                    amount >
                maxCapacity
            ) {
                revert GroupCapacityExceeded();
            }
        }
    }

    function _validateOwnerCapacity(
        uint256 groupId,
        uint256 amount
    ) internal view {
        address groupOwner = ILOVE20Group(GROUP_ADDRESS).ownerOf(groupId);
        uint256 ownerTotalJoined = _totalJoinedAmountByOwner(groupOwner);
        uint256 ownerMaxVerifyCapacity = _groupManager.maxVerifyCapacityByOwner(
            tokenAddress,
            actionId,
            groupOwner
        );
        if (ownerTotalJoined + amount > ownerMaxVerifyCapacity) {
            revert OwnerCapacityExceeded();
        }
    }

    function exit() public virtual nonReentrant {
        uint256 groupId = _groupIdHistoryByAccount[msg.sender].latestValue();
        if (groupId == 0) revert NotInGroup();

        uint256 amount = _amountHistoryByAccount[msg.sender].latestValue();
        uint256 currentRound = _join.currentRound();

        // Update state
        _groupIdHistoryByAccount[msg.sender].record(currentRound, 0);
        _amountHistoryByAccount[msg.sender].record(currentRound, 0);

        // Update totalJoinedAmount history
        _totalJoinedAmountHistoryByGroupId[groupId].record(
            currentRound,
            _totalJoinedAmountHistoryByGroupId[groupId].latestValue() - amount
        );
        _totalJoinedAmountHistory.record(
            currentRound,
            _totalJoinedAmountHistory.latestValue() - amount
        );

        _removeAccountFromGroup(currentRound, groupId, msg.sender);
        delete _joinedRoundByAccount[msg.sender];
        _center.removeAccount(tokenAddress, actionId, msg.sender);

        // Transfer tokens back
        _joinToken.safeTransfer(msg.sender, amount);

        emit Exit(
            tokenAddress,
            currentRound,
            actionId,
            groupId,
            msg.sender,
            amount
        );
    }

    // ============ View Functions ============

    function totalJoinedAmountByGroupId(
        uint256 groupId
    ) external view returns (uint256) {
        return _totalJoinedAmountHistoryByGroupId[groupId].latestValue();
    }

    function joinInfo(
        address account
    )
        external
        view
        returns (uint256 joinedRound, uint256 amount, uint256 groupId)
    {
        return (
            _joinedRoundByAccount[account],
            _amountHistoryByAccount[account].latestValue(),
            _groupIdHistoryByAccount[account].latestValue()
        );
    }

    function accountsByGroupIdCount(
        uint256 groupId
    ) external view returns (uint256) {
        return _accountCountByGroupIdHistory[groupId].latestValue();
    }

    function accountsByGroupIdAtIndex(
        uint256 groupId,
        uint256 index
    ) external view returns (address) {
        return _accountByGroupIdAndIndexHistory[groupId][index].latestValue();
    }

    function groupIdByAccountByRound(
        address account,
        uint256 round
    ) public view returns (uint256) {
        return _groupIdHistoryByAccount[account].value(round);
    }

    function totalJoinedAmountByGroupIdByRound(
        uint256 groupId,
        uint256 round
    ) public view returns (uint256) {
        return _totalJoinedAmountHistoryByGroupId[groupId].value(round);
    }

    function totalJoinedAmount() public view returns (uint256) {
        return _totalJoinedAmountHistory.latestValue();
    }

    function totalJoinedAmountByRound(
        uint256 round
    ) public view returns (uint256) {
        return _totalJoinedAmountHistory.value(round);
    }

    // ============ Round-based Query Functions ============

    function accountCountByGroupIdByRound(
        uint256 groupId,
        uint256 round
    ) public view returns (uint256) {
        return _accountCountByGroupIdHistory[groupId].value(round);
    }

    function accountByGroupIdAndIndexByRound(
        uint256 groupId,
        uint256 index,
        uint256 round
    ) public view returns (address) {
        return _accountByGroupIdAndIndexHistory[groupId][index].value(round);
    }

    function amountByAccountByRound(
        address account,
        uint256 round
    ) public view returns (uint256) {
        return _amountHistoryByAccount[account].value(round);
    }

    // ============ Internal Functions ============

    /// @dev Calculate total joined amount for all active groups owned by owner
    function _totalJoinedAmountByOwner(
        address owner
    ) internal view returns (uint256 total) {
        uint256[] memory ownerGroupIds = _groupManager.activeGroupIdsByOwner(
            tokenAddress,
            actionId,
            owner
        );
        for (uint256 i = 0; i < ownerGroupIds.length; i++) {
            total += _totalJoinedAmountHistoryByGroupId[ownerGroupIds[i]]
                .latestValue();
        }
    }

    function _addAccountToGroup(
        uint256 round,
        uint256 groupId,
        address account
    ) internal {
        uint256 accountCount = _accountCountByGroupIdHistory[groupId]
            .latestValue();

        _accountByGroupIdAndIndexHistory[groupId][accountCount].record(
            round,
            account
        );
        _accountIndexInGroupHistory[groupId][account].record(
            round,
            accountCount
        );
        _accountCountByGroupIdHistory[groupId].record(round, accountCount + 1);
    }

    function _removeAccountFromGroup(
        uint256 round,
        uint256 groupId,
        address account
    ) internal {
        uint256 index = _accountIndexInGroupHistory[groupId][account]
            .latestValue();
        uint256 lastIndex = _accountCountByGroupIdHistory[groupId]
            .latestValue() - 1;

        // Swap and pop
        if (index != lastIndex) {
            address lastAccount = _accountByGroupIdAndIndexHistory[groupId][
                lastIndex
            ].latestValue();
            _accountByGroupIdAndIndexHistory[groupId][index].record(
                round,
                lastAccount
            );
            _accountIndexInGroupHistory[groupId][lastAccount].record(
                round,
                index
            );
        }
        _accountCountByGroupIdHistory[groupId].record(round, lastIndex);
    }
}
