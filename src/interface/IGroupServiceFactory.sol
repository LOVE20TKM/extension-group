// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IGroupServiceFactoryErrors {
    error InvalidGroupActionTokenAddress();
}

interface IGroupServiceFactory is IGroupServiceFactoryErrors {
    function GROUP_ACTION_FACTORY_ADDRESS() external view returns (address);

    function createExtension(
        address tokenAddress_,
        address groupActionTokenAddress_
    ) external returns (address extension);
}
