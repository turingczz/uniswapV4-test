// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {X402Launchpad} from "../../src/X402Launchpad.sol";

/*
X402Launchpad 合约调用流程

# 1. 初始化合约配置
forge script script/do/CallX402Launchpad.s.sol:CallX402Launchpad \
--sig "step1_InitConfig()" \
--rpc-url sepolia \
--broadcast \
--legacy

# 2. 部署新代币
forge script script/do/CallX402Launchpad.s.sol:CallX402Launchpad \
--sig "step2_DeployToken()" \
--rpc-url sepolia \
--broadcast \
--legacy

# 3. 添加流动性
forge script script/do/CallX402Launchpad.s.sol:CallX402Launchpad \
--sig "step3_AddLiquidity()" \
--rpc-url sepolia \
--broadcast \
--legacy

# 4. 批量空投
forge script script/do/CallX402Launchpad.s.sol:CallX402Launchpad \
--sig "step4_BatchAirdrop()" \
--rpc-url sepolia \
--broadcast \
--legacy

# 5. 收集手续费
forge script script/do/CallX402Launchpad.s.sol:CallX402Launchpad \
--sig "step5_CollectSwapFees()" \
--rpc-url sepolia \
--broadcast \
--legacy

# 6. 查询合约状态
forge script script/do/CallX402Launchpad.s.sol:CallX402Launchpad \
--sig "queryContractState()" \
--rpc-url sepolia

# 完整工作流程
forge script script/do/CallX402Launchpad.s.sol:CallX402Launchpad \
--sig "runFullWorkflow()" \
--rpc-url sepolia \
--broadcast \
--legacy

*/
contract CallX402Launchpad is Script {
    X402Launchpad x402Launchpad;
    address payable proxyAddress;
    uint256 deployerPrivateKey;
    address deployer;

    // 测试代币配置
    IERC20 fundingToken;
    address[] airdropRecipients;
    
    // 部署的代币信息
    IERC20 deployedToken;
    string tokenSymbol = "t3";

    function setUp() public {
        // 从.env文件读取私钥和代理合约地址
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);
        console.log("setUp, deployer:", deployer);

        proxyAddress = payable(vm.envAddress("PROXY_ADDRESS"));
        console.log("setUp, proxyAddress:", proxyAddress);

        x402Launchpad = X402Launchpad(proxyAddress);

        // 初始化测试配置
        fundingToken = IERC20(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238); // 使用已有的代币地址
        
        // 设置空投接收者列表
        airdropRecipients = new address[](3);
        airdropRecipients[0] = deployer;
        airdropRecipients[1] = 0x39034cF2D4bbDeAaF9BDf35F4005F6324CFf8A83;
        airdropRecipients[2] = 0x99002a739dc14A95CD454795712e2A9987aeAfBf;

        console.log("Test configuration initialized");
        console.log("Funding token:", address(fundingToken));
        console.log("Airdrop recipients count:", airdropRecipients.length);
    }

    // 第一步：初始化合约配置
    function step1_InitConfig() public {
        console.log("\n=== Step 1: Initialize Contract Configuration ===");

        vm.startBroadcast(deployerPrivateKey);

        // 设置所有管理员地址为部署者（实际项目中应该使用不同的地址）
        x402Launchpad.initConfig(
            0xa9012Bdc1705edB039db00aCcd628373151c40Fc, // createTokenAdmin
            0xa9012Bdc1705edB039db00aCcd628373151c40Fc, // addLiquidityAdmin
            0xa9012Bdc1705edB039db00aCcd628373151c40Fc, // airdropAdmin
            0xa9012Bdc1705edB039db00aCcd628373151c40Fc, // refundAdmin
            0xa9012Bdc1705edB039db00aCcd628373151c40Fc, // fundingCollectAddress
            0xa9012Bdc1705edB039db00aCcd628373151c40Fc  // swapFeeTo
        );

        vm.stopBroadcast();

        console.log("Contract configuration initialized successfully");
        console.log("All admin roles set to:", deployer);
    }

    // 第二步：部署新代币
    function step2_DeployToken() public {
        console.log("\n=== Step 2: Deploy New Token ===");

        vm.startBroadcast(deployerPrivateKey);

        // 部署新代币
        x402Launchpad.deploy(
            "Test Token",     // _name
            tokenSymbol,      // _symbol
            18,               // _decimals
            100e18,          // _cap (100 tokens)
            fundingToken,    // _fundingToken
            1e4              // _fundingAmount (0.01 usdc funding tokens) 刚好 1w:1
        );

        vm.stopBroadcast();

        // 获取部署的代币地址
        deployedToken = x402Launchpad.tokens(tokenSymbol);
        console.log("Token deployed successfully");
        console.log("Token symbol:", tokenSymbol);
        console.log("Token address:", address(deployedToken));
        console.log("Token cap: 1,000,000 tokens");
        console.log("Funding amount: 100 funding tokens");
    }

    // 第三步：添加流动性
    function step3_AddLiquidity() public {
        console.log("\n=== Step 3: Add Liquidity ===");

        deployedToken = IERC20(0xC64820c15e7Fb4860e3Fd07D33cc6694678F79C0);
        if (address(deployedToken) == address(0)) {
            console.log("ERROR: No token deployed yet. Run step2_DeployToken first.");
            return;
        }

        vm.startBroadcast(deployerPrivateKey);

        // 添加流动性
        x402Launchpad.addLiquidity(deployedToken);

        vm.stopBroadcast();

        uint256 lpTokenId = x402Launchpad.lpTokenIds(deployedToken);
        console.log("Liquidity added successfully");
        console.log("LP Token ID:", lpTokenId);
        console.log("Token status changed to: AddedLiquidity");
    }

    // 第四步：批量空投
    function step4_BatchAirdrop() public {
        console.log("\n=== Step 4: Batch Airdrop ===");

        if (address(deployedToken) == address(0)) {
            console.log("ERROR: No token deployed yet. Run step2_DeployToken first.");
            return;
        }

        vm.startBroadcast(deployerPrivateKey);

        // 计算每个接收者的空投金额（总供应量的1%）
        uint256 airdropAmount = x402Launchpad.tokenSupplies(deployedToken) / 100;

        // 执行批量空投
        x402Launchpad.batchAirdrop(deployedToken, airdropRecipients, airdropAmount);

        vm.stopBroadcast();

        console.log("Batch airdrop completed successfully");
        console.log("Airdrop amount per recipient:", airdropAmount);
        console.log("Number of recipients:", airdropRecipients.length);
        
        // 验证空投结果
        for (uint i = 0; i < airdropRecipients.length; i++) {
            bool airdropped = x402Launchpad.airdropped(deployedToken, airdropRecipients[i]);
            console.log("Recipient", airdropRecipients[i], "airdropped:", airdropped);
        }
    }

    // 第五步：收集手续费
    function step5_CollectSwapFees() public {
        console.log("\n=== Step 5: Collect Swap Fees ===");

        if (address(deployedToken) == address(0)) {
            console.log("ERROR: No token deployed yet. Run step2_DeployToken first.");
            return;
        }

        vm.startBroadcast(deployerPrivateKey);

        // 收集手续费
        x402Launchpad.collectSwapFees(deployedToken);

        vm.stopBroadcast();

        console.log("Swap fees collected successfully");
        console.log("Fees transferred to swap fee recipient");
    }

    // 查询合约状态
    function queryContractState() public {
        console.log("\n=== Current Contract State ===");
        console.log("Proxy Address:", proxyAddress);
        console.log("Contract Version:", x402Launchpad.version());
        
        // 管理员地址
        console.log("\n--- Admin Addresses ---");
        console.log("Create Token Admin:", x402Launchpad.createTokenAdmin());
        console.log("Add Liquidity Admin:", x402Launchpad.addLiquidityAdmin());
        console.log("Airdrop Admin:", x402Launchpad.airdropAdmin());
        console.log("Refund Admin:", x402Launchpad.refundAdmin());
        console.log("Funding Collect Address:", x402Launchpad.fundingCollectAddress());
        console.log("Swap Fee To:", x402Launchpad.swapFeeTo());
        
        // 配置参数
        console.log("\n--- Configuration Parameters ---");
        console.log("Swap Fee Rate:", x402Launchpad.swapFeeRate());
        console.log("Token Add Liquidity Rate:", x402Launchpad.tokenAddLiquidityRate());
        console.log("Paused:", x402Launchpad.paused());
        
        // 部署的代币信息
        if (address(deployedToken) != address(0)) {
            console.log("\n--- Deployed Token Info ---");
            console.log("Token Symbol:", tokenSymbol);
            console.log("Token Address:", address(deployedToken));
            console.log("Token Supply:", x402Launchpad.tokenSupplies(deployedToken));
            console.log("Funding Token:", address(x402Launchpad.fundingTokens(deployedToken)));
            console.log("Funding Amount:", x402Launchpad.fundingAmounts(deployedToken));
            console.log("LP Token ID:", x402Launchpad.lpTokenIds(deployedToken));
            
            // 检查代币状态
            uint8 tokenStatusValue = uint8(x402Launchpad.tokenStatus(deployedToken));
            string memory status;
            if (tokenStatusValue == 0) status = "Presale";
            else if (tokenStatusValue == 1) status = "AddedLiquidity";
            else status = "Refund";
            console.log("Token Status:", status);
        }
    }

    // 运行完整工作流程
    function runFullWorkflow() public {
        console.log("=== Starting Complete X402Launchpad Workflow ===");

        step1_InitConfig();
        step2_DeployToken();
        step3_AddLiquidity();
        step4_BatchAirdrop();
        step5_CollectSwapFees();

        queryContractState();

        console.log("\n=== X402Launchpad Workflow Completed Successfully ===");
        console.log("You can now use the deployed proxy at:", proxyAddress);
        if (address(deployedToken) != address(0)) {
            console.log("Deployed token at:", address(deployedToken));
        }
    }
}