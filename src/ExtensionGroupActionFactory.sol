// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ExtensionFactoryBase} from "@extension/src/ExtensionFactoryBase.sol";
import {ExtensionGroupAction} from "./ExtensionGroupAction.sol";
import {
    IExtensionGroupActionFactory
} from "./interface/IExtensionGroupActionFactory.sol";
import {IGroupManager} from "./interface/IGroupManager.sol";
import {IGroupJoin} from "./interface/IGroupJoin.sol";
import {IGroupVerify} from "./interface/IGroupVerify.sol";

contract ExtensionGroupActionFactory is
    ExtensionFactoryBase,
    IExtensionGroupActionFactory
{
    address public immutable GROUP_MANAGER_ADDRESS;
    address public immutable GROUP_JOIN_ADDRESS;
    address public immutable GROUP_VERIFY_ADDRESS;
    address public immutable GROUP_ADDRESS;

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

    function createExtension(
        address tokenAddress_,
        address stakeTokenAddress_,
        address joinTokenAddress_,
        uint256 activationStakeAmount_,
        uint256 maxJoinAmountRatio_,
        uint256 maxVerifyCapacityFactor_
    ) external returns (address extension) {
        extension = address(
            new ExtensionGroupAction(
                address(this),
                tokenAddress_,
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
