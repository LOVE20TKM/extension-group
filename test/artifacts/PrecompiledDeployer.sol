// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Test} from "forge-std/Test.sol";
import {PrecompiledBytecodes} from "./PrecompiledBytecodes.sol";

/// @title PrecompiledDeployer
/// @notice Helper to deploy precompiled contracts (WETH, UniswapV2Factory) from bytecode
abstract contract PrecompiledDeployer is Test {
    /// @notice Deploy ETH20 (WETH) contract
    /// @param name Token name
    /// @param symbol Token symbol
    /// @return weth Deployed WETH address
    function deployETH20(
        string memory name,
        string memory symbol
    ) internal returns (address weth) {
        bytes memory bytecode = PrecompiledBytecodes.getETH20Bytecode();
        bytes memory initCode = abi.encodePacked(
            bytecode,
            abi.encode(name, symbol)
        );
        assembly {
            weth := create(0, add(initCode, 0x20), mload(initCode))
        }
        require(weth != address(0), "ETH20 deployment failed");
    }

    /// @notice Deploy UniswapV2Factory contract
    /// @param feeToSetter Address of fee setter
    /// @return factory Deployed factory address
    function deployUniswapV2Factory(
        address feeToSetter
    ) internal returns (address factory) {
        bytes memory bytecode = PrecompiledBytecodes
            .getUniswapV2FactoryBytecode();
        bytes memory initCode = abi.encodePacked(
            bytecode,
            abi.encode(feeToSetter)
        );
        assembly {
            factory := create(0, add(initCode, 0x20), mload(initCode))
        }
        require(factory != address(0), "UniswapV2Factory deployment failed");
    }
}
