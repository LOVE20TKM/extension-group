// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    GroupTokenJoinManualScoreDistrustReward
} from "./base/GroupTokenJoinManualScoreDistrustReward.sol";
import {GroupTokenJoin} from "./base/GroupTokenJoin.sol";
import {GroupCore} from "./base/GroupCore.sol";
import {ILOVE20Extension} from "@extension/src/interface/ILOVE20Extension.sol";
import {IGroupManualScore} from "./interface/base/IGroupManualScore.sol";

/// @title LOVE20ExtensionGroupAction
/// @notice Extension contract for manual scoring verification in group-based actions
/// @dev Uses tokenAddress as both joinToken and stakeToken
contract LOVE20ExtensionGroupAction is
    GroupTokenJoinManualScoreDistrustReward,
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
        uint256 activationStakeAmount_,
        uint256 maxJoinAmountMultiplier_,
        uint256 capacityFactor_
    )
        GroupTokenJoinManualScoreDistrustReward(groupDistrustAddress_)
        GroupCore(
            factory_,
            tokenAddress_,
            groupManagerAddress_,
            stakeTokenAddress_,
            activationStakeAmount_,
            maxJoinAmountMultiplier_,
            capacityFactor_
        )
        GroupTokenJoin(tokenAddress_) // joinTokenAddress = tokenAddress
    {}

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
        (, uint256 amount, ) = this.joinInfo(account);
        return amount;
    }
}
