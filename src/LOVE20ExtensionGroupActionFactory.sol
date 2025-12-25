// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    LOVE20ExtensionFactoryBase
} from "@extension/src/LOVE20ExtensionFactoryBase.sol";
import {LOVE20ExtensionGroupAction} from "./LOVE20ExtensionGroupAction.sol";
import {
    ILOVE20ExtensionGroupActionFactory
} from "./interface/ILOVE20ExtensionGroupActionFactory.sol";

/// @title LOVE20ExtensionGroupActionFactory
/// @notice Factory contract for creating LOVE20ExtensionGroupAction instances
contract LOVE20ExtensionGroupActionFactory is
    LOVE20ExtensionFactoryBase,
    ILOVE20ExtensionGroupActionFactory
{
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
        address joinTokenAddress_,
        uint256 activationStakeAmount_,
        uint256 maxJoinAmountMultiplier_,
        uint256 verifyCapacityMultiplier_
    ) external returns (address extension) {
        extension = address(
            new LOVE20ExtensionGroupAction(
                address(this),
                tokenAddress_,
                groupManagerAddress_,
                groupDistrustAddress_,
                stakeTokenAddress_,
                joinTokenAddress_,
                activationStakeAmount_,
                maxJoinAmountMultiplier_,
                verifyCapacityMultiplier_
            )
        );

        _extensionParams[extension] = ExtensionParams({
            tokenAddress: tokenAddress_,
            groupManagerAddress: groupManagerAddress_,
            groupDistrustAddress: groupDistrustAddress_,
            stakeTokenAddress: stakeTokenAddress_,
            joinTokenAddress: joinTokenAddress_,
            activationStakeAmount: activationStakeAmount_,
            maxJoinAmountMultiplier: maxJoinAmountMultiplier_,
            verifyCapacityMultiplier: verifyCapacityMultiplier_
        });

        _registerExtension(extension, tokenAddress_);

        emit ExtensionCreate({
            extension: extension,
            tokenAddress: tokenAddress_,
            groupManagerAddress: groupManagerAddress_,
            groupDistrustAddress: groupDistrustAddress_,
            stakeTokenAddress: stakeTokenAddress_,
            joinTokenAddress: joinTokenAddress_,
            activationStakeAmount: activationStakeAmount_,
            maxJoinAmountMultiplier: maxJoinAmountMultiplier_,
            verifyCapacityMultiplier: verifyCapacityMultiplier_
        });
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
            address groupManagerAddress,
            address groupDistrustAddress,
            address stakeTokenAddress,
            address joinTokenAddress,
            uint256 activationStakeAmount,
            uint256 maxJoinAmountMultiplier,
            uint256 verifyCapacityMultiplier
        )
    {
        ExtensionParams memory params = _extensionParams[extension_];
        return (
            params.tokenAddress,
            params.groupManagerAddress,
            params.groupDistrustAddress,
            params.stakeTokenAddress,
            params.joinTokenAddress,
            params.activationStakeAmount,
            params.maxJoinAmountMultiplier,
            params.verifyCapacityMultiplier
        );
    }
}
