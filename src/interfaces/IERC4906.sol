// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @title ERC-4906 Metadata Update Extension
/// @dev Interface for emitting events when token metadata is changed.
interface IERC4906 {
    /// @dev Emitted when the metadata of a token is changed.
    event MetadataUpdate(uint256 _tokenId);

    /// @dev Emitted when the metadata of a range of tokens is changed.
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);
}
