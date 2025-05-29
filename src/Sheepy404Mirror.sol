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
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        // ERC-4906 interface ID is hardcoded in the EIP
        return interfaceId == 0x49064906 || super.supportsInterface(interfaceId);
    }

    /// @dev Fallback function for calls from base DN404 contract.
    fallback() external payable virtual override dn404NFTFallback {
        uint256 fnSelector = __calldataload(0x00) >> 224;

        // logMetadataUpdate(uint256)
        if (fnSelector == 0x9e1569c7) {
            if (msg.sender != baseERC20()) revert SenderNotBase();
            emit MetadataUpdate(__calldataload(0x04));
            assembly {
                mstore(0x00, 0x01)
                return(0x00, 0x20)
            }
        }

        // logBatchMetadataUpdate(uint256,uint256)
        if (fnSelector == 0x5f3058f7) {
            if (msg.sender != baseERC20()) revert SenderNotBase();
            emit BatchMetadataUpdate(__calldataload(0x04), __calldataload(0x24));
            assembly {
                mstore(0x00, 0x01)
                return(0x00, 0x20)
            }
        }

        __rv(uint32(FnSelectorNotRecognized.selector));
    }

    /// @dev Returns the calldata value at `offset`.
    function __calldataload(uint256 offset) private pure returns (uint256 value) {
        /// @solidity memory-safe-assembly
        assembly {
            value := calldataload(offset)
        }
    }

    /// @dev More bytecode-efficient way to revert.
    function __rv(uint32 s) private pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, s)
            revert(0x1c, 0x04)
        }
    }
}
