// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IExtensionCore} from "@extension/src/interface/base/IExtensionCore.sol";
import {IExtensionReward} from "@extension/src/interface/base/IExtensionReward.sol";
import {ILOVE20ExtensionGroupAction} from "../../src/interface/ILOVE20ExtensionGroupAction.sol";
import {ExtensionCore} from "@extension/src/base/ExtensionCore.sol";
import {ExtensionReward} from "@extension/src/base/ExtensionReward.sol";

/**
 * @title MockExtensionGroupAction
 * @dev Mock Extension contract for GroupAction testing that implements ILOVE20ExtensionGroupAction
 */
contract MockExtensionGroupAction is ExtensionReward, ILOVE20ExtensionGroupAction {
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
    ) ExtensionReward(factory_, tokenAddress_) {
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

    function isJoinedValueCalculated() external pure returns (bool) {
        return true;
    }

    function joinedValue() external pure returns (uint256) {
        return 0;
    }

    function joinedValueByAccount(
        address /*account*/
    ) external pure returns (uint256) {
        return 0;
    }

    function rewardByAccount(
        uint256 /*round*/,
        address /*account*/
    )
        public
        pure
        override(IExtensionReward, ExtensionReward)
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

    // ============ ILOVE20ExtensionGroupAction Interface ============

    function initializeAction() external override {
        // Mock implementation - do nothing
    }

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

