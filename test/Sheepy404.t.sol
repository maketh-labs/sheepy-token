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
    event Reroll(uint256 indexed tokenId);
    event Reset(uint256 indexed tokenId);

    Sheepy404 sheepy;
    Sheepy404Mirror mirror;
    SheepySale sale;

    address internal _ALICE = address(0x111);
    address internal _BOB;
    uint256 internal _BOB_PRIVATE_KEY;
    address internal _CHARLIE = address(0x333);
    address internal _DAVID = address(0x444);

    uint256 internal _WAD = 10 ** 18;
    uint256 internal _INITIAL_SUPPLY = 10_000_000_000 * _WAD;
    uint256 internal _UNIT = _INITIAL_SUPPLY / 10_000;
    uint256 internal _REVEAL_PRICE = 0.001 ether;
    uint256 internal _REROLL_PRICE = 0.01 ether;

    string internal constant _NAME = "Sheepy";
    string internal constant _SYMBOL = "Sheepy404";
    string internal constant _BASE_URI = "https://sheepyapi.com/{id}.json";
    string internal constant _NOT_SO_SECRET = "SomethingSomethingNoGrief";

    function setUp() public {
        sheepy = new Sheepy404();
        mirror = new Sheepy404Mirror();
        sale = new SheepySale();
        (_BOB, _BOB_PRIVATE_KEY) = makeAddrAndKey("bob");
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
        vm.prank(_ALICE);
        sheepy.setRerollPrice(_REROLL_PRICE);

        sale.initialize(_ALICE, address(0), _NOT_SO_SECRET);
    }

    function testInitialize() public {
        _initialize();

        assertEq(sheepy.name(), _NAME);
        assertEq(sheepy.symbol(), _SYMBOL);
        assertEq(mirror.name(), _NAME);
        assertEq(mirror.symbol(), _SYMBOL);

        assertEq(sheepy.revealPrice(), _REVEAL_PRICE);
        assertEq(sheepy.rerollPrice(), _REROLL_PRICE);

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

    function testResetRevealAndReroll() public {
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
        assertEq(address(_CHARLIE).balance, 100 ether - _REVEAL_PRICE);

        vm.prank(_CHARLIE);
        vm.expectEmit();
        emit Reroll(1);
        sheepy.reroll{value: _REROLL_PRICE}(DynamicArrayLib.p(1).asUint256Array());
        assertEq(address(_CHARLIE).balance, 100 ether - _REVEAL_PRICE - _REROLL_PRICE);

        vm.prank(_CHARLIE);
        sheepy.transfer(_BOB, _UNIT);
        assertEq(mirror.ownerOf(1), _BOB);
    }

    function testFreeReroll() public {
        _initialize();

        // Transfer some tokens to BOB
        vm.prank(_ALICE);
        sheepy.transfer(_BOB, _UNIT * 2);
        assertEq(mirror.balanceOf(_BOB), 2, "BOB should have 2 tokens");
        assertEq(mirror.ownerOf(1), _BOB, "Token 1 should be owned by BOB");
        assertEq(mirror.ownerOf(2), _BOB, "Token 2 should be owned by BOB");

        // Create signature for tokenIds [1,2]
        uint256[] memory tokenIds = DynamicArrayLib.malloc(2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        bytes32 hash = keccak256(abi.encode(tokenIds));

        // Sign the hash with BOB's private key (who has admin role)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_BOB_PRIVATE_KEY, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Test successful freeReroll with admin signature
        vm.expectEmit();
        emit Reroll(1);
        vm.expectEmit();
        emit Reroll(2);
        vm.prank(_BOB);
        sheepy.freeReroll(tokenIds, signature);

        // Test unauthorized signature
        // Sign with CHARLIE's private key (who doesn't have admin role)
        (v, r, s) = vm.sign(0x333, hash);
        signature = abi.encodePacked(r, s, v);
        vm.prank(_BOB);
        vm.expectRevert("Unauthorized.");
        sheepy.freeReroll(tokenIds, signature);

        // Test unauthorized caller
        // Transfer token 1 to CHARLIE
        vm.prank(_BOB);
        mirror.transferFrom(_BOB, _CHARLIE, 1);
        assertEq(mirror.ownerOf(1), _CHARLIE, "Token 1 should be owned by CHARLIE");

        // Sign with BOB's private key (admin)
        (v, r, s) = vm.sign(_BOB_PRIVATE_KEY, hash);
        signature = abi.encodePacked(r, s, v);

        // Try to reroll with CHARLIE's token using BOB's signature
        vm.prank(_CHARLIE);
        vm.expectRevert("Unauthorized.");
        sheepy.freeReroll(tokenIds, signature);

        // Test invalid signature format
        bytes memory invalidSignature = abi.encodePacked(r, s); // Missing v
        vm.prank(_BOB);
        vm.expectRevert();
        sheepy.freeReroll(tokenIds, invalidSignature);

        // Test empty tokenIds array
        uint256[] memory emptyTokenIds = DynamicArrayLib.malloc(0);
        hash = keccak256(abi.encode(emptyTokenIds));
        (v, r, s) = vm.sign(_BOB_PRIVATE_KEY, hash);
        signature = abi.encodePacked(r, s, v);
        vm.prank(_BOB);
        sheepy.freeReroll(emptyTokenIds, signature); // Should succeed but emit no events
    }

    function testFreeReveal() public {
        _initialize();

        // Transfer some tokens to BOB
        vm.prank(_ALICE);
        sheepy.transfer(_BOB, _UNIT * 2);
        assertEq(mirror.balanceOf(_BOB), 2, "BOB should have 2 tokens");
        assertEq(mirror.ownerOf(1), _BOB, "Token 1 should be owned by BOB");
        assertEq(mirror.ownerOf(2), _BOB, "Token 2 should be owned by BOB");

        // Create signature for tokenIds [1,2]
        uint256[] memory tokenIds = DynamicArrayLib.malloc(2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        bytes32 hash = keccak256(abi.encode(tokenIds));

        // Sign the hash with BOB's private key (who has admin role)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_BOB_PRIVATE_KEY, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Test successful freeReveal with admin signature
        vm.expectEmit();
        emit Reveal(1);
        vm.expectEmit();
        emit Reveal(2);
        vm.prank(_BOB);
        sheepy.freeReveal(tokenIds, signature);
        assertEq(_revealed(1), true, "Token 1 should be revealed");
        assertEq(_revealed(2), true, "Token 2 should be revealed");

        // Test unauthorized signature
        // Sign with CHARLIE's private key (who doesn't have admin role)
        (v, r, s) = vm.sign(0x333, hash);
        signature = abi.encodePacked(r, s, v);
        vm.prank(_BOB);
        vm.expectRevert("Unauthorized.");
        sheepy.freeReveal(tokenIds, signature);

        // Test unauthorized caller
        // Transfer token 1 to CHARLIE
        vm.prank(_BOB);
        mirror.transferFrom(_BOB, _CHARLIE, 1);
        assertEq(mirror.ownerOf(1), _CHARLIE, "Token 1 should be owned by CHARLIE");

        // Sign with BOB's private key (admin)
        (v, r, s) = vm.sign(_BOB_PRIVATE_KEY, hash);
        signature = abi.encodePacked(r, s, v);

        // Try to reveal with CHARLIE's token using BOB's signature
        vm.prank(_CHARLIE);
        vm.expectRevert("Unauthorized.");
        sheepy.freeReveal(tokenIds, signature);

        // Test invalid signature format
        bytes memory invalidSignature = abi.encodePacked(r, s); // Missing v
        vm.prank(_BOB);
        vm.expectRevert();
        sheepy.freeReveal(tokenIds, invalidSignature);

        // Test empty tokenIds array
        uint256[] memory emptyTokenIds = DynamicArrayLib.malloc(0);
        hash = keccak256(abi.encode(emptyTokenIds));
        (v, r, s) = vm.sign(_BOB_PRIVATE_KEY, hash);
        signature = abi.encodePacked(r, s, v);
        vm.prank(_BOB);
        sheepy.freeReveal(emptyTokenIds, signature); // Should succeed but emit no events
    }

    function _revealed(uint256 i) internal view returns (bool) {
        return sheepy.revealed(DynamicArrayLib.p(i).asUint256Array())[0];
    }
}
