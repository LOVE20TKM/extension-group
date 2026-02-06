// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IGroupActionFactoryErrors {
    error InvalidJoinTokenAddress();
    error InvalidMaxJoinAmountRatio();
    error InvalidActivationMinGovRatio();
    error InvalidActivationStakeAmount();
}

interface IGroupActionFactory is IGroupActionFactoryErrors {
    function GROUP_MANAGER_ADDRESS() external view returns (address);

    function GROUP_JOIN_ADDRESS() external view returns (address);

    function GROUP_VERIFY_ADDRESS() external view returns (address);

    function GROUP_ADDRESS() external view returns (address);

    function createExtension(
        address tokenAddress_,
        uint256 activationMinGovRatio_,
        uint256 activationStakeAmount_,
        address joinTokenAddress_,
        uint256 maxJoinAmountRatio_
    ) external returns (address extension);
}
