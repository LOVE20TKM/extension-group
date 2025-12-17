// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    LOVE20ExtensionFactoryBase
} from "@extension/src/LOVE20ExtensionFactoryBase.sol";
import {LOVE20ExtensionGroupAction} from "./LOVE20ExtensionGroupAction.sol";

/// @title LOVE20ExtensionGroupActionFactory
/// @notice Factory contract for creating LOVE20ExtensionGroupAction instances
contract LOVE20ExtensionGroupActionFactory is LOVE20ExtensionFactoryBase {
    // ============ Structs ============

    struct ExtensionParams {
        address tokenAddress;
        address groupManagerAddress;
        address groupDistrustAddress;
        address stakeTokenAddress;
        uint256 activationStakeAmount;
        uint256 maxJoinAmountMultiplier;
    }

    // ============ Storage ============

    mapping(address => ExtensionParams) private _extensionParams;

    // ============ Constructor ============

    constructor(address center_) LOVE20ExtensionFactoryBase(center_) {}

    // ============ Factory Functions ============

    /// @notice Create a new LOVE20ExtensionGroupAction extension
    function createExtension(
        address tokenAddress_,
        address groupManagerAddress_,
        address groupDistrustAddress_,
        address stakeTokenAddress_,
        uint256 activationStakeAmount_,
        uint256 maxJoinAmountMultiplier_
    ) external returns (address extension) {
        extension = address(
            new LOVE20ExtensionGroupAction(
                address(this),
                tokenAddress_,
                groupManagerAddress_,
                groupDistrustAddress_,
                stakeTokenAddress_,
                activationStakeAmount_,
                maxJoinAmountMultiplier_
            )
        );

        _extensionParams[extension] = ExtensionParams({
            tokenAddress: tokenAddress_,
            groupManagerAddress: groupManagerAddress_,
            groupDistrustAddress: groupDistrustAddress_,
            stakeTokenAddress: stakeTokenAddress_,
            activationStakeAmount: activationStakeAmount_,
            maxJoinAmountMultiplier: maxJoinAmountMultiplier_
        });

        _registerExtension(extension, tokenAddress_);
    }

    // ============ View Functions ============

    /// @notice Get the parameters of an extension
    function extensionParams(
        address extension_
    ) external view returns (ExtensionParams memory) {
        return _extensionParams[extension_];
    }
}
