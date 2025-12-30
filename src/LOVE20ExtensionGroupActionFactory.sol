// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    ExtensionFactoryBase
} from "@extension/src/ExtensionFactoryBase.sol";
import {LOVE20ExtensionGroupAction} from "./LOVE20ExtensionGroupAction.sol";
import {
    ILOVE20ExtensionGroupActionFactory
} from "./interface/ILOVE20ExtensionGroupActionFactory.sol";
import {IGroupManager} from "./interface/IGroupManager.sol";
import {IGroupJoin} from "./interface/IGroupJoin.sol";
import {IGroupVerify} from "./interface/IGroupVerify.sol";

/// @title LOVE20ExtensionGroupActionFactory
/// @notice Factory contract for creating LOVE20ExtensionGroupAction instances
contract LOVE20ExtensionGroupActionFactory is
    ExtensionFactoryBase,
    ILOVE20ExtensionGroupActionFactory
{
    // ============ Storage ============

    /// @notice The group manager address configured in the factory
    address public immutable GROUP_MANAGER_ADDRESS;

    /// @notice The group join address configured in the factory
    address public immutable GROUP_JOIN_ADDRESS;

    /// @notice The group verify address configured in the factory
    address public immutable GROUP_VERIFY_ADDRESS;

    /// @notice The group address configured in the factory
    address public immutable GROUP_ADDRESS;

    // ============ Constructor ============

    /// @param center_ The extension center address
    /// @param groupManagerAddress_ The group manager address
    /// @param groupJoinAddress_ The group join address
    /// @param groupVerifyAddress_ The group verify address
    /// @param groupAddress_ The group address
    constructor(
        address center_,
        address groupManagerAddress_,
        address groupJoinAddress_,
        address groupVerifyAddress_,
        address groupAddress_
    ) ExtensionFactoryBase(center_) {
        GROUP_MANAGER_ADDRESS = groupManagerAddress_;
        GROUP_JOIN_ADDRESS = groupJoinAddress_;
        GROUP_VERIFY_ADDRESS = groupVerifyAddress_;
        GROUP_ADDRESS = groupAddress_;
    }

    // ============ Factory Functions ============

    /// @notice Create a new LOVE20ExtensionGroupAction extension
    /// @param tokenAddress_ The token address
    /// @param stakeTokenAddress_ The stake token address
    /// @param joinTokenAddress_ The join token address
    /// @param activationStakeAmount_ The activation stake amount
    /// @param maxJoinAmountRatio_ The max join amount ratio (with 1e18 precision)
    /// @param maxVerifyCapacityFactor_ The max verify capacity factor (with 1e18 precision)
    /// @return extension The address of the created extension
    function createExtension(
        address tokenAddress_,
        address stakeTokenAddress_,
        address joinTokenAddress_,
        uint256 activationStakeAmount_,
        uint256 maxJoinAmountRatio_,
        uint256 maxVerifyCapacityFactor_
    ) external returns (address extension) {
        extension = address(
            new LOVE20ExtensionGroupAction(
                address(this),
                tokenAddress_,
                GROUP_MANAGER_ADDRESS,
                stakeTokenAddress_,
                joinTokenAddress_,
                activationStakeAmount_,
                maxJoinAmountRatio_,
                maxVerifyCapacityFactor_
            )
        );

        _registerExtension(extension, tokenAddress_);

        emit ExtensionCreate(extension, tokenAddress_);
    }
}
