// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {SheepyBase} from "./SheepyBase.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {MetadataReaderLib} from "solady/utils/MetadataReaderLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";

contract SheepySale is SheepyBase {
    using ECDSA for bytes32;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          STRUCTS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev For configuring a sale.
    struct SaleConfig {
        // The address of the ERC20 to sell.
        address erc20ToSell;
        // Amount of Ether in wei, per `10 ** erc20ToSell.decimals()` ERC20 in wei.
        // `decimals` is usually 18 by default.
        uint256 price;
        // The sale start timestamp.
        uint256 startTime;
        // The sale end timestamp.
        uint256 endTime;
        // The maximum amount in wei that can be bought.
        uint256 totalQuota;
        // The maximum amount in wei that can be bought per-address.
        uint256 addressQuota;
        // Leave as `address(0)` if no WL required.
        // If WL is required, the hash to be signed is:
        // `keccak256(abi.encode(keccak256("SheepySale"), saleId, msg.sender, customAddressQuota))`.
        address signer;
    }

    /// @dev Holds the information for a sale.
    struct SaleInfo {
        address erc20ToSell;
        uint256 price;
        uint256 startTime;
        uint256 endTime;
        uint256 totalQuota;
        uint256 addressQuota;
        uint256 totalBought;
        address signer;
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           EVENTS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Emitted for a purchase.
    event Bought(address by, address to, address erc20ToSell, uint256 price, uint256 amount);

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          STORAGE                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Sale storage.
    struct Sale {
        address erc20ToSell;
        uint256 price;
        uint256 startTime;
        uint256 endTime;
        uint256 totalQuota;
        uint256 addressQuota;
        uint256 totalBought;
        address signer;
        mapping(address => uint256) bought;
    }

    /// @dev The sales structs.
    mapping(uint256 => Sale) internal _sales;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                        INITIALIZER                         */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev For initialization.
    function initialize(address initialOwner, address initialAdmin, string memory notSoSecret)
        public
        virtual
    {
        _initializeSheepyBase(initialOwner, initialAdmin, notSoSecret);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                            SALE                            */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Public sale function.
    /// The `customAddressQuota` can be used to allow dynamic on-the-fly per-address quotas.
    function buy(
        uint256 saleId,
        address to,
        uint256 amount,
        uint256 customAddressQuota,
        bytes calldata signature
    ) public payable {
        Sale storage s = _sales[saleId];
        require(s.erc20ToSell != address(0), "ERC20 not set.");
        require(s.startTime <= block.timestamp && block.timestamp <= s.endTime, "Not open.");
        require((s.totalBought += amount) <= s.totalQuota, "Exceeded total quota.");
        uint256 minAddressQuota = FixedPointMathLib.min(customAddressQuota, s.addressQuota);
        require((s.bought[msg.sender] += amount) <= minAddressQuota, "Exceeded address quota.");
        require(msg.value == priceOf(s.erc20ToSell, amount, s.price), "Wrong payment.");

        if (s.signer != address(0)) {
            bytes32 hash = keccak256("SheepySale");
            hash = keccak256(abi.encode(hash, saleId, msg.sender, customAddressQuota));
            hash = hash.toEthSignedMessageHash();
            require(hash.recover(signature) == s.signer, "Invalid signature.");
        }
        SafeTransferLib.safeTransfer(s.erc20ToSell, to, amount);
        emit Bought(msg.sender, to, s.erc20ToSell, s.price, amount);
    }

    /// @dev Returns the amount of native currency required for payment.
    function priceOf(address erc20, uint256 amount, uint256 price) public view returns (uint256) {
        uint256 decimals = MetadataReaderLib.readDecimals(erc20, type(uint256).max);
        return FixedPointMathLib.fullMulDivUp(amount, price, 10 ** decimals);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                   PUBLIC VIEW FUNCTIONS                    */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns info for `saleId`.
    function saleInfo(uint256 saleId) public view returns (SaleInfo memory info) {
        Sale storage s = _sales[saleId];
        info.erc20ToSell = s.erc20ToSell;
        info.price = s.price;
        info.startTime = s.startTime;
        info.endTime = s.endTime;
        info.totalQuota = s.totalQuota;
        info.addressQuota = s.addressQuota;
        info.signer = s.signer;
        info.totalBought = s.totalBought;
    }

    /// @dev Returns the total amount bought by `by` in `saleId`.
    function bought(uint256 saleId, address by) public view returns (uint256) {
        return _sales[saleId].bought[by];
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      ADMIN FUNCTIONS                       */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Sets the sale config.
    function setSale(uint256 saleId, SaleConfig calldata c) public onlyOwnerOrRole(ADMIN_ROLE) {
        Sale storage s = _sales[saleId];
        s.erc20ToSell = c.erc20ToSell;
        s.price = c.price;
        s.startTime = c.startTime;
        s.endTime = c.endTime;
        s.totalQuota = c.totalQuota;
        s.addressQuota = c.addressQuota;
        s.signer = c.signer;
    }
}
