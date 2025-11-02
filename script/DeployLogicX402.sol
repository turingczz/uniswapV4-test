// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Script } from "lib/forge-std/src/Script.sol";
import { console } from "forge-std/console.sol";
import { X402Launchpad } from "../src/X402Launchpad.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        X402Launchpad imp = new X402Launchpad();

        vm.stopBroadcast();

        console.log("logic deployed to:", address(imp));
    }
}

/* 部署命令:
forge script script/DeployLogicX402.sol:DeployScript \
    --rpc-url=sepolia \
    --broadcast \
    --legacy

forge script script/DeployLogicX402.sol:DeployScript \
    --rpc-url=base \
    --broadcast \
    --legacy --verify

*/
