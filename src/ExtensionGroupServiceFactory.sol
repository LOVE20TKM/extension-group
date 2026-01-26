// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    IExtensionGroupServiceFactory
} from "./interface/IExtensionGroupServiceFactory.sol";
import {ExtensionGroupService} from "./ExtensionGroupService.sol";
import {ExtensionFactoryBase} from "@extension/src/ExtensionFactoryBase.sol";
import {
    IExtensionFactory
} from "@extension/src/interface/IExtensionFactory.sol";
import {IExtensionCenter} from "@extension/src/interface/IExtensionCenter.sol";
import {ILOVE20Launch} from "@core/interfaces/ILOVE20Launch.sol";
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";
import {IGroupServiceFactoryErrors} from "./interface/IGroupServiceFactory.sol";

contract ExtensionGroupServiceFactory is
    ExtensionFactoryBase,
    IExtensionGroupServiceFactory
{
    address public immutable GROUP_ACTION_FACTORY_ADDRESS;

    constructor(
        address groupActionFactory_
    )
        ExtensionFactoryBase(
            IExtensionFactory(groupActionFactory_).CENTER_ADDRESS()
        )
    {
        GROUP_ACTION_FACTORY_ADDRESS = groupActionFactory_;
    }

    function createExtension(
        address tokenAddress_,
        address groupActionTokenAddress_
    ) external returns (address extension) {
        _validateGroupActionTokenAddress(
            tokenAddress_,
            groupActionTokenAddress_
        );

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

    function _validateGroupActionTokenAddress(
        address tokenAddress_,
        address groupActionTokenAddress_
    ) internal view {
        if (groupActionTokenAddress_ == tokenAddress_) return;

        IExtensionCenter center = IExtensionCenter(CENTER_ADDRESS);
        ILOVE20Launch launch = ILOVE20Launch(center.launchAddress());

        if (
            !launch.isLOVE20Token(groupActionTokenAddress_) ||
            ILOVE20Token(groupActionTokenAddress_).parentTokenAddress() !=
            tokenAddress_
        ) {
            revert IGroupServiceFactoryErrors.InvalidGroupActionTokenAddress();
        }
    }
}
