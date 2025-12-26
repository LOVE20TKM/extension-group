// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    ILOVE20ExtensionFactory
} from "@extension/src/interface/ILOVE20ExtensionFactory.sol";

/// @title ILOVE20ExtensionGroupServiceFactory
/// @notice Interface for LOVE20ExtensionGroupServiceFactory
interface ILOVE20ExtensionGroupServiceFactory is ILOVE20ExtensionFactory {
    // ============ Events ============

    event ExtensionCreate(
        address indexed extension,
        address indexed tokenAddress
    );
}
