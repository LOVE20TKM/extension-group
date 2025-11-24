// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ExtensionCore} from "@extension/src/base/ExtensionCore.sol";
import {ExtensionAccounts} from "@extension/src/base/ExtensionAccounts.sol";
import {
    ExtensionVerificationInfo
} from "@extension/src/base/ExtensionVerificationInfo.sol";
import {GroupManager} from "./base/GroupManager.sol";
import {ILOVE20Extension} from "@extension/src/interface/ILOVE20Extension.sol";
import {ILOVE20Stake} from "@core/interfaces/ILOVE20Stake.sol";

/// @title LOVE20ExtensionBaseGroup
/// @notice Abstract base contract for group-based LOVE20 extensions
/// @dev Minimal base class with group management only
/// @dev Layer 1: Base - Only group lifecycle management, no actor participation
abstract contract LOVE20ExtensionBaseGroup is
    ExtensionCore,
    ExtensionAccounts,
    ExtensionVerificationInfo,
    GroupManager,
    ILOVE20Extension
{
    // ============================================
    // CONSTRUCTOR
    // ============================================

    /// @notice Initialize the group extension
    /// @param factory_ The factory contract address
    /// @param groupNFT_ The LOVE20Group NFT contract address
    /// @param minGovernanceVoteRatio_ Minimum governance vote ratio
    /// @param capacityMultiplier_ Capacity multiplier
    /// @param stakingMultiplier_ Staking multiplier
    /// @param maxJoinAmountMultiplier_ Max actor amount multiplier
    constructor(
        address factory_,
        address groupNFT_,
        uint256 minGovernanceVoteRatio_,
        uint256 capacityMultiplier_,
        uint256 stakingMultiplier_,
        uint256 maxJoinAmountMultiplier_
    )
        GroupManager(
            factory_,
            groupNFT_,
            minGovernanceVoteRatio_,
            capacityMultiplier_,
            stakingMultiplier_,
            maxJoinAmountMultiplier_
        )
    {}

    // ============================================
    // OVERRIDE: GET CURRENT ROUND
    // ============================================

    /// @inheritdoc GroupManager
    function _getCurrentRound()
        internal
        view
        virtual
        override
        returns (uint256)
    {
        return _join.currentRound();
    }

    // ============================================
    // ABSTRACT METHODS - TO BE IMPLEMENTED BY SUBCLASSES
    // ============================================

    // IExtensionJoinedValue methods (joinedValue, joinedValueByAccount, isJoinedValueCalculated)
    // are inherited from ILOVE20Extension and must be implemented by subclasses
}
