// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ExtensionCenter} from "@extension/src/ExtensionCenter.sol";

/// @title MockExtensionCenter
/// @notice Test-only ExtensionCenter
contract MockExtensionCenter is ExtensionCenter {
    constructor(
        address uniswapV2FactoryAddress_,
        address launchAddress_,
        address stakeAddress_,
        address submitAddress_,
        address voteAddress_,
        address joinAddress_,
        address verifyAddress_,
        address mintAddress_,
        address randomAddress_
    )
        ExtensionCenter(
            uniswapV2FactoryAddress_,
            launchAddress_,
            stakeAddress_,
            submitAddress_,
            voteAddress_,
            joinAddress_,
            verifyAddress_,
            mintAddress_,
            randomAddress_
        )
    {}
}
