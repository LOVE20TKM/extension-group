// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    ExtensionFactoryBase
} from "@extension/src/ExtensionFactoryBase.sol";
import {ExtensionGroupService} from "./ExtensionGroupService.sol";
import {
    IExtensionGroupServiceFactory
} from "./interface/IExtensionGroupServiceFactory.sol";
import {
    IExtensionFactory
} from "@extension/src/interface/IExtensionFactory.sol";

/// @title ExtensionGroupServiceFactory
/// @notice Factory contract for creating ExtensionGroupService instances
contract ExtensionGroupServiceFactory is
    ExtensionFactoryBase,
    IExtensionGroupServiceFactory
{
    // ============ Storage ============

    /// @notice The group action factory address
    address public immutable GROUP_ACTION_FACTORY_ADDRESS;

    // ============ Constructor ============

    /// @param groupActionFactory_ The group action factory address
    constructor(
        address groupActionFactory_
    )
        ExtensionFactoryBase(
            IExtensionFactory(groupActionFactory_).center()
        )
    {
        GROUP_ACTION_FACTORY_ADDRESS = groupActionFactory_;
    }

    // ============ Factory Functions ============

    /// @notice Create a new ExtensionGroupService extension
    /// @param tokenAddress_ The service token address
    /// @param groupActionTokenAddress_ The group action token address
    /// @return extension The address of the created extension
    function createExtension(
        address tokenAddress_,
        address groupActionTokenAddress_
    ) external returns (address extension) {
        extension = address(
            new ExtensionGroupService(
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

