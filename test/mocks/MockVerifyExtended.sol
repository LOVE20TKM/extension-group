// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

/**
 * @title MockVerifyExtended
 * @notice Extended Mock Verify contract for group testing with distrust support
 */
contract MockVerifyExtended {
    uint256 internal _currentRound = 1;

    // tokenAddress => round => actionId => extension => score
    mapping(address => mapping(uint256 => mapping(uint256 => mapping(address => uint256))))
        internal _scoreByActionIdByAccount;

    // tokenAddress => round => verifier => actionId => extension => score
    mapping(address => mapping(uint256 => mapping(address => mapping(uint256 => mapping(address => uint256)))))
        internal _scoreByVerifierByActionIdByAccount;

    function setCurrentRound(uint256 round) external {
        _currentRound = round;
    }

    function currentRound() external view returns (uint256) {
        return _currentRound;
    }

    function setScoreByActionIdByAccount(
        address tokenAddress,
        uint256 round,
        uint256 actionId,
        address account,
        uint256 score
    ) external {
        _scoreByActionIdByAccount[tokenAddress][round][actionId][account] = score;
    }

    function scoreByActionIdByAccount(
        address tokenAddress,
        uint256 round,
        uint256 actionId,
        address account
    ) external view returns (uint256) {
        return _scoreByActionIdByAccount[tokenAddress][round][actionId][account];
    }

    function setScoreByVerifierByActionIdByAccount(
        address tokenAddress,
        uint256 round,
        address verifier,
        uint256 actionId,
        address account,
        uint256 score
    ) external {
        _scoreByVerifierByActionIdByAccount[tokenAddress][round][verifier][actionId][account] = score;
    }

    function scoreByVerifierByActionIdByAccount(
        address tokenAddress,
        uint256 round,
        address verifier,
        uint256 actionId,
        address account
    ) external view returns (uint256) {
        return _scoreByVerifierByActionIdByAccount[tokenAddress][round][verifier][actionId][account];
    }
}

