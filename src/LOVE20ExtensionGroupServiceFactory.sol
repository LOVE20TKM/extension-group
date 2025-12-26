// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    LOVE20ExtensionFactoryBase
} from "@extension/src/LOVE20ExtensionFactoryBase.sol";
import {LOVE20ExtensionGroupService} from "./LOVE20ExtensionGroupService.sol";
import {
    ILOVE20ExtensionGroupServiceFactory
} from "./interface/ILOVE20ExtensionGroupServiceFactory.sol";

/// @title LOVE20ExtensionGroupServiceFactory
/// @notice Factory contract for creating LOVE20ExtensionGroupService instances
contract LOVE20ExtensionGroupServiceFactory is
    LOVE20ExtensionFactoryBase,
    ILOVE20ExtensionGroupServiceFactory
{
    // ============ Constructor ============

    constructor(address center_) LOVE20ExtensionFactoryBase(center_) {}

    // ============ Factory Functions ============

    /// @notice Create a new LOVE20ExtensionGroupService extension
    /// @param tokenAddress_ The service token address
    /// @param groupActionTokenAddress_ The group action token address
    /// @param groupActionFactoryAddress_ The GroupAction factory address
    /// @param maxRecipients_ Maximum number of reward recipients
    /// @return extension The address of the created extension
    function createExtension(
        address tokenAddress_,
        address groupActionTokenAddress_,
        address groupActionFactoryAddress_,
        uint256 maxRecipients_
    ) external returns (address extension) {
        extension = address(
            new LOVE20ExtensionGroupService(
                address(this),
                tokenAddress_,
                groupActionTokenAddress_,
                groupActionFactoryAddress_,
                maxRecipients_
            )
        );

        _registerExtension(extension, tokenAddress_);

        emit ExtensionCreate(extension, tokenAddress_);
    }
}
