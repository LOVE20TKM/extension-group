// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IGroupServiceEvents {
    event DistributeRecipient(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        uint256 indexed groupId,
        address account,
        address recipient,
        uint256 amount
    );
    event ClaimRewardDistribution(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        address indexed account,
        uint256 mintAmount,
        uint256 burnAmount,
        uint256 distributed,
        uint256 remaining
    );
}

interface IGroupServiceErrors {
    error NoActiveGroups();
    error InvalidExtension();
}

interface IGroupService is IGroupServiceEvents, IGroupServiceErrors {
    function PRECISION() external view returns (uint256);
    function GOV_RATIO_MULTIPLIER() external view returns (uint256);

    function GROUP_ACTION_TOKEN_ADDRESS() external view returns (address);
    function GROUP_ACTION_FACTORY_ADDRESS() external view returns (address);

    function rewardByRecipient(
        uint256 round,
        address groupOwner,
        uint256 actionId,
        uint256 groupId,
        address recipient
    ) external view returns (uint256);

    function rewardDistribution(
        uint256 round,
        address groupOwner,
        uint256 actionId,
        uint256 groupId
    )
        external
        view
        returns (
            address[] memory addrs,
            uint256[] memory ratios,
            uint256[] memory amounts,
            uint256 ownerAmount
        );

    function hasActiveGroups(address owner) external view returns (bool);

    function generatedActionRewardByVerifier(
        uint256 round,
        address verifier
    ) external view returns (uint256 amount);

    function generatedActionReward(
        uint256 round
    ) external view returns (uint256);

    /// @return Gov ratio (1e18) at claim time; 0 if not claimed
    function claimGovRatioByRound(
        uint256 round,
        address account
    ) external view returns (uint256);
}
