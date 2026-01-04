// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IReward} from "@extension/src/interface/IReward.sol";
import {IGroupAction} from "../../src/interface/IGroupAction.sol";
import {ExtensionBaseReward} from "@extension/src/ExtensionBaseReward.sol";
import {ExtensionBase} from "@extension/src/ExtensionBase.sol";
import {IExtension} from "@extension/src/interface/IExtension.sol";

/**
 * @title MockExtensionGroupAction
 * @dev Mock Extension contract for GroupAction testing that implements IGroupAction
 */
contract MockExtensionGroupAction is ExtensionBaseReward, IGroupAction {
    // ============ Config Immutables ============

    address public immutable override STAKE_TOKEN_ADDRESS;
    address public immutable override JOIN_TOKEN_ADDRESS;
    uint256 public immutable override ACTIVATION_STAKE_AMOUNT;
    uint256 public immutable override MAX_JOIN_AMOUNT_RATIO;
    uint256 public immutable override MAX_VERIFY_CAPACITY_FACTOR;

    constructor(
        address factory_,
        address tokenAddress_,
        address stakeTokenAddress_,
        address joinTokenAddress_,
        uint256 activationStakeAmount_,
        uint256 maxJoinAmountRatio_,
        uint256 maxVerifyCapacityFactor_
    ) ExtensionBaseReward(factory_, tokenAddress_) {
        STAKE_TOKEN_ADDRESS = stakeTokenAddress_;
        JOIN_TOKEN_ADDRESS = joinTokenAddress_;
        ACTIVATION_STAKE_AMOUNT = activationStakeAmount_;
        MAX_JOIN_AMOUNT_RATIO = maxJoinAmountRatio_;
        MAX_VERIFY_CAPACITY_FACTOR = maxVerifyCapacityFactor_;
    }

    /// @dev Test helper to simulate initialization without going through _doInitialize
    function mockInitialize(uint256 actionId_) external {
        initialized = true;
        actionId = actionId_;
    }

    function isJoinedValueConverted()
        external
        pure
        override(ExtensionBase)
        returns (bool)
    {
        return true;
    }

    function joinedValue()
        external
        pure
        override(ExtensionBase)
        returns (uint256)
    {
        return 0;
    }

    function joinedValueByAccount(
        address /*account*/
    ) external pure override(ExtensionBase) returns (uint256) {
        return 0;
    }

    function rewardByAccount(
        uint256 /*round*/,
        address /*account*/
    )
        public
        pure
        override(ExtensionBaseReward)
        returns (uint256 reward, bool isMinted)
    {
        return (0, false);
    }

    function _calculateReward(
        uint256 /*round*/,
        address /*account*/
    ) internal pure override returns (uint256) {
        return 0;
    }

    function exit() external pure {
        revert("Exit not implemented in mock");
    }

    // ============ IGroupAction Interface ============

    function burnUnclaimedReward(uint256 /*round*/) external pure override {
        revert("Not implemented in mock");
    }

    function generatedRewardByGroupId(
        uint256 /*round*/,
        uint256 /*groupId*/
    ) external pure override returns (uint256) {
        return 0;
    }

    function generatedRewardByVerifier(
        uint256 /*round*/,
        address /*verifier*/
    ) external pure override returns (uint256) {
        return 0;
    }
}
