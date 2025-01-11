// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {DN404Mirror} from "dn404/src/DN404Mirror.sol";

/// @dev This contract can be used by itself or as an proxy's implementation.
contract Sheepy404Mirror is DN404Mirror {
    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                        CONSTRUCTOR                         */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    constructor() DN404Mirror(msg.sender) {}
}
