// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IGroupSnapshot} from "./IGroupSnapshot.sol";
import {IGroupScore, MAX_ORIGIN_SCORE} from "./IGroupScore.sol";
import {IGroupDistrust} from "./IGroupDistrust.sol";

/// @title IGroupManualScore
/// @notice Combined interface for manual scoring functionality
interface IGroupManualScore is IGroupSnapshot, IGroupScore, IGroupDistrust {}
