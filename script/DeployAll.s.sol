// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Script} from "forge-std/Script.sol";
import "../src/Sheepy404.sol";
import "../src/Sheepy404Mirror.sol";
import "../src/SheepySale.sol";

contract DeployAllScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        bytes32 salt = keccak256(abi.encode(block.timestamp, "hehe"));
        new Sheepy404{salt: salt}();
        new Sheepy404Mirror{salt: salt}();
        new SheepySale{salt: salt}();
        vm.stopBroadcast();
    }
}
