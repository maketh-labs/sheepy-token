// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Ownable} from "solady/auth/Ownable.sol";
import {EnumerableRoles} from "solady/auth/EnumerableRoles.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

contract SheepyBase is Ownable, EnumerableRoles {
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
    /*                        INITIALIZER                         */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev For initialization.
    function _initializeSheepyBase(
        address initialOwner,
        address initialAdmin,
        string memory notSoSecret
    ) internal virtual {
        _initializeOwner(initialOwner);
        require(
            keccak256(bytes(notSoSecret))
                == 0x9f6dc27901fd3c0399e319e16bba7e24d8bb2b077fe896daffd2108aa65c40cc
        );
        if (initialAdmin != address(0)) _setRole(initialAdmin, ADMIN_ROLE, true);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      ADMIN FUNCTIONS                       */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

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

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         OVERRIDES                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev So that `_initializeOwner` cannot be called twice.
    function _guardInitializeOwner() internal pure virtual override returns (bool) {
        return true;
    }
}
