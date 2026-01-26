// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    IExtensionGroupActionFactory
} from "./interface/IExtensionGroupActionFactory.sol";
import {ExtensionGroupAction} from "./ExtensionGroupAction.sol";
import {ILOVE20Vote} from "@core/interfaces/ILOVE20Vote.sol";
import {ILOVE20Submit, ActionInfo} from "@core/interfaces/ILOVE20Submit.sol";
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
        address joinTokenAddress_,
        uint256 activationStakeAmount_,
        uint256 maxJoinAmountRatio_,
        uint256 maxVerifyCapacityFactor_
    ) external returns (address extension) {
        if (maxJoinAmountRatio_ == 0 || maxJoinAmountRatio_ > 1e18) {
            revert IGroupActionFactoryErrors.InvalidMaxJoinAmountRatio();
        }
        if (maxVerifyCapacityFactor_ == 0) {
            revert IGroupActionFactoryErrors.InvalidMaxVerifyCapacityFactor();
        }
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

    function votedGroupActions(
        address tokenAddress,
        uint256 round
    )
        external
        view
        override
        returns (uint256[] memory actionIds_, address[] memory extensions)
    {
        IExtensionCenter center_ = IExtensionCenter(CENTER_ADDRESS);
        ILOVE20Vote vote = ILOVE20Vote(center_.voteAddress());
        ILOVE20Submit submit = ILOVE20Submit(center_.submitAddress());

        uint256 count = vote.votedActionIdsCount(tokenAddress, round);
        if (count == 0) return (actionIds_, extensions);

        extensions = new address[](count);
        actionIds_ = new uint256[](count);
        uint256 validCount;

        for (uint256 i; i < count; ) {
            uint256 aid = vote.votedActionIdsAtIndex(tokenAddress, round, i);
            ActionInfo memory actionInfo = submit.actionInfo(tokenAddress, aid);
            address ext = actionInfo.body.whiteListAddress;

            if (ext != address(0) && _isExtension[ext]) {
                extensions[validCount] = ext;
                actionIds_[validCount] = aid;
                unchecked {
                    ++validCount;
                }
            }
            unchecked {
                ++i;
            }
        }

        if (validCount == 0) return (actionIds_, extensions);

        assembly {
            mstore(extensions, validCount)
            mstore(actionIds_, validCount)
        }
        return (actionIds_, extensions);
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
