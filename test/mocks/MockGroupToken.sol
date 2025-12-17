// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

/**
 * @title MockSLToken
 * @notice Mock SL token for testing
 */
contract MockSLToken {
    uint256 internal _tokenAmount;

    function setTokenAmount(uint256 amount) external {
        _tokenAmount = amount;
    }

    function tokenAmounts()
        external
        view
        returns (
            uint256 tokenAmount,
            uint256 slTokenAmount,
            uint256 liquidityAmount,
            address pair
        )
    {
        return (_tokenAmount, 0, 0, address(0));
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }
}

/**
 * @title MockSTToken
 * @notice Mock ST token for testing
 */
contract MockSTToken {
    uint256 internal _reserve;

    function setReserve(uint256 amount) external {
        _reserve = amount;
    }

    function reserve() external view returns (uint256) {
        return _reserve;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }
}

/**
 * @title MockGroupToken
 * @notice Mock ERC20 token with burn support for testing
 */
contract MockGroupToken {
    mapping(address => uint256) internal _balances;
    mapping(address => mapping(address => uint256)) internal _allowances;
    uint256 internal _totalSupply;

    MockSLToken public immutable slToken;
    MockSTToken public immutable stToken;

    constructor() {
        slToken = new MockSLToken();
        stToken = new MockSTToken();
    }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
    }

    function burn(uint256 amount) external {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        _balances[msg.sender] -= amount;
        _totalSupply -= amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        require(
            _allowances[from][msg.sender] >= amount,
            "Insufficient allowance"
        );
        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function slAddress() external view returns (address) {
        return address(slToken);
    }

    function stAddress() external view returns (address) {
        return address(stToken);
    }
}
