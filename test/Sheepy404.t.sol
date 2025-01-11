// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./utils/SoladyTest.sol";
import "../src/Sheepy404.sol";
import "../src/Sheepy404Mirror.sol";

import "solady/utils/LibClone.sol";

contract Sheepy404Test is SoladyTest {
    Sheepy404 sheepy;
    Sheepy404Mirror mirror;

    address internal _ALICE = address(0x111);
    address internal _BOB = address(0x222);
    address internal _CHARLIE = address(0x333);
    address internal _DAVID = address(0x444);

    uint256 internal _WAD = 10 ** 18;
    uint256 internal _INITIAL_SUPPLY = 1_000_000_000 * _WAD;
    uint256 internal _UNIT = _INITIAL_SUPPLY / 10_000;

    string internal constant _NAME = "Sheepy";
    string internal constant _SYMBOL = "Sheepy404";
    string internal constant _BASE_URI = "https://sheepyapi.com/{id}.json";

    function setUp() public {
        sheepy = new Sheepy404();
        mirror = new Sheepy404Mirror();
    }

    function testInitialize() public {
        sheepy.initialize(_ALICE, _BOB, address(mirror));
        assertEq(sheepy.balanceOf(_ALICE), _INITIAL_SUPPLY);
        mirror.pullOwner();
        assertEq(mirror.owner(), _ALICE);

        vm.prank(_ALICE);
        sheepy.setBaseURI(_BASE_URI);
        vm.prank(_ALICE);
        sheepy.setNameAndSymbol(_NAME, _SYMBOL);

        assertEq(sheepy.name(), _NAME);
        assertEq(sheepy.symbol(), _SYMBOL);

        assertEq(mirror.name(), _NAME);
        assertEq(mirror.symbol(), _SYMBOL);

        assertEq(mirror.balanceOf(_BOB), 0);
        vm.prank(_ALICE);
        sheepy.transfer(_BOB, _UNIT - 1);
        assertEq(mirror.balanceOf(_BOB), 0);
        vm.prank(_ALICE);
        sheepy.transfer(_BOB, 1);
        assertEq(mirror.balanceOf(_BOB), 1);
        assertEq(mirror.ownerOf(1), _BOB);

        assertEq(mirror.tokenURI(1), "https://sheepyapi.com/1.json");
    }
}
