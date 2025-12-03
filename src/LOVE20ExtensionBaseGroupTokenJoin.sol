// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {GroupTokenJoin} from "./base/GroupTokenJoin.sol";
import {GroupManager} from "./base/GroupManager.sol";
import {IExtensionExit} from "@extension/src/interface/base/IExtensionExit.sol";
import {ExtensionAccounts} from "@extension/src/base/ExtensionAccounts.sol";
import {
    ExtensionVerificationInfo
} from "@extension/src/base/ExtensionVerificationInfo.sol";
import {ILOVE20Extension} from "@extension/src/interface/ILOVE20Extension.sol";

/// @title LOVE20ExtensionBaseGroupTokenJoin
/// @notice Abstract base contract for token join group extensions
/// @dev Combines group management with token-based actor participation
abstract contract LOVE20ExtensionBaseGroupTokenJoin is
    GroupTokenJoin,
    ExtensionAccounts,
    ExtensionVerificationInfo,
    ILOVE20Extension
{
    // ============================================
    // CONSTRUCTOR
    // ============================================

    /// @notice Initialize the token join group extension
    /// @param factory_ The factory contract address
    /// @param tokenAddress_ The token address
    /// @param groupAddress_ The LOVE20Group NFT contract address
    /// @param stakeTokenAddress_ The token used for staking by group owners
    /// @param joinTokenAddress_ The token used for joining groups
    /// @param minGovernanceVoteRatio_ Minimum governance vote ratio
    /// @param capacityMultiplier_ Capacity multiplier
    /// @param stakingMultiplier_ Staking multiplier
    /// @param maxJoinAmountMultiplier_ Max join amount multiplier
    /// @param minJoinAmount_ Minimum join amount
    constructor(
        address factory_,
        address tokenAddress_,
        address groupAddress_,
        address stakeTokenAddress_,
        address joinTokenAddress_,
        uint256 minGovernanceVoteRatio_,
        uint256 capacityMultiplier_,
        uint256 stakingMultiplier_,
        uint256 maxJoinAmountMultiplier_,
        uint256 minJoinAmount_
    )
        GroupTokenJoin(joinTokenAddress_)
        GroupManager(
            factory_,
            tokenAddress_,
            groupAddress_,
            stakeTokenAddress_,
            minGovernanceVoteRatio_,
            capacityMultiplier_,
            stakingMultiplier_,
            maxJoinAmountMultiplier_,
            minJoinAmount_
        )
    {}

    // ============================================
    // OVERRIDE: ACCOUNT MANAGEMENT
    // ============================================

    /// @inheritdoc GroupTokenJoin
    function _addAccount(
        address account
    ) internal override(ExtensionAccounts, GroupTokenJoin) {
        ExtensionAccounts._addAccount(account);
    }

    /// @inheritdoc GroupTokenJoin
    function _removeAccount(
        address account
    ) internal override(ExtensionAccounts, GroupTokenJoin) {
        ExtensionAccounts._removeAccount(account);
    }

    // ============================================
    // IMPLEMENTATION: IEXTENSIONEXIT
    // ============================================

    /// @dev Override exit to satisfy IExtensionExit and GroupTokenJoin
    function exit() public override(GroupTokenJoin, IExtensionExit) {
        GroupTokenJoin.exit();
    }
}
