// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Script } from "lib/forge-std/src/Script.sol";
import { console } from "forge-std/console.sol";
import {Ping} from "../src/v4.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

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
