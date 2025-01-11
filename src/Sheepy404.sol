// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {SheepyBase} from "./SheepyBase.sol";
import {DN404} from "dn404/src/DN404.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {EnumerableRoles} from "solady/auth/EnumerableRoles.sol";
import {LibString} from "solady/utils/LibString.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @dev This contract can be used by itself or as an proxy's implementation.
contract Sheepy404 is DN404, SheepyBase {
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

    /// @dev How much native currency required to reveal a token.
    uint256 public revealPrice;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                        INITIALIZER                         */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev For initialization.
    function initialize(address initialOwner, address initialAdmin, address mirror)
        public
        virtual
    {
        uint256 initialSupply = 1_000_000_000 * 10 ** 18;
        _initializeSheepyBase(initialOwner, initialAdmin);
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

    /// @dev Allows the public to pay to reveal the `tokenIds`.
    function reveal(uint256[] calldata tokenIds) public payable virtual {
        require(msg.value == revealPrice * tokenIds.length, "Wrong payment.");
        for (uint256 i; i < tokenIds.length; ++i) {
            uint256 id = tokenIds[i];
            if (!_exists(id)) revert TokenDoesNotExist();
            emit Reveal(id);
        }
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
                if (from[i] != to[i]) emit Reset(ids[i]);
            }
        }
    }
}
