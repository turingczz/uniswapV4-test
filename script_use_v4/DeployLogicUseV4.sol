// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Script } from "lib/forge-std/src/Script.sol";
import { console } from "forge-std/console.sol";
import { UseV4 } from "../script_v4/UseV4.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        UseV4 imp = new UseV4();
        
        vm.stopBroadcast();

        console.log("UseV4 logic deployed to:", address(imp));
    }
}

/* 部署命令:
forge script script/DeployLogicUseV4.sol:DeployScript \
    --rpc-url=sepolia \
    --broadcast \
    --legacy

forge script script/DeployLogicUseV4.sol:DeployScript \
    --rpc-url=base \
    --broadcast \
    --legacy --verify

*/
