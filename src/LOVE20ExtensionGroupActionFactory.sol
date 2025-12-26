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

    /// @notice The group manager address configured in the factory
    address public immutable GROUP_MANAGER_ADDRESS;

    /// @notice The group distrust address configured in the factory
    address public immutable GROUP_DISTRUST_ADDRESS;

    mapping(address => ExtensionParams) private _extensionParams;

    // ============ Constructor ============

    /// @param center_ The extension center address
    /// @param groupManagerAddress_ The group manager address
    /// @param groupDistrustAddress_ The group distrust address
    constructor(
        address center_,
        address groupManagerAddress_,
        address groupDistrustAddress_
    ) LOVE20ExtensionFactoryBase(center_) {
        GROUP_MANAGER_ADDRESS = groupManagerAddress_;
        GROUP_DISTRUST_ADDRESS = groupDistrustAddress_;
    }

    // ============ Factory Functions ============

    /// @notice Create a new LOVE20ExtensionGroupAction extension
    /// @param tokenAddress_ The token address
    /// @param stakeTokenAddress_ The stake token address
    /// @param joinTokenAddress_ The join token address
    /// @param activationStakeAmount_ The activation stake amount
    /// @param maxJoinAmountMultiplier_ The max join amount multiplier
    /// @param verifyCapacityMultiplier_ The verify capacity multiplier
    /// @return extension The address of the created extension
    function createExtension(
        address tokenAddress_,
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
                GROUP_MANAGER_ADDRESS,
                GROUP_DISTRUST_ADDRESS,
                stakeTokenAddress_,
                joinTokenAddress_,
                activationStakeAmount_,
                maxJoinAmountMultiplier_,
                verifyCapacityMultiplier_
            )
        );

        _extensionParams[extension] = ExtensionParams({
            tokenAddress: tokenAddress_,
            groupManagerAddress: GROUP_MANAGER_ADDRESS,
            groupDistrustAddress: GROUP_DISTRUST_ADDRESS,
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
            groupManagerAddress: GROUP_MANAGER_ADDRESS,
            groupDistrustAddress: GROUP_DISTRUST_ADDRESS,
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
