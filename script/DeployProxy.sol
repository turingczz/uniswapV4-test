// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { X402Launchpad } from "../src/X402Launchpad.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployProxy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        //sepolia uniswapV4 合约地址
        address poolManger = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
        address positionManger = 0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4;
        address  permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

        // 1. deploy implementation contract
        X402Launchpad implementation = new X402Launchpad(poolManger, positionManger, permit2);

        // 2. prepare init data
        bytes memory initData = abi.encodeWithSelector(
            X402Launchpad.initialize.selector,
            vm.addr(deployerPrivateKey) // admin
        );

        // 3. deploy proxy contract with the implementation address and init data
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        vm.stopBroadcast();

        console.log("Implementation deployed to:", address(implementation));
        console.log("Proxy deployed to:", address(proxy));
    }
}


/* 部署命令:
//testnet
forge script script/DeployProxy.sol:DeployProxy \
    --rpc-url=sepolia \
    --broadcast \
    --legacy

//prod
forge script script/DeployProxy.sol:DeployProxy \
    --rpc-url=merlin_mainnet \
    --broadcast \
    --legacy --verify

*/