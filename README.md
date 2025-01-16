## Requirements

ZKsync Foundry.

https://foundry-book.zksync.io/

## Setup

There are three deployed contracts, and you'll need to setup those with `initialize` functions.

- Sheepy404 (the ERC20)
https://sepolia.abscan.org/address/0xE23e9c4f270696C5E9E8A40bDa0039F2e9959FeF

```solidity
function initialize(
    address initialOwner,
    address initialAdmin,
    address mirror,
    string memory notSoSecret
)
```

- Sheepy404Mirror (the ERC721 counterpart)
https://sepolia.abscan.org/address/0x2422E18402655c7Ad30e519E06c7890BAd5122CE

- SheepySale (the Sale contract)
https://sepolia.abscan.org/address/0x0E0C950389aE0588Fb940058D51493De7ED69D9a

```solidity
function initialize(
    address initialOwner,
    address initialAdmin,
    string memory notSoSecret
)
```

Here, `notSoSecret` is `SomethingSomethingNoGrief`.

## Setting up the Sale Schedules

