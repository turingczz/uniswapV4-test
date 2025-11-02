// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Script } from "lib/forge-std/src/Script.sol";
import { console } from "forge-std/console.sol";
import { Ping } from "../src-other-app/V4.sol";

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
forge script script/DeployLogicV4-2.sol:DeployScript \
    --rpc-url=sepolia \
    --broadcast \
    --legacy

forge script script/DeployLogicV4.sol:DeployScript \
    --rpc-url=base \
    --broadcast \
    --legacy --verify

*/
