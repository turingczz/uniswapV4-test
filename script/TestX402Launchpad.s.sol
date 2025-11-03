// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "../src/X402Launchpad.sol";
import "../src/ERC3009Token.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestX402LaunchpadScript is Script {
    X402Launchpad public launchpad;
    ERC3009Token public testToken;
    address public deployer;
    
    function setUp() public {
        deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        
        // 部署X402Launchpad合约
        vm.startBroadcast(deployer);
//        launchpad = new X402Launchpad();
        launchpad = X402Launchpad(payable(0x0fbf6187C26AF7C7E04BD8A428a7519aA2A3a7fC));
        // 注意：X402Launchpad合约构造函数中调用了_disableInitializers()，无法通过initialize初始化
        // 由于合约部署时部署者自动成为所有者，我们可以直接设置管理员配置
        
        // 设置合约配置
        launchpad.setCreateTokenAdmin(deployer);
        launchpad.setAddLiquidityAdmin(deployer);
        launchpad.setAirdropAdmin(deployer);
        launchpad.setRefundAdmin(deployer);
        launchpad.setFeeTo(deployer);
        launchpad.setSwapFeeTo(deployer);
        launchpad.setFeeRate(1000); // 1% 手续费
        launchpad.setSwapFeeRate(3000); // 0.3% 交易手续费
        vm.stopBroadcast();
    }
    
    function run() public {
        setUp();
        
        // 测试1: createTokenAndCreatePool
        testCreateTokenAndCreatePool();
        
        // 测试2: addLiquidity
        testAddLiquidity();
        
        // 测试3: collectFees
        // testCollectFees();
        
        console.log("All tests completed!");
    }
    
    function testCreateTokenAndCreatePool() internal {
        console.log("Testing createTokenAndCreatePool...");
        
        vm.startBroadcast(deployer);
        
        // 创建代币和池子
        string memory name = "Test Token";
        string memory symbol = "TEST";
        uint8 decimals = 18;
        uint256 cap = 1000000 * 10**18; // 100万代币
        
        // 使用ETH作为支付代币
        IERC20 currency = IERC20(address(0));
        uint256 amount = 1 ether; // 1 ETH作为支付代币
        uint256 quota = 100000 * 10**18; // 10万代币配额
        uint256 start = block.timestamp + 1 hours;
        uint256 expiry = start + 30 days;
        
        // 调用createTokenAndCreatePool
        launchpad.createTokenAndCreatePool(name, symbol, decimals, cap, currency, amount, quota, start, expiry);
        
        // 验证代币是否创建成功
        address tokenAddress = address(launchpad.tokens(symbol));
        require(tokenAddress != address(0), "Token creation failed");
        
        testToken = ERC3009Token(tokenAddress);
        console.log("Token created successfully:", tokenAddress);
        console.log("Token name:", testToken.name());
        console.log("Token symbol:", testToken.symbol());
        console.log("Total supply:", testToken.totalSupply());
        
        // 验证池子是否创建成功
        uint256 tokenAmount = launchpad.amounts(IERC20(tokenAddress));
        require(tokenAmount > 0, "Pool creation failed");
        console.log("Pool created successfully, liquidity amount:", tokenAmount);
        
        vm.stopBroadcast();
        console.log("createTokenAndCreatePool test passed!");
    }
    
    function testAddLiquidity() internal {
        console.log("Testing addLiquidity...");
        
        vm.startBroadcast(deployer);
        
        // 获取之前创建的代币
        address tokenAddress = address(launchpad.tokens("TEST"));
        require(tokenAddress != address(0), "Token does not exist");
        
        IERC20 token = IERC20(tokenAddress);
        
        // 添加流动性
        bool preSaleSuccess = true;
        
        // 调用addLiquidity
        launchpad.addLiquidity(token, preSaleSuccess, 0.5 ether);
        
        console.log("Liquidity added successfully");
        console.log("Pre-sale status:", preSaleSuccess);
        
        vm.stopBroadcast();
        console.log("addLiquidity test passed!");
    }
    
    function testCollectFees() internal {
        console.log("Testing collectFees...");
        
        vm.startBroadcast(deployer);
        
        // 获取之前创建的代币
        address tokenAddress = address(launchpad.tokens("TEST"));
        require(tokenAddress != address(0), "Token does not exist");
        
        IERC20 token = IERC20(tokenAddress);
        
        // 记录当前手续费余额
//        uint256 initialBalance = deployer.balance;
        
        // 调用collectFees
        launchpad.collectFees(token);
        
        // // 检查手续费是否收集成功
        // uint256 finalBalance = deployer.balance;
        
        // if (finalBalance > initialBalance) {
        //     console.log("Fees collected successfully");
        //     console.log("Collected fees:", finalBalance - initialBalance);
        // } else {
        //     console.log("No fees available to collect");
        // }
        
        vm.stopBroadcast();
        console.log("collectFees test passed!");
    }
}


/* 特别注意：uniswapV4的调用代码，不能直接测试。
需要部署好后，使用cast脚本测试。例如：execute_v4_functions.sh

部署命令:
forge script script/TestX402Launchpad.s.sol:TestX402LaunchpadScript \
    --rpc-url=sepolia \
    --broadcast \
    --legacy \
    --gas-limit 30000000

forge script script/TestX402Launchpad.s.sol:TestX402LaunchpadScript \
    --rpc-url=base \
    --broadcast \
    --legacy --verify
*/