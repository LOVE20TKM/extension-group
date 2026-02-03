// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IGroupActionFactoryErrors {
    error InvalidJoinTokenAddress();
    error InvalidMaxJoinAmountRatio();
}

interface IGroupActionFactory is IGroupActionFactoryErrors {
    function GROUP_MANAGER_ADDRESS() external view returns (address);

    function GROUP_JOIN_ADDRESS() external view returns (address);

    function GROUP_VERIFY_ADDRESS() external view returns (address);

    function GROUP_ADDRESS() external view returns (address);

    function createExtension(
        address tokenAddress_,
        address joinTokenAddress_,
        uint256 activationStakeAmount_,
        uint256 maxJoinAmountRatio_,
        uint256 activationMinGovRatio_
    ) external returns (address extension);
}
