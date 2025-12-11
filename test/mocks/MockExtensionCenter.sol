// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {LOVE20ExtensionCenter} from "@extension/src/LOVE20ExtensionCenter.sol";

/// @title MockExtensionCenter
/// @notice Test-only ExtensionCenter
contract MockExtensionCenter is LOVE20ExtensionCenter {
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
        LOVE20ExtensionCenter(
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
