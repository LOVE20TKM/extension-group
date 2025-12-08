// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

/**
 * @title MockGroup
 * @notice Mock LOVE20Group (ERC721Enumerable) for testing
 */
contract MockGroup {
    mapping(uint256 => address) internal _owners;
    mapping(address => uint256) internal _balances;
    mapping(address => uint256[]) internal _ownedTokens;
    mapping(uint256 => uint256) internal _ownedTokensIndex;
    mapping(uint256 => string) internal _groupNames;

    uint256 internal _nextTokenId = 1;
    uint256 internal _totalSupply;

    function mint(address to, string memory groupName) external returns (uint256 tokenId) {
        tokenId = _nextTokenId++;
        _owners[tokenId] = to;
        _groupNames[tokenId] = groupName;

        uint256 length = _balances[to];
        _ownedTokens[to].push(tokenId);
        _ownedTokensIndex[tokenId] = length;
        _balances[to]++;
        _totalSupply++;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        return _owners[tokenId];
    }

    function balanceOf(address owner) external view returns (uint256) {
        return _balances[owner];
    }

    function tokenOfOwnerByIndex(
        address owner,
        uint256 index
    ) external view returns (uint256) {
        require(index < _balances[owner], "Index out of bounds");
        return _ownedTokens[owner][index];
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function groupNameOf(uint256 tokenId) external view returns (string memory) {
        return _groupNames[tokenId];
    }

    // Transfer function for testing NFT ownership changes
    function transferFrom(address from, address to, uint256 tokenId) external {
        require(_owners[tokenId] == from, "Not owner");

        // Remove from old owner
        uint256 lastIndex = _balances[from] - 1;
        uint256 tokenIndex = _ownedTokensIndex[tokenId];
        if (tokenIndex != lastIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastIndex];
            _ownedTokens[from][tokenIndex] = lastTokenId;
            _ownedTokensIndex[lastTokenId] = tokenIndex;
        }
        _ownedTokens[from].pop();
        _balances[from]--;

        // Add to new owner
        _owners[tokenId] = to;
        uint256 newLength = _balances[to];
        _ownedTokens[to].push(tokenId);
        _ownedTokensIndex[tokenId] = newLength;
        _balances[to]++;
    }
}

