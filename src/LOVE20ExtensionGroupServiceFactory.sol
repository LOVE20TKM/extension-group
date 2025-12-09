// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    LOVE20ExtensionFactoryBase
} from "@extension/src/LOVE20ExtensionFactoryBase.sol";
import {LOVE20ExtensionGroupService} from "./LOVE20ExtensionGroupService.sol";

/// @title LOVE20ExtensionGroupServiceFactory
/// @notice Factory contract for creating LOVE20ExtensionGroupService instances
contract LOVE20ExtensionGroupServiceFactory is LOVE20ExtensionFactoryBase {
    // ============ Structs ============

    struct ExtensionParams {
        address tokenAddress;
        address groupActionAddress;
        uint256 maxRecipients;
    }

    // ============ Storage ============

    mapping(address => ExtensionParams) private _extensionParams;

    // ============ Constructor ============

    constructor(address center_) LOVE20ExtensionFactoryBase(center_) {}

    // ============ Factory Functions ============

    /// @notice Create a new LOVE20ExtensionGroupService extension
    /// @param tokenAddress_ The token address
    /// @param groupActionAddress_ The GroupAction extension address
    /// @param maxRecipients_ Maximum number of reward recipients
    /// @return extension The address of the created extension
    function createExtension(
        address tokenAddress_,
        address groupActionAddress_,
        uint256 maxRecipients_
    ) external returns (address extension) {
        extension = address(
            new LOVE20ExtensionGroupService(
                address(this),
                tokenAddress_,
                groupActionAddress_,
                maxRecipients_
            )
        );

        _extensionParams[extension] = ExtensionParams({
            tokenAddress: tokenAddress_,
            groupActionAddress: groupActionAddress_,
            maxRecipients: maxRecipients_
        });

        _registerExtension(extension, tokenAddress_);
    }

    // ============ View Functions ============

    /// @notice Get the parameters of an extension
    function extensionParams(
        address extension_
    )
        external
        view
        returns (
            address tokenAddress,
            address groupActionAddress,
            uint256 maxRecipients
        )
    {
        ExtensionParams memory params = _extensionParams[extension_];
        return (
            params.tokenAddress,
            params.groupActionAddress,
            params.maxRecipients
        );
    }
}

