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
        address groupManagerAddress;
        address groupDistrustAddress;
        address stakeTokenAddress;
        uint256 minGovVoteRatioBps;
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
    function createExtension(
        address tokenAddress_,
        address groupManagerAddress_,
        address groupDistrustAddress_,
        address stakeTokenAddress_,
        uint256 minGovVoteRatioBps_,
        uint256 capacityMultiplier_,
        uint256 stakingMultiplier_,
        uint256 maxJoinAmountMultiplier_,
        uint256 minJoinAmount_
    ) external returns (address extension) {
        extension = address(
            new LOVE20ExtensionGroupAction(
                address(this),
                tokenAddress_,
                groupManagerAddress_,
                groupDistrustAddress_,
                stakeTokenAddress_,
                minGovVoteRatioBps_,
                capacityMultiplier_,
                stakingMultiplier_,
                maxJoinAmountMultiplier_,
                minJoinAmount_
            )
        );

        _extensionParams[extension] = ExtensionParams({
            tokenAddress: tokenAddress_,
            groupManagerAddress: groupManagerAddress_,
            groupDistrustAddress: groupDistrustAddress_,
            stakeTokenAddress: stakeTokenAddress_,
            minGovVoteRatioBps: minGovVoteRatioBps_,
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
    ) external view returns (ExtensionParams memory) {
        return _extensionParams[extension_];
    }
}
