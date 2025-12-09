// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    GroupTokenJoinSnapshotManualScoreDistrustReward
} from "./base/GroupTokenJoinSnapshotManualScoreDistrustReward.sol";
import {GroupTokenJoin} from "./base/GroupTokenJoin.sol";
import {GroupCore} from "./base/GroupCore.sol";
import {ExtensionAccounts} from "@extension/src/base/ExtensionAccounts.sol";
import {ILOVE20Extension} from "@extension/src/interface/ILOVE20Extension.sol";
import {IGroupManualScore} from "./interface/base/IGroupManualScore.sol";

/// @title LOVE20ExtensionGroupAction
/// @notice Extension contract for manual scoring verification in group-based actions
/// @dev Uses tokenAddress as both joinToken and stakeToken
contract LOVE20ExtensionGroupAction is
    GroupTokenJoinSnapshotManualScoreDistrustReward,
    ExtensionAccounts,
    ILOVE20Extension,
    IGroupManualScore
{
    // ============ Constructor ============

    constructor(
        address factory_,
        address tokenAddress_,
        address groupManagerAddress_,
        address groupDistrustAddress_,
        address stakeTokenAddress_,
        uint256 minGovVoteRatioBps_,
        uint256 capacityMultiplier_,
        uint256 stakingMultiplier_,
        uint256 maxJoinAmountMultiplier_,
        uint256 minJoinAmount_
    )
        GroupTokenJoinSnapshotManualScoreDistrustReward(groupDistrustAddress_)
        GroupCore(
            factory_,
            tokenAddress_,
            groupManagerAddress_,
            stakeTokenAddress_,
            minGovVoteRatioBps_,
            capacityMultiplier_,
            stakingMultiplier_,
            maxJoinAmountMultiplier_,
            minJoinAmount_
        )
        GroupTokenJoin(tokenAddress_) // joinTokenAddress = tokenAddress
    {}

    // ============ Override: Account Management ============

    function _addAccount(
        address account
    ) internal override(ExtensionAccounts, GroupTokenJoin) {
        ExtensionAccounts._addAccount(account);
    }

    function _removeAccount(
        address account
    ) internal override(ExtensionAccounts, GroupTokenJoin) {
        ExtensionAccounts._removeAccount(account);
    }

    // ============ Override: Exit ============

    function exit() public override(GroupTokenJoin) {
        GroupTokenJoin.exit();
    }

    // ============ IExtensionJoinedValue Implementation ============

    function isJoinedValueCalculated() external pure returns (bool) {
        return false;
    }

    function joinedValue() external view returns (uint256) {
        return totalJoinedAmount();
    }

    function joinedValueByAccount(
        address account
    ) external view returns (uint256) {
        return _joinInfo[account].amount;
    }
}
