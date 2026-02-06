// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    IExtensionGroupActionFactory
} from "./interface/IExtensionGroupActionFactory.sol";
import {ExtensionGroupAction} from "./ExtensionGroupAction.sol";
import {ExtensionFactoryBase} from "@extension/src/ExtensionFactoryBase.sol";
import {IExtensionCenter} from "@extension/src/interface/IExtensionCenter.sol";
import {TokenLib} from "@extension/src/lib/TokenLib.sol";
import {IGroupActionFactoryErrors} from "./interface/IGroupActionFactory.sol";

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
        uint256 activationMinGovRatio_,
        uint256 activationStakeAmount_,
        address joinTokenAddress_,
        uint256 maxJoinAmountRatio_
    ) external returns (address extension) {
        if (activationMinGovRatio_ > 1e18) {
            revert IGroupActionFactoryErrors.InvalidActivationMinGovRatio();
        }
        if (activationStakeAmount_ == 0) {
            revert IGroupActionFactoryErrors.InvalidActivationStakeAmount();
        }
        if (maxJoinAmountRatio_ == 0 || maxJoinAmountRatio_ > 1e18) {
            revert IGroupActionFactoryErrors.InvalidMaxJoinAmountRatio();
        }
        _validateJoinToken(tokenAddress_, joinTokenAddress_);

        extension = address(
            new ExtensionGroupAction(
                address(this),
                tokenAddress_,
                activationMinGovRatio_,
                activationStakeAmount_,
                joinTokenAddress_,
                maxJoinAmountRatio_
            )
        );

        _registerExtension(extension, tokenAddress_);
    }

    function _validateJoinToken(
        address tokenAddress_,
        address joinTokenAddress_
    ) private view {
        if (joinTokenAddress_ == tokenAddress_) return;

        if (
            !TokenLib.isLpTokenFromFactory(
                joinTokenAddress_,
                IExtensionCenter(CENTER_ADDRESS).uniswapV2FactoryAddress()
            )
        ) {
            revert IGroupActionFactoryErrors.InvalidJoinTokenAddress();
        }

        if (
            !TokenLib.isLpTokenContainsToken(joinTokenAddress_, tokenAddress_)
        ) {
            revert IGroupActionFactoryErrors.InvalidJoinTokenAddress();
        }
    }
}
