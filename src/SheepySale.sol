// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {EnumerableRoles} from "solady/auth/EnumerableRoles.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";

contract SheepySale is Ownable, EnumerableRoles {
    using ECDSA for bytes32;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          STRUCTS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev For configuring a sale.
    struct SaleConfig {
        address erc20ToSell;
        uint256 unit;
        uint256 unitPrice;
        uint256 startTime;
        uint256 endTime;
        uint256 unitsToSell;
        uint256 maxUnitsPerAddress;
        address signer; // Leave as `address(0)` if no WL required.
    }

    /// @dev Holds the information for a sale.
    struct SaleInfo {
        address erc20ToSell;
        uint256 unit;
        uint256 unitPrice;
        uint256 startTime;
        uint256 endTime;
        uint256 unitsToSell;
        uint256 maxUnitsPerAddress;
        uint256 totalUnitsBought;
        address signer;
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         CONSTANTS                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev The admin role.
    uint256 public constant ADMIN_ROLE = 0;

    /// @dev The role that can withdraw native currency.
    uint256 public constant WITHDRAWER_ROLE = 1;

    /// @dev The maximum role that can be set.
    uint256 public constant MAX_ROLE = 1;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           EVENTS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Emitted for a purchase.
    event Bought(
        address by,
        address to,
        address erc20ToSell,
        uint256 unit,
        uint256 unitPrice,
        uint256 numUnits
    );

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          STORAGE                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Sale storage.
    struct Sale {
        address erc20ToSell;
        uint256 unit;
        uint256 unitPrice;
        uint256 startTime;
        uint256 endTime;
        uint256 unitsToSell;
        uint256 maxUnitsPerAddress;
        uint256 totalUnitsBought;
        address signer;
        mapping(address => uint256) unitsBought;
    }

    /// @dev The sales structs.
    mapping(uint256 => Sale) internal _sales;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                        INITIALIZER                         */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev For initialization.
    function initialize(address initialOwner, address initialAdmin) public virtual {
        _initializeOwner(initialOwner);
        if (initialAdmin != address(0)) _setRole(initialAdmin, ADMIN_ROLE, true);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                            SALE                            */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Public sale function.
    function buy(uint256 saleId, address to, uint256 numUnits, bytes calldata signature)
        public
        payable
    {
        Sale storage s = _sales[saleId];
        require(s.erc20ToSell != address(0), "ERC20 not set.");
        require(s.startTime <= block.timestamp, "Not open.");
        require(block.timestamp <= s.endTime, "Not open.");
        require(msg.value == numUnits * s.unitPrice, "Wrong payment.");
        require(
            (s.unitsBought[msg.sender] += numUnits) <= s.maxUnitsPerAddress,
            "Exceeded per-address quota."
        );
        require((s.totalUnitsBought += numUnits) <= s.unitsToSell, "Exceeded total quota.");

        if (s.signer != address(0)) {
            bytes32 hash = keccak256(abi.encode(address(this), saleId, msg.sender));
            require(
                hash.toEthSignedMessageHash().recover(signature) == s.signer, "Invalid signature."
            );
        }
        SafeTransferLib.safeTransfer(s.erc20ToSell, to, numUnits * s.unit);
        emit Bought(msg.sender, to, s.erc20ToSell, s.unit, s.unitPrice, numUnits);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                   PUBLIC VIEW FUNCTIONS                    */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns info for `saleId`.
    function saleInfo(uint256 saleId) public view returns (SaleInfo memory info) {
        Sale storage s = _sales[saleId];
        info.erc20ToSell = s.erc20ToSell;
        info.unit = s.unit;
        info.unitPrice = s.unitPrice;
        info.startTime = s.startTime;
        info.endTime = s.endTime;
        info.unitsToSell = s.unitsToSell;
        info.maxUnitsPerAddress = s.maxUnitsPerAddress;
        info.signer = s.signer;
        info.totalUnitsBought = s.totalUnitsBought;
    }

    /// @dev Returns the total number of units bought by `by` in `saleId`.
    function unitsBought(uint256 saleId, address by) public view returns (uint256) {
        return _sales[saleId].unitsBought[by];
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      ADMIN FUNCTIONS                       */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Sets the sale config.
    function setSale(uint256 saleId, SaleConfig calldata c) public onlyOwnerOrRole(ADMIN_ROLE) {
        Sale storage s = _sales[saleId];
        s.erc20ToSell = c.erc20ToSell;
        s.unit = c.unit;
        s.unitPrice = c.unitPrice;
        s.startTime = c.startTime;
        s.endTime = c.endTime;
        s.unitsToSell = c.unitsToSell;
        s.maxUnitsPerAddress = c.maxUnitsPerAddress;
        s.signer = c.signer;
    }

    /// @dev Withdraws `amount` of `erc20` to `to`.
    function withdrawERC20(address erc20, address to, uint256 amount)
        public
        onlyOwnerOrRole(WITHDRAWER_ROLE)
    {
        SafeTransferLib.safeTransfer(erc20, _coalesce(to), amount);
    }

    /// @dev Withdraws all the native currency in the contract to `to`.
    function withdrawAllNative(address to) public onlyOwnerOrRole(WITHDRAWER_ROLE) {
        SafeTransferLib.safeTransferAllETH(_coalesce(to));
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      INTERNAL HELPERS                      */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Coalesces `to` to `msg.sender` if it is `address(0)`.
    function _coalesce(address to) internal view returns (address) {
        return to == address(0) ? msg.sender : to;
    }
}
