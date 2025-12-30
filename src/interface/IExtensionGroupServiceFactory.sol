// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    IExtensionFactory
} from "@extension/src/interface/IExtensionFactory.sol";

interface IExtensionGroupServiceFactory is IExtensionFactory {
    event ExtensionCreate(
        address indexed extension,
        address indexed tokenAddress
    );
}
