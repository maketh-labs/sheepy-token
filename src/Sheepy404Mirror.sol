// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {DN404Mirror} from "dn404/src/DN404Mirror.sol";
import {IERC4906} from "./interfaces/IERC4906.sol";

/// @dev This contract can be used by itself or as an proxy's implementation.
contract Sheepy404Mirror is DN404Mirror, IERC4906 {
    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                        CONSTRUCTOR                         */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    constructor() DN404Mirror(msg.sender) {}

    /// @inheritdoc DN404Mirror
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override
        returns (bool)
    {
        return interfaceId == type(IERC4906).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
