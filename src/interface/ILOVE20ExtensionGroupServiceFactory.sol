// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ILOVE20ExtensionFactory} from "@extension/src/interface/ILOVE20ExtensionFactory.sol";

/// @title ILOVE20ExtensionGroupServiceFactory
/// @notice Interface for LOVE20ExtensionGroupServiceFactory
interface ILOVE20ExtensionGroupServiceFactory is ILOVE20ExtensionFactory {
    // ============ Structs ============

    struct ExtensionParams {
        address tokenAddress;
        address groupActionTokenAddress;
        address groupActionFactoryAddress;
        uint256 maxRecipients;
    }

    // ============ Events ============

    event ExtensionCreate(
        address indexed extension,
        address indexed tokenAddress,
        address groupActionTokenAddress,
        address groupActionFactoryAddress,
        uint256 maxRecipients
    );

    // ============ View Functions ============

    /// @notice Get the parameters of an extension
    /// @param extension_ The extension address
    /// @return tokenAddress The token address
    /// @return groupActionTokenAddress The group action token address
    /// @return groupActionFactoryAddress The group action factory address
    /// @return maxRecipients Maximum number of recipients
    function extensionParams(
        address extension_
    )
        external
        view
        returns (
            address tokenAddress,
            address groupActionTokenAddress,
            address groupActionFactoryAddress,
            uint256 maxRecipients
        );
}

