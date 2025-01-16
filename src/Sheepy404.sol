// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {SheepyBase} from "./SheepyBase.sol";
import {DN404} from "dn404/src/DN404.sol";
import {LibString} from "solady/utils/LibString.sol";
import {LibBitmap} from "solady/utils/LibBitmap.sol";
import {DynamicArrayLib} from "solady/utils/DynamicArrayLib.sol";

/// @dev This contract can be used by itself or as an proxy's implementation.
contract Sheepy404 is DN404, SheepyBase {
    using LibBitmap for *;
    using DynamicArrayLib for *;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           EVENTS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Emitted when `tokenId` is revealed.
    event Reveal(uint256 indexed tokenId);

    /// @dev Emitted when `tokenId` is transferred and the metadata should be reset.
    event Reset(uint256 indexed tokenId);

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
        uint256 initialSupply = 1_000_000_000 * 10 ** 18;
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

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           REVEAL                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Allows the owner of the NFTs to pay to reveal the `tokenIds`.
    /// A NFT can be re-revealed even if it has been revealed.
    function reveal(uint256[] memory tokenIds) public payable virtual {
        require(msg.value == revealPrice * tokenIds.length, "Wrong payment.");
        for (uint256 i; i < tokenIds.length; ++i) {
            uint256 id = tokenIds.get(i);
            require(_callerIsAuthorizedFor(id), "Unauthorized.");
            _revealed.set(id);
            emit Reveal(id);
        }
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
    }

    /// @dev Sets the reveal price.
    function setRevealPrice(uint256 newRevealPrice) public onlyOwnerOrRole(ADMIN_ROLE) {
        revealPrice = newRevealPrice;
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

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         OVERRIDES                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev 100k full ERC20 tokens for 1 ERC721 NFT.
    function _unit() internal view virtual override returns (uint256) {
        return 100_000 * 10 ** 18;
    }

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
                    _revealed.unset(id);
                    emit Reset(id);
                }
            }
        }
    }

    /// @dev Need to override this.
    function _useAfterNFTTransfers() internal virtual override returns (bool) {
        return true;
    }
}
