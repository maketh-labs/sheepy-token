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
    /*                           ERRORS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Amount must be greater than zero.
    error AmountZero();

    /// @dev ERC20 token not set.
    error ERC20NotSet();

    /// @dev Sale is not currently open.
    error SaleNotOpen();

    /// @dev Exceeded total sale quota.
    error ExceededTotalQuota();

    /// @dev Exceeded per-address quota.
    error ExceededAddressQuota();

    /// @dev Wrong payment amount.
    error WrongPayment();

    /// @dev Invalid signature provided.
    error InvalidSignature();

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          STRUCTS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Holds the information for a sale.
    struct Sale {
        // The address of the ERC20 to sell.
        address erc20ToSell;
        // The sale start timestamp.
        uint40 startTime;
        // The sale end timestamp.
        uint40 endTime;
        // Amount of Ether in wei, per `10 ** erc20ToSell.decimals()` ERC20 in wei.
        // `decimals` is usually 18 by default.
        uint96 price;
        // The maximum amount in wei that can be bought.
        uint96 totalQuota;
        // The maximum amount in wei that can be bought per-address.
        uint96 addressQuota;
        // The total amount bought in wei.
        uint96 totalBought;
        // Leave as `address(0)` if no WL required.
        // If WL is required, the hash to be signed is:
        // `keccak256(abi.encode(keccak256("SheepySale"), saleId, msg.sender, customAddressQuota))`.
        address signer;
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           EVENTS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Emitted for a purchase.
    event Bought(address by, address to, address erc20ToSell, uint96 price, uint96 amount);

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          STORAGE                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev The sales structs.
    mapping(uint256 saleId => Sale) internal _sales;
    mapping(uint256 saleId => mapping(address user => uint256 amount)) internal _bought;

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
        uint96 amount,
        uint96 customAddressQuota,
        bytes calldata signature
    ) public payable {
        if (amount == 0) revert AmountZero();
        Sale storage s = _sales[saleId];
        if (s.erc20ToSell == address(0)) revert ERC20NotSet();
        if (s.startTime > block.timestamp || block.timestamp > s.endTime) revert SaleNotOpen();
        if ((s.totalBought += amount) > s.totalQuota) revert ExceededTotalQuota();
        uint256 minAddressQuota = FixedPointMathLib.min(customAddressQuota, s.addressQuota);
        if ((_bought[saleId][msg.sender] += amount) > minAddressQuota) {
            revert ExceededAddressQuota();
        }
        if (msg.value != priceOf(s.erc20ToSell, amount, s.price)) revert WrongPayment();

        if (s.signer != address(0)) {
            bytes32 hash = keccak256("SheepySale");
            hash = keccak256(abi.encode(hash, saleId, msg.sender, customAddressQuota));
            hash = hash.toEthSignedMessageHash();
            if (hash.recover(signature) != s.signer) revert InvalidSignature();
        }
        SafeTransferLib.safeTransfer(s.erc20ToSell, to, amount);
        emit Bought(msg.sender, to, s.erc20ToSell, s.price, amount);
    }

    /// @dev Returns the amount of native currency required for payment.
    function priceOf(address erc20, uint96 amount, uint96 price) public view returns (uint256) {
        uint256 decimals = MetadataReaderLib.readDecimals(erc20, type(uint256).max);
        return FixedPointMathLib.fullMulDivUp(amount, price, 10 ** decimals);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                   PUBLIC VIEW FUNCTIONS                    */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns info for `saleId`.
    function saleInfo(uint256 saleId) public view returns (Sale memory) {
        return _sales[saleId];
    }

    /// @dev Returns the total amount bought by `by` in `saleId`.
    function bought(uint256 saleId, address by) public view returns (uint256) {
        return _bought[saleId][by];
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      ADMIN FUNCTIONS                       */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Sets the sale config.
    function setSale(
        uint256 saleId,
        address erc20ToSell,
        uint40 startTime,
        uint40 endTime,
        uint96 price,
        uint96 totalQuota,
        uint96 addressQuota,
        address signer
    ) public onlyOwnerOrRole(ADMIN_ROLE) {
        _sales[saleId] = Sale({
            erc20ToSell: erc20ToSell,
            startTime: startTime,
            endTime: endTime,
            price: price,
            totalQuota: totalQuota,
            addressQuota: addressQuota,
            totalBought: 0,
            signer: signer
        });
    }
}
