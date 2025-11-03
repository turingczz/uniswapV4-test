// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Script } from "lib/forge-std/src/Script.sol";
import { console } from "forge-std/console.sol";
import { X402Launchpad } from "../src/X402Launchpad.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        //sepolia uniswapV4 合约地址
        address poolManger = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
        address positionManger = 0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4;
        address  permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        X402Launchpad imp = new X402Launchpad(poolManger, positionManger, permit2);

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
