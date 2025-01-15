// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "../src/Sheepy404.sol";
import "../src/Sheepy404Mirror.sol";
import "../src/SheepySale.sol";
import "solady/utils/DynamicArrayLib.sol";

contract Sheepy404Test is Test {
    using DynamicArrayLib for *;

    event Reveal(uint256 indexed tokenId);
    event Reset(uint256 indexed tokenId);

    Sheepy404 sheepy;
    Sheepy404Mirror mirror;
    SheepySale sale;

    address internal _ALICE = address(0x111);
    address internal _BOB = address(0x222);
    address internal _CHARLIE = address(0x333);
    address internal _DAVID = address(0x444);

    uint256 internal _WAD = 10 ** 18;
    uint256 internal _INITIAL_SUPPLY = 1_000_000_000 * _WAD;
    uint256 internal _UNIT = _INITIAL_SUPPLY / 10_000;
    uint256 internal _REVEAL_PRICE = 0.001 ether;

    string internal constant _NAME = "Sheepy";
    string internal constant _SYMBOL = "Sheepy404";
    string internal constant _BASE_URI = "https://sheepyapi.com/{id}.json";
    string internal constant _NOT_SO_SECRET = "SomethingSomethingNoGrief";

    function setUp() public {
        sheepy = new Sheepy404();
        mirror = new Sheepy404Mirror();
        sale = new SheepySale();
    }

    function _initialize() internal {
        sheepy.initialize(_ALICE, _BOB, address(mirror), _NOT_SO_SECRET);
        assertEq(sheepy.balanceOf(_ALICE), _INITIAL_SUPPLY);
        mirror.pullOwner();
        assertEq(mirror.owner(), _ALICE);

        vm.prank(_ALICE);
        sheepy.setBaseURI(_BASE_URI);
        vm.prank(_ALICE);
        sheepy.setNameAndSymbol(_NAME, _SYMBOL);

        vm.prank(_ALICE);
        sheepy.setRevealPrice(_REVEAL_PRICE);

        sale.initialize(_ALICE, address(0), _NOT_SO_SECRET);
    }

    function testInitialize() public {
        _initialize();

        assertEq(sheepy.name(), _NAME);
        assertEq(sheepy.symbol(), _SYMBOL);
        assertEq(mirror.name(), _NAME);
        assertEq(mirror.symbol(), _SYMBOL);

        assertEq(sheepy.revealPrice(), _REVEAL_PRICE);

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

    function testSale() public {
        _initialize();

        SheepySale.SaleConfig memory c;
        c.erc20ToSell = address(sheepy);
        c.price = 0.03 ether;
        c.startTime = 1;
        c.endTime = 10000;
        c.totalQuota = 10;
        c.addressQuota = 2;

        vm.prank(_ALICE);
        sale.setSale(1, c);
    }

    function testSalePriceOf() public view {
        uint256 amount = _WAD / 50;
        uint256 pricePerWad = 0.03 ether;
        uint256 totalPrice = sale.priceOf(address(sheepy), amount, pricePerWad);
        assertEq(totalPrice, (10 ** 18 / 50) * 0.03 ether / 10 ** 18);
    }

    function testResetAndReveal() public {
        _initialize();

        vm.expectEmit();
        emit Reset(1);
        vm.prank(_ALICE);
        sheepy.transfer(_BOB, _UNIT * 2);
        assertEq(mirror.balanceOf(_BOB), 2);
        assertEq(mirror.ownerOf(1), _BOB);
        assertEq(mirror.ownerOf(2), _BOB);

        vm.recordLogs();
        vm.prank(_BOB);
        mirror.transferFrom(_BOB, _CHARLIE, 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i; i < entries.length; ++i) {
            assert(entries[i].topics[0] != keccak256("Reset(uint256)"));
        }
        assertEq(mirror.ownerOf(1), _CHARLIE);

        assertEq(_revealed(1), false);
        vm.deal(_CHARLIE, 100 ether);
        vm.prank(_CHARLIE);
        vm.expectEmit();
        emit Reveal(1);
        sheepy.reveal{value: _REVEAL_PRICE}(DynamicArrayLib.p(1).asUint256Array());
        assertEq(_revealed(1), true);

        vm.prank(_CHARLIE);
        sheepy.transfer(_BOB, _UNIT);
        assertEq(mirror.ownerOf(1), _BOB);
    }

    function _revealed(uint256 i) internal view returns (bool) {
        return sheepy.revealed(DynamicArrayLib.p(i).asUint256Array())[0];
    }
}
