// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    IExtensionFactory
} from "@extension/src/interface/IExtensionFactory.sol";

interface IExtensionGroupActionFactory is IExtensionFactory {
    event ExtensionCreate(
        address indexed extension,
        address indexed tokenAddress
    );

    function GROUP_MANAGER_ADDRESS() external view returns (address);

    function GROUP_JOIN_ADDRESS() external view returns (address);

    function GROUP_VERIFY_ADDRESS() external view returns (address);

    function GROUP_ADDRESS() external view returns (address);

    function createExtension(
        address tokenAddress_,
        address stakeTokenAddress_,
        address joinTokenAddress_,
        uint256 activationStakeAmount_,
        uint256 maxJoinAmountRatio_,
        uint256 maxVerifyCapacityFactor_
    ) external returns (address extension);
}
