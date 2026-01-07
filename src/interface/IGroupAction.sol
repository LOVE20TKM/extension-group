// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IGroupAction {
    error RoundHasVerifiedGroups();

    event UnclaimedRewardBurn(
        address indexed tokenAddress,
        uint256 round,
        uint256 indexed actionId,
        uint256 amount
    );

    function burnUnclaimedReward(uint256 round) external;

    function generatedRewardByGroupId(
        uint256 round,
        uint256 groupId
    ) external view returns (uint256);

    function generatedRewardByVerifier(
        uint256 round,
        address verifier
    ) external view returns (uint256);

    function JOIN_TOKEN_ADDRESS() external view returns (address);

    function ACTIVATION_STAKE_AMOUNT() external view returns (uint256);

    function MAX_JOIN_AMOUNT_RATIO() external view returns (uint256);

    function MAX_VERIFY_CAPACITY_FACTOR() external view returns (uint256);
}
