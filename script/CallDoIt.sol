// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Script } from "lib/forge-std/src/Script.sol";
import { console } from "forge-std/console.sol";
import {Ping} from "../src/v4.sol";

/**
 * @title CallDoItScript
 * @notice 调用已部署的Ping合约的doIt函数
 * @dev 需要设置以下环境变量：
 * - CONTRACT_ADDRESS: 已部署的Ping合约地址
 * - PRIVATE_KEY: 调用者的私钥（需要有MINTER_ROLE角色）
 */
contract CallDoItScript is Script {
    
    function run() external {
        // 从环境变量获取合约地址
        address contractAddress = vm.envAddress("CONTRACT_ADDRESS");
        
        // 获取调用者私钥
        uint256 callerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("Contract address:", contractAddress);
        console.log("Caller address:", vm.addr(callerPrivateKey));
        
        // 创建合约实例
        Ping pingContract = Ping(contractAddress);
        
        // 开始广播交易
        vm.startBroadcast(callerPrivateKey);
        
        // 调用doIt函数
        pingContract.doIt();
        
        vm.stopBroadcast();
        
        console.log("doIt() function called successfully!");
    }
    
    /**
     * @notice 检查调用者是否有MINTER_ROLE
     * @param contractAddress 合约地址
     * @param callerAddress 调用者地址
     */
    function checkMinterRole(address contractAddress, address callerAddress) public view returns (bool) {
        Ping pingContract = Ping(contractAddress);
        bytes32 MINTER_ROLE = keccak256("MINTER_ROLE");
        return pingContract.hasRole(MINTER_ROLE, callerAddress);
    }
    
    /**
     * @notice 获取合约的LP token ID
     * @param contractAddress 合约地址
     */
    function getLpTokenId(address contractAddress) public view returns (uint256 tokenId) {
        Ping pingContract = Ping(contractAddress);
        tokenId = pingContract.getLpTokenId();
    }
    
    /**
     * @notice 检查流动性是否已部署
     * @param contractAddress 合约地址
     */
    function isLiquidityDeployed(address contractAddress) public view returns (bool) {
        Ping pingContract = Ping(contractAddress);
        return pingContract.isLiquidityDeployed();
    }
}


/* 部署命令:
forge script script/CallDoIt.sol:CallDoItScript \
    --rpc-url=sepolia \
    --broadcast \
    --legacy

*/