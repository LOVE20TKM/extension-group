// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IGroupActionFactoryErrors {
    error InvalidJoinTokenAddress();
    error InvalidMaxJoinAmountRatio();
    error InvalidMaxVerifyCapacityFactor();
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
        uint256 maxVerifyCapacityFactor_
    ) external returns (address extension);

    function votedGroupActions(
        address tokenAddress,
        uint256 round
    )
        external
        view
        returns (uint256[] memory actionIds_, address[] memory extensions);
}
