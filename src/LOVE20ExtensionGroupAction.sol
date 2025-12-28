// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    GroupTokenJoinManualScoreDistrustReward
} from "./base/GroupTokenJoinManualScoreDistrustReward.sol";
import {GroupTokenJoin} from "./base/GroupTokenJoin.sol";
import {GroupCore} from "./base/GroupCore.sol";
import {ILOVE20Extension} from "@extension/src/interface/ILOVE20Extension.sol";
import {IGroupTokenJoin} from "./interface/base/IGroupTokenJoin.sol";
import {
    IUniswapV2Pair
} from "@core/uniswap-v2-core/interfaces/IUniswapV2Pair.sol";

/// @title LOVE20ExtensionGroupAction
/// @notice Extension contract for manual scoring verification in group-based actions
contract LOVE20ExtensionGroupAction is
    GroupTokenJoinManualScoreDistrustReward,
    ILOVE20Extension
{
    // ============ Constructor ============

    constructor(
        address factory_,
        address tokenAddress_,
        address groupManagerAddress_,
        address groupDistrustAddress_,
        address stakeTokenAddress_,
        address joinTokenAddress_,
        uint256 activationStakeAmount_,
        uint256 maxJoinAmountRatio_,
        uint256 maxVerifyCapacityFactor_
    )
        GroupTokenJoinManualScoreDistrustReward(groupDistrustAddress_)
        GroupCore(
            factory_,
            tokenAddress_,
            groupManagerAddress_,
            stakeTokenAddress_,
            activationStakeAmount_
        )
        GroupTokenJoin(
            joinTokenAddress_,
            maxJoinAmountRatio_,
            maxVerifyCapacityFactor_
        )
    {
        _validateJoinToken(joinTokenAddress_, tokenAddress_);
    }

    /// @dev Validate joinToken: must be tokenAddress or LP containing tokenAddress
    function _validateJoinToken(
        address joinTokenAddress_,
        address tokenAddress_
    ) private view {
        if (joinTokenAddress_ == tokenAddress_) return;

        // Must be LP token containing tokenAddress
        try IUniswapV2Pair(joinTokenAddress_).token0() returns (address t0) {
            try IUniswapV2Pair(joinTokenAddress_).token1() returns (
                address t1
            ) {
                if (t0 != tokenAddress_ && t1 != tokenAddress_) {
                    revert IGroupTokenJoin.InvalidJoinTokenAddress();
                }
            } catch {
                revert IGroupTokenJoin.InvalidJoinTokenAddress();
            }
        } catch {
            revert IGroupTokenJoin.InvalidJoinTokenAddress();
        }
    }

    // ============ IExtensionJoinedValue Implementation ============

    function isJoinedValueCalculated() external view returns (bool) {
        return JOIN_TOKEN_ADDRESS != tokenAddress;
    }

    function joinedValue() external view returns (uint256) {
        return _convertToTokenValue(totalJoinedAmount());
    }

    function joinedValueByAccount(
        address account
    ) external view returns (uint256) {
        (, uint256 amount, ) = this.joinInfo(account);
        return _convertToTokenValue(amount);
    }

    // ============ Internal Functions ============

    /// @dev Convert joinToken amount to tokenAddress value
    function _convertToTokenValue(
        uint256 amount
    ) internal view returns (uint256) {
        if (amount == 0) return 0;
        if (JOIN_TOKEN_ADDRESS == tokenAddress) return amount;
        return _convertLPToTokenValue(amount);
    }

    /// @dev Convert LP token amount to tokenAddress value
    /// LP value = tokenAddress reserve * 2 / totalSupply (AMM ensures equal value on both sides)
    function _convertLPToTokenValue(
        uint256 lpAmount
    ) internal view returns (uint256) {
        IUniswapV2Pair pair = IUniswapV2Pair(JOIN_TOKEN_ADDRESS);
        uint256 totalSupply = pair.totalSupply();
        if (totalSupply == 0) return 0;

        (uint112 r0, uint112 r1, ) = pair.getReserves();
        uint256 tokenReserve = pair.token0() == tokenAddress
            ? uint256(r0)
            : uint256(r1);

        return (tokenReserve * lpAmount * 2) / totalSupply;
    }
}
