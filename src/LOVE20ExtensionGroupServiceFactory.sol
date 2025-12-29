// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    LOVE20ExtensionFactoryBase
} from "@extension/src/LOVE20ExtensionFactoryBase.sol";
import {LOVE20ExtensionGroupService} from "./LOVE20ExtensionGroupService.sol";
import {
    ILOVE20ExtensionGroupServiceFactory
} from "./interface/ILOVE20ExtensionGroupServiceFactory.sol";
import {
    ILOVE20ExtensionFactory
} from "@extension/src/interface/ILOVE20ExtensionFactory.sol";

/// @title LOVE20ExtensionGroupServiceFactory
/// @notice Factory contract for creating LOVE20ExtensionGroupService instances
contract LOVE20ExtensionGroupServiceFactory is
    LOVE20ExtensionFactoryBase,
    ILOVE20ExtensionGroupServiceFactory
{
    // ============ Storage ============

    /// @notice The group action factory address
    address public immutable GROUP_ACTION_FACTORY_ADDRESS;

    // ============ Constructor ============

    /// @param groupActionFactory_ The group action factory address
    constructor(
        address groupActionFactory_
    )
        LOVE20ExtensionFactoryBase(
            ILOVE20ExtensionFactory(groupActionFactory_).center()
        )
    {
        GROUP_ACTION_FACTORY_ADDRESS = groupActionFactory_;
    }

    // ============ Factory Functions ============

    /// @notice Create a new LOVE20ExtensionGroupService extension
    /// @param tokenAddress_ The service token address
    /// @param groupActionTokenAddress_ The group action token address
    /// @return extension The address of the created extension
    function createExtension(
        address tokenAddress_,
        address groupActionTokenAddress_
    ) external returns (address extension) {
        extension = address(
            new LOVE20ExtensionGroupService(
                address(this),
                tokenAddress_,
                groupActionTokenAddress_,
                GROUP_ACTION_FACTORY_ADDRESS
            )
        );

        _registerExtension(extension, tokenAddress_);

        emit ExtensionCreate(extension, tokenAddress_);
    }
}
