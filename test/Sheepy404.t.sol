// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./utils/SoladyTest.sol";
import "../src/Sheepy404.sol";
import "../src/Sheepy404Mirror.sol";

import "solady/utils/LibClone.sol";

contract Sheepy404Test is SoladyTest {
    Sheepy404 sheepy404;
    Sheepy404Mirror sheepy404Mirror;

    address internal _ALICE = address(0x111);
    address internal _BOB = address(0x222);
    address internal _CHARLIE = address(0x333);
    address internal _DAVID = address(0x444);

    uint256 internal _WAD = 10 ** 18;

    function setUp() public {
        sheepy404 = new Sheepy404();
        sheepy404Mirror = new Sheepy404Mirror();
    }

    function testInitialize() public {
        address mirror = address(sheepy404Mirror);
        // string memory name = "Sheepy";
        // string memory symbol = "Sheepy404";
        // string memory baseURI = "https://sheepyapi.com/{id}.json";
        uint256 initialSupply = 1000 * _WAD;

        sheepy404.initialize(_ALICE, initialSupply, mirror, _BOB);
        assertEq(sheepy404.balanceOf(_ALICE), initialSupply);
        sheepy404Mirror.pullOwner();
        assertEq(sheepy404Mirror.owner(), _ALICE);
    }
}
