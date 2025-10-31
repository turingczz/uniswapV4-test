// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Script } from "lib/forge-std/src/Script.sol";
import { console } from "forge-std/console.sol";
import {Ping} from "../src/Ping-2.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        Ping imp = new Ping();

        vm.stopBroadcast();

        console.log("logic deployed to:", address(imp));
    }
}

/* 部署命令:
forge script script/DeployLogic.sol:DeployScript \
    --rpc-url=merlin_testnet \
    --broadcast \
    --legacy --verify

forge script script/DeployLogic.sol:DeployScript \
    --rpc-url=merlin_mainnet \
    --broadcast \
    --legacy --verify


*/
