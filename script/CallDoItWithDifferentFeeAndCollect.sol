// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Script } from "lib/forge-std/src/Script.sol";
import { console } from "forge-std/console.sol";
import {Ping} from "../src/v4.sol";

/**
 * @title CallDoItWithDifferentFeeAndCollectScript
 * @notice 调用已部署的Ping合约的doItWithDifferentFee和collectLpFees函数
 * @dev 需要设置以下环境变量：
 * - CONTRACT_ADDRESS: 已部署的Ping合约地址
 * - PRIVATE_KEY: 调用者的私钥（需要有MINTER_ROLE和DEFAULT_ADMIN_ROLE角色）
 */
contract CallDoItWithDifferentFeeAndCollectScript is Script {
    
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
        
        // 检查调用者角色
        bytes32 MINTER_ROLE = keccak256("MINTER_ROLE");
        bytes32 DEFAULT_ADMIN_ROLE = pingContract.DEFAULT_ADMIN_ROLE();
        
        bool hasMinterRole = pingContract.hasRole(MINTER_ROLE, callerAddress);
        bool hasAdminRole = pingContract.hasRole(DEFAULT_ADMIN_ROLE, callerAddress);
        
        console.log("Caller has MINTER_ROLE:", hasMinterRole);
        console.log("Caller has DEFAULT_ADMIN_ROLE:", hasAdminRole);
        
        require(hasMinterRole, "Caller does not have MINTER_ROLE");
        require(hasAdminRole, "Caller does not have DEFAULT_ADMIN_ROLE");

        // 开始广播交易
        vm.startBroadcast(callerPrivateKey);
        
        // 第一步：调用doItWithDifferentFee函数
        console.log("\n=== Step 1: Calling doItWithDifferentFee() ===");
        try pingContract.doItWithDifferentFee() {
            console.log("doItWithDifferentFee() function called successfully!");
        } catch Error(string memory reason) {
            console.log("Error calling doItWithDifferentFee(): ", reason);
            revert(reason);
        } catch (bytes memory) {
            console.log("Unknown error calling doItWithDifferentFee()");
            revert("Unknown error occurred");
        }
        
        // 等待一段时间让交易确认（可选）
        // vm.warp(block.timestamp + 60); // 增加60秒
        
        // 第二步：调用collectLpFees函数
        console.log("\n=== Step 2: Calling collectLpFees() ===");
        try pingContract.collectLpFees() {
            console.log("collectLpFees() function called successfully!");
        } catch Error(string memory reason) {
            console.log("Error calling collectLpFees(): ", reason);
            revert(reason);
        } catch (bytes memory) {
            console.log("Unknown error calling collectLpFees()");
            revert("Unknown error occurred");
        }
        
        vm.stopBroadcast();
        
        console.log("\n=== Script completed successfully! ===");
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
     * @notice 检查调用者是否有DEFAULT_ADMIN_ROLE
     * @param contractAddress 合约地址
     * @param callerAddress 调用者地址
     */
    function checkAdminRole(address contractAddress, address callerAddress) public view returns (bool) {
        Ping pingContract = Ping(contractAddress);
        bytes32 DEFAULT_ADMIN_ROLE = pingContract.DEFAULT_ADMIN_ROLE();
        return pingContract.hasRole(DEFAULT_ADMIN_ROLE, callerAddress);
    }
}

/* 
部署命令:
forge script script/CallDoItWithDifferentFeeAndCollect.sol:CallDoItWithDifferentFeeAndCollectScript \
    --rpc-url=sepolia \
    --broadcast \
    --legacy

环境变量设置:
export CONTRACT_ADDRESS=0x...  # 已部署的Ping合约地址
export PRIVATE_KEY=0x...     # 调用者私钥（需要有MINTER_ROLE和DEFAULT_ADMIN_ROLE角色）

注意：
1. 调用者需要有MINTER_ROLE来执行doItWithDifferentFee函数
2. 调用者需要有DEFAULT_ADMIN_ROLE来执行collectLpFees函数
3. 如果流动性已经部署，doItWithDifferentFee可能会失败
4. 如果流动性未部署，collectLpFees可能会失败
*/