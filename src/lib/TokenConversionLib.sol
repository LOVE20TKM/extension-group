// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    IUniswapV2Pair
} from "@core/uniswap-v2-core/interfaces/IUniswapV2Pair.sol";
import {
    IUniswapV2Factory
} from "@core/uniswap-v2-core/interfaces/IUniswapV2Factory.sol";

/// @title TokenConversionLib
/// @notice Library for converting between different token types and LP tokens
library TokenConversionLib {
    /// @dev Check if token is a Uniswap V2 LP token containing targetToken
    /// @param token The token address to check
    /// @param targetToken The target token address to check for
    /// @return True if token is an LP token containing targetToken
    function isLPTokenContainingTarget(
        address token,
        address targetToken
    ) internal view returns (bool) {
        try IUniswapV2Pair(token).token0() returns (address t0) {
            try IUniswapV2Pair(token).token1() returns (address t1) {
                return t0 == targetToken || t1 == targetToken;
            } catch {
                return false;
            }
        } catch {
            return false;
        }
    }

    /// @dev Convert LP token amount to targetToken value
    /// @notice LP must contain targetToken; both sides have equal value in AMM
    /// @param lpToken The LP token address
    /// @param lpAmount The amount of LP tokens
    /// @param targetToken The target token address (must be one of the LP pair tokens)
    /// @return The equivalent value in targetToken
    function convertLPToTokenValue(
        address lpToken,
        uint256 lpAmount,
        address targetToken
    ) internal view returns (uint256) {
        IUniswapV2Pair pair = IUniswapV2Pair(lpToken);
        uint256 totalSupply = pair.totalSupply();
        if (totalSupply == 0) return 0;

        (uint112 r0, uint112 r1, ) = pair.getReserves();

        // Get targetToken reserve (LP must contain targetToken)
        uint256 tokenReserve = pair.token0() == targetToken
            ? uint256(r0)
            : uint256(r1);

        // LP value = targetToken side * 2 (AMM ensures equal value on both sides)
        return (tokenReserve * lpAmount * 2) / totalSupply;
    }

    /// @dev Convert amount via Uniswap pair, returns 0 if no pair or no liquidity
    /// @param factoryAddress The Uniswap V2 Factory address
    /// @param fromToken The source token address
    /// @param toToken The target token address
    /// @param amount The amount to convert
    /// @return The equivalent value in toToken
    function convertViaUniswap(
        address factoryAddress,
        address fromToken,
        address toToken,
        uint256 amount
    ) internal view returns (uint256) {
        if (amount == 0) return 0;

        address pairAddr = IUniswapV2Factory(factoryAddress).getPair(
            fromToken,
            toToken
        );
        if (pairAddr == address(0)) return 0;

        IUniswapV2Pair pair = IUniswapV2Pair(pairAddr);
        (uint112 r0, uint112 r1, ) = pair.getReserves();
        if (r0 == 0 || r1 == 0) return 0;

        (uint256 toR, uint256 fromR) = pair.token0() == fromToken
            ? (uint256(r1), uint256(r0))
            : (uint256(r0), uint256(r1));
        return (amount * toR) / fromR;
    }
}
