// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {LOVE20ExtensionBaseGroup} from "./LOVE20ExtensionBaseGroup.sol";
import {GroupTokenJoin} from "./base/GroupTokenJoin.sol";
import {IExtensionExit} from "@extension/src/interface/base/IExtensionExit.sol";
import {IGroupTokenJoin} from "./interface/base/IGroupTokenJoin.sol";
import {IGroupManager} from "./interface/base/IGroupManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ExtensionAccounts} from "@extension/src/base/ExtensionAccounts.sol";

/// @title LOVE20ExtensionBaseGroupTokenJoin
/// @notice Abstract base contract for token join group extensions
/// @dev Combines group management with token-based actor participation
abstract contract LOVE20ExtensionBaseGroupTokenJoin is
    LOVE20ExtensionBaseGroup,
    GroupTokenJoin
{
    // ============================================
    // CONSTRUCTOR
    // ============================================

    /// @notice Initialize the token join group extension
    /// @param factory_ The factory contract address
    /// @param groupNFT_ The LOVE20Group NFT contract address
    /// @param joinTokenAddress_ The token used for joining groups
    /// @param minGovernanceVoteRatio_ Minimum governance vote ratio
    /// @param capacityMultiplier_ Capacity multiplier
    /// @param stakingMultiplier_ Staking multiplier
    /// @param maxJoinAmountMultiplier_ Max actor amount multiplier
    constructor(
        address factory_,
        address groupNFT_,
        address joinTokenAddress_,
        uint256 minGovernanceVoteRatio_,
        uint256 capacityMultiplier_,
        uint256 stakingMultiplier_,
        uint256 maxJoinAmountMultiplier_
    )
        LOVE20ExtensionBaseGroup(
            factory_,
            groupNFT_,
            minGovernanceVoteRatio_,
            capacityMultiplier_,
            stakingMultiplier_,
            maxJoinAmountMultiplier_
        )
        GroupTokenJoin(joinTokenAddress_)
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
    // OVERRIDE: GROUP MANAGER METHODS
    // ============================================

    /// @inheritdoc GroupTokenJoin
    function _getGroupManager() internal view override returns (IGroupManager) {
        return IGroupManager(address(this));
    }

    /// @inheritdoc GroupTokenJoin
    function _getGroupInfo(
        uint256 groupId
    ) internal view override returns (IGroupManager.GroupInfo memory) {
        return _groups[groupId];
    }

    /// @inheritdoc GroupTokenJoin
    function _updateGrouptotalJoinedAmount(
        uint256 groupId,
        uint256 newTotal
    ) internal override {
        _groups[groupId].totalJoinedAmount = newTotal;
    }

    /// @inheritdoc GroupTokenJoin
    function _getCurrentRound()
        internal
        view
        override(LOVE20ExtensionBaseGroup, GroupTokenJoin)
        returns (uint256)
    {
        return LOVE20ExtensionBaseGroup._getCurrentRound();
    }

    // ============================================
    // IMPLEMENTATION: IEXTENSIONJOINEDVALUE
    // ============================================

    /// @notice Get total joined value across all groups
    function joinedValue() public view override returns (uint256) {
        uint256 total = 0;
        uint256[] memory groupIds = this.getAllStartedGroupIds();
        for (uint256 i = 0; i < groupIds.length; i++) {
            total += _groups[groupIds[i]].totalJoinedAmount;
        }
        return total;
    }

    /// @notice Get joined value for a specific account
    function joinedValueByAccount(
        address account
    ) public view override returns (uint256) {
        return _joinInfo[account].amount;
    }

    /// @notice Check if joined value is calculated
    function isJoinedValueCalculated() public pure override returns (bool) {
        return true;
    }

    // ============================================
    // IMPLEMENTATION: IEXTENSIONEXIT
    // ============================================

    /// @inheritdoc IExtensionExit
    function exit() public override {
        uint256 groupId = _joinInfo[msg.sender].groupId;
        if (groupId == 0) revert IGroupTokenJoin.NotInGroup();
        exitGroup(groupId);
    }
}
