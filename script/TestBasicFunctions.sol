// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Script } from "lib/forge-std/src/Script.sol";
import { console } from "forge-std/console.sol";
import {Ping} from "../src/v4.sol";

/**
 * @title TestBasicFunctionsScript
 * @notice 测试Ping合约的基本功能，不涉及Uniswap v4初始化
 * @dev 测试角色分配、状态查询等基本功能
 */
contract TestBasicFunctionsScript is Script {
    
    function run() external {
        // 从环境变量获取合约地址
        address contractAddress = vm.envAddress("CONTRACT_ADDRESS");
        
        // 获取调用者私钥
        uint256 callerPrivateKey = vm.envUint("PRIVATE_KEY");
        address callerAddress = vm.addr(callerPrivateKey);
        
        console.log("Contract address:", contractAddress);
        console.log("Caller address:", callerAddress);
        
        // 创建合约实例
        Ping pingContract = Ping(contractAddress);
        
        // 测试基本状态查询
        console.log("\n=== Testing Basic Functions ===");
        
        // 检查调用者角色
        bytes32 MINTER_ROLE = keccak256("MINTER_ROLE");
        bytes32 DEFAULT_ADMIN_ROLE = pingContract.DEFAULT_ADMIN_ROLE();
        
        bool hasMinterRole = pingContract.hasRole(MINTER_ROLE, callerAddress);
        bool hasAdminRole = pingContract.hasRole(DEFAULT_ADMIN_ROLE, callerAddress);
        
        console.log("Caller has MINTER_ROLE:", hasMinterRole);
        console.log("Caller has DEFAULT_ADMIN_ROLE:", hasAdminRole);
        
        // 检查流动性部署状态
        bool liquidityDeployed = pingContract.isLiquidityDeployed();
        console.log("Liquidity deployed:", liquidityDeployed);
        
        // 获取LP Token ID
        uint256 tokenId = pingContract.getLpTokenId();
        console.log("LP Token ID:", tokenId);
        
        // 测试常量值
        console.log("\n=== Testing Constants ===");
        console.log("PAYMENT_TOKEN:", pingContract.PAYMENT_TOKEN());
        console.log("NEW_TOKEN:", pingContract.NEW_TOKEN());
        console.log("PAYMENT_SEED:", pingContract.PAYMENT_SEED());
        console.log("POOL_SEED_AMOUNT:", pingContract.POOL_SEED_AMOUNT());
        
        // 测试简单的函数调用（不涉及Uniswap v4）
        console.log("\n=== Testing Simple Function Calls ===");
        
        // 测试角色授予（如果需要）
        if (!hasMinterRole || !hasAdminRole) {
            console.log("Granting roles to caller...");
            vm.startBroadcast(callerPrivateKey);
            
            if (!hasMinterRole) {
                // 注意：只有DEFAULT_ADMIN_ROLE才能授予角色
                // 这里需要确保调用者有DEFAULT_ADMIN_ROLE
                pingContract.grantRole(MINTER_ROLE, callerAddress);
                console.log("MINTER_ROLE granted to caller");
            }
            
            vm.stopBroadcast();
        }
        
        console.log("\n=== Test Completed Successfully! ===");
    }
    
    /**
     * @notice 测试合约的只读函数
     */
    function testReadOnlyFunctions(address contractAddress) public view {
        Ping pingContract = Ping(contractAddress);
        
        // 测试所有只读函数
        console.log("Testing read-only functions...");
        
        // 常量
        console.log("PAYMENT_TOKEN:", pingContract.PAYMENT_TOKEN());
        console.log("NEW_TOKEN:", pingContract.NEW_TOKEN());
        console.log("PAYMENT_SEED:", pingContract.PAYMENT_SEED());
        console.log("POOL_SEED_AMOUNT:", pingContract.POOL_SEED_AMOUNT());
        
        // 状态变量
        console.log("LP Token ID:", pingContract.getLpTokenId());
        console.log("Liquidity Deployed:", pingContract.isLiquidityDeployed());
    }
}

/* 
测试命令:
forge script script/TestBasicFunctions.sol:TestBasicFunctionsScript \
    --rpc-url=sepolia \
    --legacy

环境变量设置:
export CONTRACT_ADDRESS=0xfb1e83658CC65d278a08BF449a4AFf0E89008B93
export PRIVATE_KEY=0xf6ba0bbff94e3b7cdbe1d876128d6b4495346b110e4e83987823aa5973a12e31

注意：这个脚本只测试基本功能，不涉及Uniswap v4初始化
*/