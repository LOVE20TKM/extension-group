// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    IUniswapV2Pair
} from "@core/uniswap-v2-core/interfaces/IUniswapV2Pair.sol";
import {
    IUniswapV2Factory
} from "@core/uniswap-v2-core/interfaces/IUniswapV2Factory.sol";

library TokenConversionLib {
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

    function convertLPToTokenValue(
        address lpToken,
        uint256 lpAmount,
        address targetToken
    ) internal view returns (uint256) {
        IUniswapV2Pair pair = IUniswapV2Pair(lpToken);
        uint256 totalSupply = pair.totalSupply();
        if (totalSupply == 0) return 0;

        (uint112 r0, uint112 r1, ) = pair.getReserves();

        uint256 tokenReserve = pair.token0() == targetToken
            ? uint256(r0)
            : uint256(r1);

        return (tokenReserve * lpAmount * 2) / totalSupply;
    }

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
