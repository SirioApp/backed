// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Mock ERC-8004 IdentityRegistry for testing.
contract MockIdentityRegistry {
    mapping(uint256 => address) private _owners;
    mapping(uint256 => string) private _uris;
    uint256 private _nextId;

    error ERC721NonexistentToken(uint256 tokenId);

    /// @notice Register a new agent identity, returns the agentId.
    function register(address owner, string calldata uri) external returns (uint256 agentId) {
        agentId = ++_nextId;
        _owners[agentId] = owner;
        _uris[agentId] = uri;
    }

    function ownerOf(uint256 agentId) external view returns (address) {
        address owner = _owners[agentId];
        if (owner == address(0)) revert ERC721NonexistentToken(agentId);
        return owner;
    }

    function tokenURI(uint256 agentId) external view returns (string memory) {
        if (_owners[agentId] == address(0)) revert ERC721NonexistentToken(agentId);
        return _uris[agentId];
    }

    function getMetadata(uint256, bytes32) external pure returns (bytes memory) {
        return "";
    }

    function getAgentWallet(uint256 agentId) external view returns (address) {
        return _owners[agentId];
    }
}
