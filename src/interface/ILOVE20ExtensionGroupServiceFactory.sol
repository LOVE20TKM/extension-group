// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    IExtensionFactory
} from "@extension/src/interface/IExtensionFactory.sol";

/// @title ILOVE20ExtensionGroupServiceFactory
/// @notice Interface for LOVE20ExtensionGroupServiceFactory
interface ILOVE20ExtensionGroupServiceFactory is IExtensionFactory {
    // ============ Events ============

    event ExtensionCreate(
        address indexed extension,
        address indexed tokenAddress
    );
}
