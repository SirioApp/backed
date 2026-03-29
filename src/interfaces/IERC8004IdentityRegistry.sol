// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IERC8004IdentityRegistry
/// @notice Minimal interface for the ERC-8004 Identity Registry (ERC-721 based).
///         Agents register on-chain identities that resolve to registration files.
///         See: https://eips.ethereum.org/EIPS/eip-8004
interface IERC8004IdentityRegistry {
    /// @notice Returns the owner of a given agent identity NFT.
    /// @param agentId The ERC-721 token ID representing the agent identity.
    /// @return owner The address that owns the agent identity.
    function ownerOf(uint256 agentId) external view returns (address owner);

    /// @notice Returns the URI of the agent's registration file.
    /// @param agentId The ERC-721 token ID.
    /// @return uri The URI pointing to the agent's registration JSON.
    function tokenURI(uint256 agentId) external view returns (string memory uri);

    /// @notice Returns the on-chain metadata for a given agent and key.
    /// @param agentId The agent identity token ID.
    /// @param metadataKey The metadata key to query.
    /// @return value The ABI-encoded metadata value.
    function getMetadata(uint256 agentId, bytes32 metadataKey)
        external
        view
        returns (bytes memory value);

    /// @notice Returns the verified wallet address for the agent.
    /// @param agentId The agent identity token ID.
    /// @return wallet The verified wallet address.
    function getAgentWallet(uint256 agentId) external view returns (address wallet);
}
