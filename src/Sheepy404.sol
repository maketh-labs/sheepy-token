// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {SheepyBase} from "./SheepyBase.sol";
import {DN404} from "dn404/src/DN404.sol";
import {LibString} from "solady/utils/LibString.sol";
import {LibBitmap} from "solady/utils/LibBitmap.sol";
import {DynamicArrayLib} from "solady/utils/DynamicArrayLib.sol";
import {EIP712} from "solady/utils/EIP712.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {LibAGW} from "absmate/utils/LibAGW.sol";

/// @dev This contract can be used by itself or as a proxy's implementation.
contract Sheepy404 is DN404, SheepyBase, EIP712 {
    using LibBitmap for LibBitmap.Bitmap;
    using DynamicArrayLib for uint256[];
    using DynamicArrayLib for address[];

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           ERRORS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Wrong payment amount.
    error WrongPayment();

    /// @dev Signature has expired.
    error SignatureExpired();

    /// @dev Salt has already been used.
    error SaltUsed();

    /// @dev Asset count is too small.
    error AssetCountTooSmall();

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           EVENTS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Emitted when `tokenId` is revealed.
    event Reveal(uint256 indexed tokenId);

    /// @dev Emitted when `tokenId` is rerolled.
    event Reroll(uint256 indexed tokenId);

    /// @dev Emitted when `tokenId` is transferred and the metadata should be reset.
    event Reset(uint256 indexed tokenId);

    /// @dev Emitted when asset count is set.
    event AssetCount(uint256 newAssetCount);

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         CONSTANTS                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev `keccak256("FreeReveal(uint256[] tokenIds,bytes32 salt,uint256 deadline)")`.
    bytes32 private constant _FREE_REVEAL_TYPEHASH =
        0xcbb6b2caea63e26816b6962db016926cda6cb7d3a5d178e4f6d922786b13519a;

    /// @dev `keccak256("FreeReroll(uint256[] tokenIds,bytes32 salt,uint256 deadline)")`.
    bytes32 private constant _FREE_REROLL_TYPEHASH =
        0xab9e08c6dc1641c44003b1a2c1c5dea3cc27a6ce103778226c15c053a8ca9dae;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          STORAGE                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev The name of the contract.
    string internal _name;

    /// @dev The symbol of the contract.
    string internal _symbol;

    /// @dev The base URI of the contract.
    string internal _baseURI;

    /// @dev Whether a certain `tokenId` has been revealed.
    LibBitmap.Bitmap internal _revealed;

    /// @dev How much native currency required to reveal a token.
    uint256 public revealPrice;

    /// @dev How much native currency required to reroll a token.
    uint256 public rerollPrice;

    /// @dev Whether a certain `salt` has been used.
    mapping(address account => mapping(bytes32 salt => bool used)) public usedSalt;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                        INITIALIZER                         */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev For initialization.
    function initialize(
        address initialOwner,
        address initialAdmin,
        address mirror,
        string memory notSoSecret
    ) public virtual {
        uint256 initialSupply = 10_000_000_000 * 10 ** 18;
        _initializeSheepyBase(initialOwner, initialAdmin, notSoSecret);
        _initializeDN404(initialSupply, initialOwner, mirror);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          METADATA                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the name.
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /// @dev Returns the symbol.
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /// @dev Returns the token URI.
    function _tokenURI(uint256 id) internal view virtual override returns (string memory result) {
        if (!_exists(id)) revert TokenDoesNotExist();
        string memory baseURI = _baseURI;
        if (bytes(baseURI).length != 0) {
            result = LibString.replace(baseURI, "{id}", LibString.toString(id));
        }
    }

    /// @dev Returns the domain separator for EIP-712 typed data signing.
    function DOMAIN_SEPARATOR() external view returns (bytes32 result) {
        return _domainSeparator();
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                       REVEAL & REROLL                      */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Allows the owner of the NFTs to pay to reveal the `tokenIds`.
    /// A NFT can be re-revealed even if it has been revealed.
    function reveal(uint256[] memory tokenIds) public payable virtual {
        if (msg.value != revealPrice * tokenIds.length) revert WrongPayment();
        _reveal(tokenIds);
    }

    /// @dev Allows the owner of the NFTs to pay to reroll the `tokenIds`.
    function reroll(uint256[] memory tokenIds) public payable {
        if (msg.value != rerollPrice * tokenIds.length) revert WrongPayment();
        _reroll(tokenIds);
    }

    function freeReveal(
        uint256[] memory tokenIds,
        bytes32 salt,
        uint256 deadline,
        bytes memory signature
    ) public {
        _verifyFreeActionSignature(_FREE_REVEAL_TYPEHASH, tokenIds, salt, deadline, signature);
        _reveal(tokenIds);
    }

    /// require a signature from the owner to reroll
    function freeReroll(
        uint256[] memory tokenIds,
        bytes32 salt,
        uint256 deadline,
        bytes memory signature
    ) public {
        _verifyFreeActionSignature(_FREE_REROLL_TYPEHASH, tokenIds, salt, deadline, signature);
        _reroll(tokenIds);
    }

    /// @dev Returns if each of the `tokenIds` has been revealed.
    function revealed(uint256[] memory tokenIds) public view returns (bool[] memory) {
        uint256[] memory results = DynamicArrayLib.malloc(tokenIds.length);
        for (uint256 i; i < tokenIds.length; ++i) {
            results.set(i, _revealed.get(tokenIds.get(i)));
        }
        return results.asBoolArray();
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                   PUBLIC VIEW FUNCTIONS                    */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Return all the NFT token IDs owned by `owner`.
    function ownedIds(address owner) public view returns (uint256[] memory) {
        return _ownedIds(owner, 0, type(uint256).max);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      ADMIN FUNCTIONS                       */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Sets the name and symbol.
    function setNameAndSymbol(string memory newName, string memory newSymbol)
        public
        virtual
        onlyOwnerOrRole(ADMIN_ROLE)
    {
        _name = newName;
        _symbol = newSymbol;
    }

    /// @dev Sets the base URI.
    function setBaseURI(string memory newBaseURI) public virtual onlyOwnerOrRole(ADMIN_ROLE) {
        _baseURI = newBaseURI;
        _logBatchMetadataUpdate(1, totalSupply() / _unit());
    }

    /// @dev Sets the reveal price.
    function setRevealPrice(uint256 newRevealPrice) public onlyOwnerOrRole(ADMIN_ROLE) {
        revealPrice = newRevealPrice;
    }

    /// @dev Sets the reroll price.
    function setRerollPrice(uint256 newRerollPrice) public onlyOwnerOrRole(ADMIN_ROLE) {
        rerollPrice = newRerollPrice;
    }

    /// @dev Sets the asset count.
    function setAssetCount(uint256 newAssetCount) public onlyOwnerOrRole(ADMIN_ROLE) {
        uint256 minAssetCount = totalSupply() / _unit();
        if (newAssetCount < minAssetCount) revert AssetCountTooSmall();
        emit AssetCount(newAssetCount);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      INTERNAL HELPERS                      */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns if `msg.sender` can reveal `id`.
    function _callerIsAuthorizedFor(uint256 id) internal view returns (bool) {
        // `_ownerOf` will revert if the token does not exist.
        address nftOwner = _ownerOf(id);
        if (nftOwner == msg.sender) return true;
        if (_isApprovedForAll(nftOwner, msg.sender)) return true;
        if (_getApproved(id) == msg.sender) return true;
        return false;
    }

    function _verifyFreeActionSignature(
        bytes32 typeHash,
        uint256[] memory tokenIds,
        bytes32 salt,
        uint256 deadline,
        bytes memory signature
    ) internal {
        bytes32 hash = _hashTypedData(keccak256(abi.encode(typeHash, tokenIds, salt, deadline)));
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
        address signer = ecrecover(hash, v, r, s);
        // Check if signer has admin role
        if (!hasRole(signer, ADMIN_ROLE)) revert Unauthorized();
        if (block.timestamp > deadline) revert SignatureExpired();
        if (usedSalt[signer][salt]) revert SaltUsed();
        usedSalt[signer][salt] = true;
    }

    /// @dev Internal function to handle the reveal logic for token IDs.
    function _reveal(uint256[] memory tokenIds) internal {
        for (uint256 i; i < tokenIds.length; ++i) {
            uint256 id = tokenIds.get(i);
            if (!_callerIsAuthorizedFor(id)) revert Unauthorized();
            if (_revealed.get(id)) continue;
            _revealed.set(id);
            emit Reveal(id);
            _logMetadataUpdate(id);
        }
    }

    /// @dev Internal function to handle the reroll logic for token IDs.
    function _reroll(uint256[] memory tokenIds) internal {
        for (uint256 i; i < tokenIds.length; ++i) {
            uint256 id = tokenIds.get(i);
            if (!_callerIsAuthorizedFor(id)) revert Unauthorized();
            emit Reroll(id);
            _logMetadataUpdate(id);
        }
    }

    /// @dev Helper function to log metadata update to the mirror
    function _logMetadataUpdate(uint256 tokenId) internal {
        address mirror = _getDN404Storage().mirrorERC721;
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, 0x9e1569c7) // logMetadataUpdate(uint256)
            mstore(0x20, tokenId)
            pop(call(gas(), mirror, 0, 0x1c, 0x24, 0x00, 0x20))
        }
    }

    /// @dev Helper function to log batch metadata update to the mirror
    function _logBatchMetadataUpdate(uint256 fromTokenId, uint256 toTokenId) internal {
        address mirror = _getDN404Storage().mirrorERC721;
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, 0x5f3058f7) // logBatchMetadataUpdate(uint256,uint256)
            mstore(0x20, fromTokenId)
            mstore(0x40, toTokenId)
            pop(call(gas(), mirror, 0, 0x1c, 0x44, 0x00, 0x20))
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         OVERRIDES                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Hook that is called after a batch of NFT transfers.
    /// The lengths of `from`, `to`, and `ids` are guaranteed to be the same.
    function _afterNFTTransfers(address[] memory from, address[] memory to, uint256[] memory ids)
        internal
        virtual
        override
    {
        // Emit a {Reset} event for each id if the caller isn't the mirror.
        if (msg.sender != _getDN404Storage().mirrorERC721) {
            for (uint256 i; i < ids.length; ++i) {
                if (from.toUint256Array().get(i) != to.toUint256Array().get(i)) {
                    uint256 id = ids.get(i);
                    if (!_revealed.get(id)) continue;
                    _revealed.unset(id);
                    emit Reset(id);
                    _logMetadataUpdate(id);
                }
            }
        }
    }

    /// @dev Need to override this.
    function _useAfterNFTTransfers() internal virtual override returns (bool) {
        return true;
    }

    /// @dev 1m full ERC20 tokens for 1 ERC721 NFT.
    function _unit() internal view virtual override returns (uint256) {
        return 1_000_000 * 10 ** 18;
    }

    /// @dev Returns the name and version of the contract. Override from EIP712.
    function _domainNameAndVersion()
        internal
        pure
        override
        returns (string memory, string memory)
    {
        return ("Sheepy404", "1");
    }

    /// @dev On Abstract chain, individual accounts have contract code, which would normally cause _skipNFTDefault to return true for all accounts.
    /// To handle this, we treat AGW (Abstract Global Wallet) as an exception: only AGW contracts are skipped, while regular EOAs (even with code) are not.
    /// This override ensures correct skipNFT behavior for Abstract chain accounts.
    function _skipNFTDefault(address owner) internal view virtual override returns (bool result) {
        if (LibAGW.isAGWContract(owner)) return false;
        /// @solidity memory-safe-assembly
        assembly {
            result := iszero(iszero(extcodesize(owner)))
        }
    }
}
