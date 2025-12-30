// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    IExtensionFactory
} from "@extension/src/interface/IExtensionFactory.sol";

/// @title IExtensionGroupServiceFactory
/// @notice Interface for ExtensionGroupServiceFactory
interface IExtensionGroupServiceFactory is IExtensionFactory {
    // ============ Events ============

    event ExtensionCreate(
        address indexed extension,
        address indexed tokenAddress
    );
}

