## Requirements

ZKsync Foundry.

https://foundry-book.zksync.io/

## Setup

There are three deployed contracts, and you'll need to setup those with `initialize` functions.

- Sheepy404 (the ERC20)
https://sepolia.abscan.org/address/0x9C0773Ed02EC78d38408ca8b8E478280B07ddb43

```solidity
function initialize(
    address initialOwner,
    address initialAdmin,
    address mirror,
    string memory notSoSecret
)
```

- Sheepy404Mirror (the ERC721 counterpart)
https://sepolia.abscan.org/address/0x0056DF5136D53dE52014Fe303c43a92cdA5D0377

- SheepySale (the Sale contract)
https://sepolia.abscan.org/address/0x39D25887C6EEEef56345954b7E71e06826B35795

```solidity
function initialize(
    address initialOwner,
    address initialAdmin,
    string memory notSoSecret
)
```

Here, `notSoSecret` is `SomethingSomethingNoGrief`.
