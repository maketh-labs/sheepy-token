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
        Sheepy404 sheepy = new Sheepy404();
        Sheepy404Mirror mirror = new Sheepy404Mirror();
        SheepySale sale = new SheepySale();
        vm.stopBroadcast();
    }
}
