// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { X402Launchpad } from "../src/X402Launchpad.sol";

contract Upgrade is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address payable proxyAddress = payable(vm.envAddress("PROXY_ADDRESS"));

        vm.startBroadcast(deployerPrivateKey);

        //sepolia uniswapV4 合约地址
        address poolManger = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
        address positionManger = 0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4;
        address  permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

        // 1. deploy new implementation contract
        X402Launchpad newImplementation = new X402Launchpad(poolManger, positionManger, permit2);

        // 2. upgrade proxy
        X402Launchpad proxy = X402Launchpad(proxyAddress);
        proxy.upgradeToAndCall(address(newImplementation), "");

        vm.stopBroadcast();

        console.log("New implementation deployed to:", address(newImplementation));
        console.log("Proxy upgraded successfully");
    }
}

/* 部署命令:
forge script script/Upgrade.sol:Upgrade \
    --rpc-url=sepolia \
    --broadcast \
    --legacy

*/
