// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ExtensionFactoryBase} from "@extension/src/ExtensionFactoryBase.sol";
import {IGroupActionFactory} from "../../src/interface/IGroupActionFactory.sol";
import {
    IGroupActionFactoryErrors
} from "../../src/interface/IGroupActionFactory.sol";
import {IGroupManager} from "../../src/interface/IGroupManager.sol";
import {GroupJoin} from "../../src/GroupJoin.sol";
import {GroupVerify} from "../../src/GroupVerify.sol";
import {ExtensionGroupAction} from "../../src/ExtensionGroupAction.sol";
import {TokenLib} from "@extension/src/lib/TokenLib.sol";
import {IExtensionCenter} from "@extension/src/interface/IExtensionCenter.sol";

/// @title MockExtensionGroupActionFactory
/// @notice Mock factory for testing ExtensionGroupAction
contract MockExtensionGroupActionFactory is
    ExtensionFactoryBase,
    IGroupActionFactory
{
    // ============ Storage ============

    address public immutable GROUP_MANAGER_ADDRESS;
    address public immutable GROUP_JOIN_ADDRESS;
    address public immutable GROUP_VERIFY_ADDRESS;
    address public immutable GROUP_ADDRESS;

    // ============ Constructor ============

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

        // Note: Initialize calls are moved to setUpBase() to avoid constructor reentrancy issues
        // The factory must be fully constructed before calling initialize()
    }

    /// @notice Initialize the singleton contracts (called after factory deployment)
    function initializeSingletons() external {
        IGroupManager(GROUP_MANAGER_ADDRESS).initialize(address(this));
        GroupJoin(GROUP_JOIN_ADDRESS).initialize(address(this));
        GroupVerify(GROUP_VERIFY_ADDRESS).initialize(address(this));
    }

    // ============ Factory Functions ============

    /// @notice Create a new extension (mock implementation)
    function createExtension(
        address tokenAddress_,
        address joinTokenAddress_,
        uint256 activationStakeAmount_,
        uint256 maxJoinAmountRatio_,
        uint256 maxVerifyCapacityFactor_
    ) external returns (address extension) {
        _validateJoinToken(tokenAddress_, joinTokenAddress_);

        extension = address(
            new ExtensionGroupAction(
                address(this),
                tokenAddress_,
                joinTokenAddress_,
                activationStakeAmount_,
                maxJoinAmountRatio_,
                maxVerifyCapacityFactor_
            )
        );

        _registerExtension(extension, tokenAddress_);
    }

    function _validateJoinToken(
        address tokenAddress_,
        address joinTokenAddress_
    ) private view {
        if (joinTokenAddress_ == tokenAddress_) return;

        IExtensionCenter center_ = IExtensionCenter(CENTER_ADDRESS);
        address uniswapV2Factory = center_.uniswapV2FactoryAddress();

        if (
            !TokenLib.isLpTokenFromFactory(joinTokenAddress_, uniswapV2Factory)
        ) {
            revert IGroupActionFactoryErrors.InvalidJoinTokenAddress();
        }

        if (
            !TokenLib.isLpTokenContainsToken(joinTokenAddress_, tokenAddress_)
        ) {
            revert IGroupActionFactoryErrors.InvalidJoinTokenAddress();
        }
    }

    // ============ Test Helper Functions ============

    /// @notice Register an extension for testing (bypasses normal creation flow)
    /// @dev This is a test-only function to register extensions that were created directly
    function registerExtensionForTesting(
        address extension,
        address tokenAddress
    ) external {
        _registerExtension(extension, tokenAddress);
    }
}
