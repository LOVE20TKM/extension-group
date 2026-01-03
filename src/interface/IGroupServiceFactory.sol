// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IGroupServiceFactory {
    event ExtensionCreate(
        address indexed extension,
        address indexed tokenAddress
    );
}
