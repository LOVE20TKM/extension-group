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
    LOVE20ExtensionBaseJoin,
    ILOVE20ExtensionGroupService
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using RoundHistoryAddressArray for RoundHistoryAddressArray.History;
    using RoundHistoryUint256Array for RoundHistoryUint256Array.History;

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
    ) LOVE20ExtensionBaseJoin(factory_, tokenAddress_) {
        GROUP_ACTION_ADDRESS = groupActionAddress_;
        MAX_RECIPIENTS = maxRecipients_;
    }

    // ============ Write Functions ============

    /// @notice Join the service reward action
    function join(
        string[] memory verificationInfos
    ) public override(IJoin, JoinBase) {
        ILOVE20ExtensionGroupAction groupAction = ILOVE20ExtensionGroupAction(
            GROUP_ACTION_ADDRESS
        );
        uint256 stakedAmount = ILOVE20GroupManager(
            groupAction.GROUP_MANAGER_ADDRESS()
        ).totalStakedByOwner(
                groupAction.tokenAddress(),
                groupAction.actionId(),
                msg.sender
            );
        if (stakedAmount == 0) revert NoActiveGroups();

        super.join(verificationInfos);
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
        ILOVE20ExtensionGroupAction groupAction = ILOVE20ExtensionGroupAction(
            GROUP_ACTION_ADDRESS
        );
        return
            ILOVE20GroupManager(groupAction.GROUP_MANAGER_ADDRESS())
                .totalStaked(
                    groupAction.tokenAddress(),
                    groupAction.actionId()
                );
    }

    function joinedValueByAccount(
        address account
    ) external view returns (uint256) {
        if (!_accounts.contains(account)) return 0;
        ILOVE20ExtensionGroupAction groupAction = ILOVE20ExtensionGroupAction(
            GROUP_ACTION_ADDRESS
        );
        return
            ILOVE20GroupManager(groupAction.GROUP_MANAGER_ADDRESS())
                .totalStakedByOwner(
                    groupAction.tokenAddress(),
                    groupAction.actionId(),
                    account
                );
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
        ).rewardByVerifier(round, account);
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

        emit ClaimReward(tokenAddress, round, actionId, msg.sender, amount);
    }
}
