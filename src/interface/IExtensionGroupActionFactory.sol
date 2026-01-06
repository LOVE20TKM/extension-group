// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupActionFactory} from "./IGroupActionFactory.sol";
import {
    IExtensionFactory
} from "@extension/src/interface/IExtensionFactory.sol";

interface IExtensionGroupActionFactory is
    IGroupActionFactory,
    IExtensionFactory
{}
