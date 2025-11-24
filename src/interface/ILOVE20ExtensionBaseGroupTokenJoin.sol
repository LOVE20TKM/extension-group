// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ILOVE20ExtensionBaseGroup} from "./ILOVE20ExtensionBaseGroup.sol";
import {IGroupTokenJoin} from "./base/IGroupTokenJoin.sol";

/// @title ILOVE20ExtensionBaseGroupTokenJoin
/// @notice Interface for token join group extensions
interface ILOVE20ExtensionBaseGroupTokenJoin is
    ILOVE20ExtensionBaseGroup,
    IGroupTokenJoin
{
    // No additional functions needed
    // exit() is inherited from ILOVE20Extension -> IExtensionExit
    // Group token join functions are inherited from IGroupTokenJoin
}
