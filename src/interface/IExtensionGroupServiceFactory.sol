// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupServiceFactory} from "./IGroupServiceFactory.sol";
import {
    IExtensionFactory
} from "@extension/src/interface/IExtensionFactory.sol";

interface IExtensionGroupServiceFactory is
    IGroupServiceFactory,
    IExtensionFactory
{}
