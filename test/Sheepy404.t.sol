// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "../src/Sheepy404.sol";
import "../src/SheepyBase.sol";
import "../src/Sheepy404Mirror.sol";
import "../src/SheepySale.sol";
import "solady/utils/DynamicArrayLib.sol";
import "solady/utils/ECDSA.sol";

contract Sheepy404Test is Test {
    using DynamicArrayLib for *;
    using ECDSA for bytes32;

    event Reveal(uint256 indexed tokenId);
    event Reroll(uint256 indexed tokenId);
    event Reset(uint256 indexed tokenId);
    event AssetCount(uint256 newAssetCount);
    event MetadataUpdate(uint256 _tokenId);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

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

    bytes32 private constant _FREE_REVEAL_TYPEHASH =
        0xcbb6b2caea63e26816b6962db016926cda6cb7d3a5d178e4f6d922786b13519a;
    bytes32 private constant _FREE_REROLL_TYPEHASH =
        0xab9e08c6dc1641c44003b1a2c1c5dea3cc27a6ce103778226c15c053a8ca9dae;

    function setUp() public {
        sheepy = new Sheepy404();
        mirror = new Sheepy404Mirror();
        sale = new SheepySale();
        (_BOB, _BOB_PRIVATE_KEY) = makeAddrAndKey("bob");

        // Mock LibAGW.isAGW to always return false globally
        vm.mockCall(
            0xd5E3efDA6bB5aB545cc2358796E96D9033496Dda,
            abi.encodeWithSignature("isAGW(address)"),
            abi.encode(false)
        );
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

        vm.prank(_ALICE);
        sale.setSale(1, address(sheepy), 1, 10000, uint96(0.03 ether), 10, 2, address(0));
    }

    function testSalePriceOf() public view {
        uint96 amount = uint96(_WAD / 50);
        uint96 pricePerWad = uint96(0.03 ether);
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

    function testTransferToAGW() public {
        _initialize();

        vm.mockCall(
            0xd5E3efDA6bB5aB545cc2358796E96D9033496Dda,
            abi.encodeWithSignature("isAGW(address)", address(this)),
            abi.encode(true)
        );

        vm.expectEmit();
        emit Reset(1);
        vm.prank(_ALICE);
        sheepy.transfer(address(this), _UNIT); // address(this) has code
        assertEq(mirror.balanceOf(address(this)), 1);
        assertEq(sheepy.balanceOf(address(this)), _UNIT);
        assertEq(mirror.totalSupply(), 1);
        assertEq(mirror.ownerOf(1), address(this));

        vm.mockCall(
            0xd5E3efDA6bB5aB545cc2358796E96D9033496Dda,
            abi.encodeWithSignature("isAGW(address)", address(this)),
            abi.encode(false)
        );

        vm.prank(_ALICE);
        sheepy.transfer(address(this), _UNIT);
        assertEq(mirror.ownerOf(1), address(this));
        assertEq(sheepy.balanceOf(address(this)), _UNIT * 2);
        assertEq(mirror.totalSupply(), 1); // NFT does not mint
    }

    function testFreeReroll() public {
        _initialize();

        // Transfer some tokens to BOB
        vm.prank(_ALICE);
        sheepy.transfer(_BOB, _UNIT * 2);
        assertEq(mirror.balanceOf(_BOB), 2, "BOB should have 2 tokens");
        assertEq(mirror.ownerOf(1), _BOB, "Token 1 should be owned by BOB");
        assertEq(mirror.ownerOf(2), _BOB, "Token 2 should be owned by BOB");

        // Create signature for tokenIds [1,2] with salt and deadline
        uint256[] memory tokenIds = DynamicArrayLib.malloc(2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        bytes32 salt = keccak256("test-salt-1");
        uint256 deadline = block.timestamp + 1 hours;

        // EIP-712 struct hash: keccak256(abi.encode(_FREE_REROLL_TYPEHASH, tokenIds, salt, deadline))
        bytes32 structHash = keccak256(abi.encode(_FREE_REROLL_TYPEHASH, tokenIds, salt, deadline));
        // EIP-712 domain separator: use sheepy.DOMAIN_SEPARATOR()
        bytes32 domainSeparator = sheepy.DOMAIN_SEPARATOR();
        // EIP-712 digest: keccak256("\x19\x01" || domainSeparator || structHash)
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        // Sign the digest with BOB's private key (who has admin role)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_BOB_PRIVATE_KEY, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Test successful freeReroll with admin signature
        vm.expectEmit();
        emit Reroll(1);
        vm.expectEmit();
        emit Reroll(2);
        vm.prank(_BOB);
        sheepy.freeReroll(tokenIds, salt, deadline, signature);

        // Test signature reuse (should fail)
        vm.prank(_BOB);
        vm.expectRevert(Sheepy404.SaltUsed.selector);
        sheepy.freeReroll(tokenIds, salt, deadline, signature);

        // Test unauthorized signature
        // Sign with CHARLIE's private key (who doesn't have admin role)
        vm.warp(block.timestamp + 1 hours);
        salt = keccak256("test-salt-2");
        deadline = block.timestamp + 1 hours;
        structHash = keccak256(abi.encode(_FREE_REROLL_TYPEHASH, tokenIds, salt, deadline));
        digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (v, r, s) = vm.sign(0x333, digest);
        bytes memory unauthorizedSignature = abi.encodePacked(r, s, v);

        vm.prank(_BOB);
        vm.expectRevert(Ownable.Unauthorized.selector);
        sheepy.freeReroll(tokenIds, salt, deadline, unauthorizedSignature);

        // Test unauthorized caller
        // Transfer token 1 to CHARLIE
        vm.prank(_BOB);
        mirror.transferFrom(_BOB, _CHARLIE, 1);
        assertEq(mirror.ownerOf(1), _CHARLIE, "Token 1 should be owned by CHARLIE");

        // Sign with BOB's private key (admin) for new salt and deadline
        salt = keccak256("test-salt-3");
        deadline = block.timestamp + 1 hours;
        structHash = keccak256(abi.encode(_FREE_REROLL_TYPEHASH, tokenIds, salt, deadline));
        digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (v, r, s) = vm.sign(_BOB_PRIVATE_KEY, digest);
        bytes memory newSignature = abi.encodePacked(r, s, v);

        // Try to reroll with CHARLIE's token using BOB's signature
        vm.prank(_CHARLIE);
        vm.expectRevert(Ownable.Unauthorized.selector);
        sheepy.freeReroll(tokenIds, salt, deadline, newSignature);

        // Test invalid signature format
        bytes memory invalidSignature = abi.encodePacked(r, s); // Missing v
        vm.prank(_BOB);
        vm.expectRevert();
        sheepy.freeReroll(tokenIds, salt, deadline, invalidSignature);

        // Test empty tokenIds array
        tokenIds = DynamicArrayLib.malloc(0);
        salt = keccak256("empty-test-salt");
        deadline = block.timestamp + 1 hours;
        structHash = keccak256(abi.encode(_FREE_REROLL_TYPEHASH, tokenIds, salt, deadline));
        digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (v, r, s) = vm.sign(_BOB_PRIVATE_KEY, digest);
        bytes memory emptySignature = abi.encodePacked(r, s, v);
        vm.prank(_BOB);
        sheepy.freeReroll(tokenIds, salt, deadline, emptySignature); // Should succeed but emit no events
    }

    function testFreeReveal() public {
        _initialize();

        // Transfer some tokens to BOB
        vm.prank(_ALICE);
        sheepy.transfer(_BOB, _UNIT * 2);
        assertEq(mirror.balanceOf(_BOB), 2, "BOB should have 2 tokens");
        assertEq(mirror.ownerOf(1), _BOB, "Token 1 should be owned by BOB");
        assertEq(mirror.ownerOf(2), _BOB, "Token 2 should be owned by BOB");

        // Create signature for tokenIds [1,2] with salt and deadline
        uint256[] memory tokenIds = DynamicArrayLib.malloc(2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        bytes32 salt = keccak256("reveal-test-salt-1");
        uint256 deadline = block.timestamp + 1 hours;

        // EIP-712 struct hash: keccak256(abi.encode(_FREE_REVEAL_TYPEHASH, tokenIds, salt, deadline))
        bytes32 structHash = keccak256(abi.encode(_FREE_REVEAL_TYPEHASH, tokenIds, salt, deadline));
        // EIP-712 domain separator: use sheepy.DOMAIN_SEPARATOR()
        bytes32 domainSeparator = sheepy.DOMAIN_SEPARATOR();
        // EIP-712 digest: keccak256("\x19\x01" || domainSeparator || structHash)
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        // Sign the digest with BOB's private key (who has admin role)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_BOB_PRIVATE_KEY, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Test successful freeReveal with admin signature
        vm.expectEmit();
        emit Reveal(1);
        vm.expectEmit();
        emit Reveal(2);
        vm.prank(_BOB);
        sheepy.freeReveal(tokenIds, salt, deadline, signature);
        assertEq(_revealed(1), true, "Token 1 should be revealed");
        assertEq(_revealed(2), true, "Token 2 should be revealed");

        // Test signature reuse (should fail)
        vm.prank(_BOB);
        vm.expectRevert(Sheepy404.SaltUsed.selector);
        sheepy.freeReveal(tokenIds, salt, deadline, signature);

        // Test unauthorized signature
        // Sign with CHARLIE's private key (who doesn't have admin role)
        vm.warp(block.timestamp + 1 hours);
        salt = keccak256("reveal-test-salt-2");
        deadline = block.timestamp + 1 hours;
        structHash = keccak256(abi.encode(_FREE_REVEAL_TYPEHASH, tokenIds, salt, deadline));
        digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (v, r, s) = vm.sign(0x333, digest);
        bytes memory unauthorizedSignature = abi.encodePacked(r, s, v);

        vm.prank(_BOB);
        vm.expectRevert(Ownable.Unauthorized.selector);
        sheepy.freeReveal(tokenIds, salt, deadline, unauthorizedSignature);

        // Test unauthorized caller
        // Transfer token 1 to CHARLIE
        vm.prank(_BOB);
        mirror.transferFrom(_BOB, _CHARLIE, 1);
        assertEq(mirror.ownerOf(1), _CHARLIE, "Token 1 should be owned by CHARLIE");

        // Sign with BOB's private key (admin) for new salt and deadline
        salt = keccak256("reveal-test-salt-3");
        deadline = block.timestamp + 1 hours;
        structHash = keccak256(abi.encode(_FREE_REVEAL_TYPEHASH, tokenIds, salt, deadline));
        digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (v, r, s) = vm.sign(_BOB_PRIVATE_KEY, digest);
        bytes memory newSignature = abi.encodePacked(r, s, v);

        // Try to reveal with CHARLIE's token using BOB's signature
        vm.prank(_CHARLIE);
        vm.expectRevert(Ownable.Unauthorized.selector);
        sheepy.freeReveal(tokenIds, salt, deadline, newSignature);

        // Test invalid signature format
        bytes memory invalidSignature = abi.encodePacked(r, s); // Missing v
        vm.prank(_BOB);
        vm.expectRevert();
        sheepy.freeReveal(tokenIds, salt, deadline, invalidSignature);

        // Test empty tokenIds array
        tokenIds = DynamicArrayLib.malloc(0);
        salt = keccak256("empty-reveal-test-salt");
        deadline = block.timestamp + 1 hours;
        structHash = keccak256(abi.encode(_FREE_REVEAL_TYPEHASH, tokenIds, salt, deadline));
        digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (v, r, s) = vm.sign(_BOB_PRIVATE_KEY, digest);
        bytes memory emptySignature = abi.encodePacked(r, s, v);
        vm.prank(_BOB);
        sheepy.freeReveal(tokenIds, salt, deadline, emptySignature); // Should succeed but emit no events
    }

    function testSetAssetCount() public {
        _initialize();

        uint256 initialMinAssetCount = _INITIAL_SUPPLY / _UNIT;

        // Test setting asset count by admin (BOB) to minimum allowed value
        vm.expectEmit();
        emit AssetCount(initialMinAssetCount);
        vm.prank(_BOB);
        sheepy.setAssetCount(initialMinAssetCount);

        // Test setting asset count by admin (BOB) to a higher value
        uint256 newAssetCount = initialMinAssetCount + 1000;
        vm.expectEmit();
        emit AssetCount(newAssetCount);
        vm.prank(_BOB);
        sheepy.setAssetCount(newAssetCount);

        // Test setting asset count by owner (ALICE)
        newAssetCount = initialMinAssetCount + 2000;
        vm.expectEmit();
        emit AssetCount(newAssetCount);
        vm.prank(_ALICE);
        sheepy.setAssetCount(newAssetCount);

        // Test unauthorized caller (CHARLIE)
        vm.prank(_CHARLIE);
        vm.expectRevert();
        sheepy.setAssetCount(initialMinAssetCount);

        // Test setting asset count below minimum
        vm.prank(_BOB);
        vm.expectRevert(Sheepy404.AssetCountTooSmall.selector);
        sheepy.setAssetCount(initialMinAssetCount - 1);

        // Test setting max uint256
        vm.expectEmit();
        emit AssetCount(type(uint256).max);
        vm.prank(_BOB);
        sheepy.setAssetCount(type(uint256).max);
    }

    function _revealed(uint256 i) internal view returns (bool) {
        return sheepy.revealed(DynamicArrayLib.p(i).asUint256Array())[0];
    }

    function testMetadataEvents() public {
        _initialize();

        // Transfer some tokens to BOB
        vm.prank(_ALICE);
        sheepy.transfer(_BOB, _UNIT * 2);

        // Test reveal emits MetadataUpdate
        vm.deal(_BOB, 100 ether);
        vm.prank(_BOB);
        vm.expectEmit();
        emit Reveal(1);
        vm.expectEmit(true, true, true, true, address(mirror));
        emit MetadataUpdate(1);
        sheepy.reveal{value: _REVEAL_PRICE}(DynamicArrayLib.p(1).asUint256Array());

        // Test reroll emits MetadataUpdate
        vm.prank(_BOB);
        vm.expectEmit();
        emit Reroll(1);
        vm.expectEmit(true, true, true, true, address(mirror));
        emit MetadataUpdate(1);
        sheepy.reroll{value: _REROLL_PRICE}(DynamicArrayLib.p(1).asUint256Array());

        // Test setBaseURI emits BatchMetadataUpdate
        vm.prank(_ALICE);
        vm.expectEmit(true, true, true, true, address(mirror));
        emit BatchMetadataUpdate(1, _INITIAL_SUPPLY / _UNIT);
        sheepy.setBaseURI("new-uri/{id}");
    }

    function testSupportsERC4906Interface() public {
        _initialize();

        // Test ERC-4906 interface support (hardcoded in the EIP)
        bytes4 ERC4906_INTERFACE_ID = 0x49064906;
        assertTrue(
            mirror.supportsInterface(ERC4906_INTERFACE_ID), "Should support ERC-4906 interface"
        );

        // Test that it still supports other required interfaces
        bytes4 ERC165_INTERFACE_ID = 0x01ffc9a7;
        bytes4 ERC721_INTERFACE_ID = 0x80ac58cd;
        bytes4 ERC721_METADATA_INTERFACE_ID = 0x5b5e139f;

        assertTrue(
            mirror.supportsInterface(ERC165_INTERFACE_ID), "Should support ERC-165 interface"
        );
        assertTrue(
            mirror.supportsInterface(ERC721_INTERFACE_ID), "Should support ERC-721 interface"
        );
        assertTrue(
            mirror.supportsInterface(ERC721_METADATA_INTERFACE_ID),
            "Should support ERC-721 Metadata interface"
        );

        // Test random interface ID is not supported
        assertFalse(mirror.supportsInterface(0xffffffff), "Should not support random interface");
    }

    function testAirdropClaim() public {
        _initialize();

        // Setup airdrop sale with price = 0
        vm.prank(_ALICE);
        sale.setSale(
            1,
            address(sheepy),
            1,
            uint40(block.timestamp + 1000),
            0, // Free airdrop
            uint96(1000 * _WAD),
            uint96(100 * _WAD),
            _BOB // BOB will sign the claims
        );

        // Fund the sale contract with tokens
        vm.prank(_ALICE);
        sheepy.transfer(address(sale), 1000 * _WAD);

        // Create signature for CHARLIE to claim 50 tokens
        uint96 claimAmount = uint96(50 * _WAD);
        uint96 customQuota = uint96(100 * _WAD);
        bytes32 hash = keccak256("SheepySale");
        hash = keccak256(abi.encode(hash, uint256(1), _CHARLIE, customQuota));
        hash = hash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_BOB_PRIVATE_KEY, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Test successful claim
        uint256 charlieBalanceBefore = sheepy.balanceOf(_CHARLIE);
        vm.prank(_CHARLIE);
        sale.buy(1, _CHARLIE, claimAmount, customQuota, signature);
        assertEq(sheepy.balanceOf(_CHARLIE), charlieBalanceBefore + claimAmount);
        assertEq(sale.bought(1, _CHARLIE), claimAmount);

        // Test multiple claims with same signature (should work until quota hit)
        vm.prank(_CHARLIE);
        sale.buy(1, _CHARLIE, claimAmount, customQuota, signature);
        assertEq(sheepy.balanceOf(_CHARLIE), charlieBalanceBefore + claimAmount * 2);
        assertEq(sale.bought(1, _CHARLIE), claimAmount * 2);

        // Test quota exceeded
        vm.prank(_CHARLIE);
        vm.expectRevert(SheepySale.ExceededAddressQuota.selector);
        sale.buy(1, _CHARLIE, claimAmount, customQuota, signature);
    }

    function testAirdropClaimWithInvalidSignature() public {
        _initialize();

        // Setup airdrop sale
        vm.prank(_ALICE);
        sale.setSale(
            1,
            address(sheepy),
            1,
            uint40(block.timestamp + 1000),
            0,
            uint96(1000 * _WAD),
            uint96(100 * _WAD),
            _BOB
        );

        vm.prank(_ALICE);
        sheepy.transfer(address(sale), 1000 * _WAD);

        uint96 claimAmount = uint96(50 * _WAD);
        uint96 customQuota = uint96(100 * _WAD);

        // Test with wrong signer (CHARLIE instead of BOB)
        bytes32 hash = keccak256("SheepySale");
        hash = keccak256(abi.encode(hash, uint256(1), _CHARLIE, customQuota));
        hash = hash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x333, hash);
        bytes memory wrongSignature = abi.encodePacked(r, s, v);

        vm.prank(_CHARLIE);
        vm.expectRevert(SheepySale.InvalidSignature.selector);
        sale.buy(1, _CHARLIE, claimAmount, customQuota, wrongSignature);

        // Test signature for different user
        hash = keccak256("SheepySale");
        hash = keccak256(abi.encode(hash, uint256(1), _DAVID, customQuota));
        hash = hash.toEthSignedMessageHash();
        (v, r, s) = vm.sign(_BOB_PRIVATE_KEY, hash);
        bytes memory davidSignature = abi.encodePacked(r, s, v);

        vm.prank(_CHARLIE); // CHARLIE tries to use DAVID's signature
        vm.expectRevert(SheepySale.InvalidSignature.selector);
        sale.buy(1, _CHARLIE, claimAmount, customQuota, davidSignature);
    }

    function testAirdropClaimQuotaLimits() public {
        _initialize();

        // Setup airdrop with small quotas
        vm.prank(_ALICE);
        sale.setSale(
            1,
            address(sheepy),
            1,
            uint40(block.timestamp + 1000),
            0,
            uint96(150 * _WAD), // Total quota smaller than address quota
            uint96(200 * _WAD),
            _BOB
        );

        vm.prank(_ALICE);
        sheepy.transfer(address(sale), 1000 * _WAD);

        uint96 claimAmount = uint96(100 * _WAD);
        uint96 customQuota = uint96(200 * _WAD);

        // CHARLIE claims first
        bytes32 hash = keccak256("SheepySale");
        hash = keccak256(abi.encode(hash, uint256(1), _CHARLIE, customQuota));
        hash = hash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_BOB_PRIVATE_KEY, hash);
        bytes memory charlieSignature = abi.encodePacked(r, s, v);

        vm.prank(_CHARLIE);
        sale.buy(1, _CHARLIE, claimAmount, customQuota, charlieSignature);

        // DAVID tries to claim but exceeds total quota
        hash = keccak256("SheepySale");
        hash = keccak256(abi.encode(hash, uint256(1), _DAVID, customQuota));
        hash = hash.toEthSignedMessageHash();
        (v, r, s) = vm.sign(_BOB_PRIVATE_KEY, hash);
        bytes memory davidSignature = abi.encodePacked(r, s, v);

        vm.prank(_DAVID);
        vm.expectRevert(SheepySale.ExceededTotalQuota.selector);
        sale.buy(1, _DAVID, claimAmount, customQuota, davidSignature);
    }

    function testAirdropClaimTimeBounds() public {
        _initialize();

        // Setup airdrop with time bounds
        vm.prank(_ALICE);
        sale.setSale(
            1,
            address(sheepy),
            uint40(block.timestamp + 100),
            uint40(block.timestamp + 200),
            0,
            uint96(1000 * _WAD),
            uint96(100 * _WAD),
            _BOB
        );

        vm.prank(_ALICE);
        sheepy.transfer(address(sale), 1000 * _WAD);

        uint96 claimAmount = uint96(50 * _WAD);
        uint96 customQuota = uint96(100 * _WAD);
        bytes32 hash = keccak256("SheepySale");
        hash = keccak256(abi.encode(hash, uint256(1), _CHARLIE, customQuota));
        hash = hash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_BOB_PRIVATE_KEY, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Test claim before start time
        vm.prank(_CHARLIE);
        vm.expectRevert(SheepySale.SaleNotOpen.selector);
        sale.buy(1, _CHARLIE, claimAmount, customQuota, signature);

        // Test claim during valid time
        vm.warp(block.timestamp + 150);
        vm.prank(_CHARLIE);
        sale.buy(1, _CHARLIE, claimAmount, customQuota, signature);
        assertEq(sheepy.balanceOf(_CHARLIE), claimAmount);

        // Test claim after end time
        vm.warp(block.timestamp + 100);
        vm.prank(_CHARLIE);
        vm.expectRevert(SheepySale.SaleNotOpen.selector);
        sale.buy(1, _CHARLIE, claimAmount, customQuota, signature);
    }

    function testSignatureReplayProtection() public {
        _initialize();

        // Transfer some tokens to BOB
        vm.prank(_ALICE);
        sheepy.transfer(_BOB, _UNIT * 3);

        uint256[] memory tokenIds = DynamicArrayLib.malloc(3);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        tokenIds[2] = 3;
        uint256 deadline = block.timestamp + 1 hours;

        // Test that same salt can be used for both reveal and reroll (different typeHashes)
        bytes32 commonSalt1 = keccak256("common-test-salt1");
        bytes32 commonSalt2 = keccak256("common-test-salt2");
        bytes32 revealStructHash =
            keccak256(abi.encode(_FREE_REVEAL_TYPEHASH, tokenIds, commonSalt1, deadline));
        bytes32 rerollStructHash =
            keccak256(abi.encode(_FREE_REROLL_TYPEHASH, tokenIds, commonSalt2, deadline));
        bytes32 domainSeparator = sheepy.DOMAIN_SEPARATOR();

        bytes32 revealDigest =
            keccak256(abi.encodePacked("\x19\x01", domainSeparator, revealStructHash));
        bytes32 rerollDigest =
            keccak256(abi.encodePacked("\x19\x01", domainSeparator, rerollStructHash));

        bytes memory revealSignature;
        bytes memory rerollSignature;
        {
            (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(_BOB_PRIVATE_KEY, revealDigest);
            (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(_BOB_PRIVATE_KEY, rerollDigest);
            revealSignature = abi.encodePacked(r1, s1, v1);
            rerollSignature = abi.encodePacked(r2, s2, v2);
        }

        // Use reveal signature
        vm.prank(_BOB);
        sheepy.freeReveal(tokenIds, commonSalt1, deadline, revealSignature);

        // Use reroll signature (should work because it's different typehash)
        vm.prank(_BOB);
        sheepy.freeReroll(tokenIds, commonSalt2, deadline, rerollSignature);

        // Try to reuse reveal signature (should fail)
        vm.prank(_BOB);
        vm.expectRevert(Sheepy404.SaltUsed.selector);
        sheepy.freeReveal(tokenIds, commonSalt1, deadline, revealSignature);

        // Try to reuse reroll signature (should fail)
        vm.prank(_BOB);
        vm.expectRevert(Sheepy404.SaltUsed.selector);
        sheepy.freeReroll(tokenIds, commonSalt2, deadline, rerollSignature);
    }

    function testSaltDifferentiation() public {
        _initialize();

        // Transfer some tokens to BOB
        vm.prank(_ALICE);
        sheepy.transfer(_BOB, _UNIT * 2);

        uint256[] memory tokenIds = DynamicArrayLib.malloc(2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        // Test reveal with first salt
        bytes32 salt1 = keccak256("test-salt-1");
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 structHash = keccak256(abi.encode(_FREE_REVEAL_TYPEHASH, tokenIds, salt1, deadline));
        bytes32 domainSeparator = sheepy.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_BOB_PRIVATE_KEY, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(_BOB);
        sheepy.freeReveal(tokenIds, salt1, deadline, signature);

        // Test reroll with different salt (should work)
        bytes32 salt2 = keccak256("test-salt-2");
        structHash = keccak256(abi.encode(_FREE_REROLL_TYPEHASH, tokenIds, salt2, deadline));
        digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (v, r, s) = vm.sign(_BOB_PRIVATE_KEY, digest);
        signature = abi.encodePacked(r, s, v);

        vm.prank(_BOB);
        sheepy.freeReroll(tokenIds, salt2, deadline, signature);

        // Test using same salt with same action type (should fail)
        structHash = keccak256(abi.encode(_FREE_REVEAL_TYPEHASH, tokenIds, salt1, deadline));
        digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (v, r, s) = vm.sign(_BOB_PRIVATE_KEY, digest);
        signature = abi.encodePacked(r, s, v);

        vm.prank(_BOB);
        vm.expectRevert(Sheepy404.SaltUsed.selector);
        sheepy.freeReveal(tokenIds, salt1, deadline, signature);
    }

    function testDeadlineExpiration() public {
        _initialize();

        // Transfer some tokens to BOB
        vm.prank(_ALICE);
        sheepy.transfer(_BOB, _UNIT * 2);

        uint256[] memory tokenIds = DynamicArrayLib.malloc(2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        // Test reveal with future deadline (should work)
        bytes32 salt = keccak256("deadline-test-salt");
        uint256 futureDeadline = block.timestamp + 1 hours;
        bytes32 structHash =
            keccak256(abi.encode(_FREE_REVEAL_TYPEHASH, tokenIds, salt, futureDeadline));
        bytes32 domainSeparator = sheepy.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_BOB_PRIVATE_KEY, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(_BOB);
        sheepy.freeReveal(tokenIds, salt, futureDeadline, signature);

        // Test reroll with current timestamp as deadline (should work)
        bytes32 salt2 = keccak256("deadline-test-salt-2");
        uint256 currentDeadline = block.timestamp;
        structHash = keccak256(abi.encode(_FREE_REROLL_TYPEHASH, tokenIds, salt2, currentDeadline));
        digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (v, r, s) = vm.sign(_BOB_PRIVATE_KEY, digest);
        signature = abi.encodePacked(r, s, v);

        vm.prank(_BOB);
        sheepy.freeReroll(tokenIds, salt2, currentDeadline, signature);

        // Advance time and test expired deadline
        vm.warp(block.timestamp + 2 hours);

        bytes32 salt3 = keccak256("deadline-test-salt-3");
        uint256 expiredDeadline = block.timestamp - 1 hours;
        structHash = keccak256(abi.encode(_FREE_REVEAL_TYPEHASH, tokenIds, salt3, expiredDeadline));
        digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (v, r, s) = vm.sign(_BOB_PRIVATE_KEY, digest);
        signature = abi.encodePacked(r, s, v);

        vm.prank(_BOB);
        vm.expectRevert(Sheepy404.SignatureExpired.selector);
        sheepy.freeReveal(tokenIds, salt3, expiredDeadline, signature);
    }

    function testAirdropWithCustomQuota() public {
        _initialize();

        // Setup airdrop
        vm.prank(_ALICE);
        sale.setSale(
            1,
            address(sheepy),
            1,
            uint40(block.timestamp + 1000),
            0,
            uint96(1000 * _WAD),
            uint96(50 * _WAD), // Default quota is 50
            _BOB
        );

        vm.prank(_ALICE);
        sheepy.transfer(address(sale), 1000 * _WAD);

        // CHARLIE gets custom quota of 100 (higher than default)
        // But effective quota is min(100, 50) = 50
        uint96 charlieCustomQuota = uint96(100 * _WAD);
        bytes32 hash = keccak256("SheepySale");
        hash = keccak256(abi.encode(hash, uint256(1), _CHARLIE, charlieCustomQuota));
        hash = hash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_BOB_PRIVATE_KEY, hash);
        bytes memory charlieSignature = abi.encodePacked(r, s, v);

        // Should succeed because claim amount (45) is within effective quota of min(100, 50) = 50
        vm.prank(_CHARLIE);
        sale.buy(1, _CHARLIE, uint96(45 * _WAD), charlieCustomQuota, charlieSignature);
        assertEq(sheepy.balanceOf(_CHARLIE), 45 * _WAD);

        // CHARLIE tries to claim 10 more (total would be 55), should fail because effective quota is 50
        vm.prank(_CHARLIE);
        vm.expectRevert(SheepySale.ExceededAddressQuota.selector);
        sale.buy(1, _CHARLIE, uint96(10 * _WAD), charlieCustomQuota, charlieSignature);

        // DAVID gets custom quota of 30 (lower than default)
        // Effective quota is min(30, 50) = 30
        uint96 davidCustomQuota = uint96(30 * _WAD);
        hash = keccak256("SheepySale");
        hash = keccak256(abi.encode(hash, uint256(1), _DAVID, davidCustomQuota));
        hash = hash.toEthSignedMessageHash();
        (v, r, s) = vm.sign(_BOB_PRIVATE_KEY, hash);
        bytes memory davidSignature = abi.encodePacked(r, s, v);

        // Should succeed when claiming within custom quota (30)
        vm.prank(_DAVID);
        sale.buy(1, _DAVID, uint96(25 * _WAD), davidCustomQuota, davidSignature);
        assertEq(sheepy.balanceOf(_DAVID), 25 * _WAD);

        // DAVID tries to claim 10 more (total would be 35), should fail because custom quota is 30
        vm.prank(_DAVID);
        vm.expectRevert(SheepySale.ExceededAddressQuota.selector);
        sale.buy(1, _DAVID, uint96(10 * _WAD), davidCustomQuota, davidSignature);
    }
}
