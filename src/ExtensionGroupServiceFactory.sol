// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    IExtensionGroupServiceFactory
} from "./interface/IExtensionGroupServiceFactory.sol";
import {ExtensionGroupService} from "./ExtensionGroupService.sol";
import {ExtensionFactoryBase} from "@extension/src/ExtensionFactoryBase.sol";

interface IExtensionFactoryOnlyCenterAddress {
    function CENTER_ADDRESS() external view returns (address);
}

contract ExtensionGroupServiceFactory is
    ExtensionFactoryBase,
    IExtensionGroupServiceFactory
{
    address public immutable GROUP_ACTION_FACTORY_ADDRESS;

    constructor(
        address groupActionFactory_
    )
        ExtensionFactoryBase(
            IExtensionFactoryOnlyCenterAddress(groupActionFactory_)
                .CENTER_ADDRESS()
        )
    {
        GROUP_ACTION_FACTORY_ADDRESS = groupActionFactory_;
    }

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
    }
}
