// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {
    LOVE20ExtensionFactoryBase
} from "@extension/src/LOVE20ExtensionFactoryBase.sol";
import {LOVE20ExtensionGroupAction} from "./LOVE20ExtensionGroupAction.sol";

/// @title LOVE20ExtensionGroupActionFactory
/// @notice Factory contract for creating LOVE20ExtensionGroupAction instances
contract LOVE20ExtensionGroupActionFactory is LOVE20ExtensionFactoryBase {
    // ============ Structs ============

    struct ExtensionParams {
        address tokenAddress;
        address groupAddress;
        uint256 minGovernanceVoteRatio;
        uint256 capacityMultiplier;
        uint256 stakingMultiplier;
        uint256 maxJoinAmountMultiplier;
        uint256 minJoinAmount;
    }

    // ============ Storage ============

    mapping(address => ExtensionParams) private _extensionParams;

    // ============ Constructor ============

    constructor(address center_) LOVE20ExtensionFactoryBase(center_) {}

    // ============ Factory Functions ============

    /// @notice Create a new LOVE20ExtensionGroupAction extension
    /// @param tokenAddress_ The token address
    /// @param groupAddress_ The group NFT contract address
    /// @param minGovernanceVoteRatio_ Minimum governance vote ratio in basis points
    /// @param capacityMultiplier_ Multiplier for capacity calculation
    /// @param stakingMultiplier_ Multiplier for staking calculation
    /// @param maxJoinAmountMultiplier_ Multiplier for max join amount
    /// @param minJoinAmount_ Minimum join amount
    /// @return extension The address of the created extension
    function createExtension(
        address tokenAddress_,
        address groupAddress_,
        uint256 minGovernanceVoteRatio_,
        uint256 capacityMultiplier_,
        uint256 stakingMultiplier_,
        uint256 maxJoinAmountMultiplier_,
        uint256 minJoinAmount_
    ) external returns (address extension) {
        extension = address(
            new LOVE20ExtensionGroupAction(
                address(this),
                tokenAddress_,
                groupAddress_,
                minGovernanceVoteRatio_,
                capacityMultiplier_,
                stakingMultiplier_,
                maxJoinAmountMultiplier_,
                minJoinAmount_
            )
        );

        _extensionParams[extension] = ExtensionParams({
            tokenAddress: tokenAddress_,
            groupAddress: groupAddress_,
            minGovernanceVoteRatio: minGovernanceVoteRatio_,
            capacityMultiplier: capacityMultiplier_,
            stakingMultiplier: stakingMultiplier_,
            maxJoinAmountMultiplier: maxJoinAmountMultiplier_,
            minJoinAmount: minJoinAmount_
        });

        _registerExtension(extension, tokenAddress_);
    }

    // ============ View Functions ============

    /// @notice Get the parameters of an extension
    function extensionParams(
        address extension_
    )
        external
        view
        returns (
            address tokenAddress,
            address groupAddress,
            uint256 minGovernanceVoteRatio,
            uint256 capacityMultiplier,
            uint256 stakingMultiplier,
            uint256 maxJoinAmountMultiplier,
            uint256 minJoinAmount
        )
    {
        ExtensionParams memory params = _extensionParams[extension_];
        return (
            params.tokenAddress,
            params.groupAddress,
            params.minGovernanceVoteRatio,
            params.capacityMultiplier,
            params.stakingMultiplier,
            params.maxJoinAmountMultiplier,
            params.minJoinAmount
        );
    }
}

