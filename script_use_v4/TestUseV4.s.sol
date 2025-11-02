// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "../script_v4/UseV4.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestUseV4Script is Script {
    UseV4 public useV4;
    address public deployer;
    
    function setUp() public {
        deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        
        // 部署UseV4合约
        vm.startBroadcast(deployer);
        useV4 = new UseV4();
        vm.stopBroadcast();
        
        console.log("UseV4 contract deployed successfully:", address(useV4));
        console.log("Contract version:", useV4.version());
    }
    
    function run() public {
        setUp();
        
        // 测试1: 初始化交易池
        testInitializePool();
        
        // 测试2: 添加流动性
        testAddLiquidity();
        
        // 测试3: 收集手续费
        // testCollectFees();
        
        console.log("All UseV4 contract tests completed!");
    }
    
    function testInitializePool() internal {
        console.log("Testing initializePool function...");
        
        vm.startBroadcast(deployer);

        // 为两个代币对UseV4合约进行授权（添加错误处理）
        try IERC20(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238).approve(address(useV4), 100) {
            console.log("First token approval successful");
        } catch {
            console.log("First token approval failed - contract may not be a valid ERC20");
        }
        
        try IERC20(0x0A3728E805073E5Aaf6755C872336c50b27114Ed).approve(address(useV4), 100) {
            console.log("Second token approval successful");
        } catch {
            console.log("Second token approval failed - contract may not be a valid ERC20");
        }
        
        // 调用initializePool函数
        useV4.initializePool();
        
        console.log("Pool initialized successfully");
        
        vm.stopBroadcast();
        console.log("initializePool test passed!");
    }
    
    function testAddLiquidity() internal {
        console.log("Testing addLiquidity function...");
        
        vm.startBroadcast(deployer);
        
        // 调用addLiquidity函数
        uint256 lpTokenId = useV4.addLiquidity();
        
        console.log("Liquidity added successfully, LP Token ID:", lpTokenId);

        vm.stopBroadcast();
        console.log("addLiquidity test passed!");
    }
    
    function testCollectFees() internal {
        console.log("Testing collectFees function...");
        
        vm.startBroadcast(deployer);
        
        // 假设我们有一个LP Token ID（在实际使用中，这个ID应该来自addLiquidity的返回值）
        uint256 lpTokenId = 1;
        
        // 调用collectFees函数
        useV4.collectFees(lpTokenId);
        
        console.log("Fee collection function called successfully");
        console.log("LP Token ID:", lpTokenId);
        
        vm.stopBroadcast();
        console.log("collectFees test passed!");
    }
    
    // 测试合约的基本信息
    function testContractInfo() internal view {
        console.log("Testing contract basic information...");
        
        string memory version = useV4.version();
        require(keccak256(abi.encodePacked(version)) == keccak256(abi.encodePacked("1.0.0")), "Version mismatch");
        
        console.log("Contract version verified successfully:", version);
        console.log("Contract basic information test passed!");
    }
}

/*特别注意：uniswapV4的调用代码，不能直接测试。
需要部署好后，使用cast脚本测试。例如：execute_v4_functions.sh

部署和测试命令:xxx 错误的，不能跑
forge script script/TestUseV4.s.sol:TestUseV4Script \
    --rpc-url=sepolia \
    --broadcast \
    --legacy


forge script script/TestUseV4.s.sol:TestUseV4Script \
    --rpc-url=sepolia \
    --broadcast \
    --legacy \
    --skip-simulation \
    -vvvv  # 详细日志

    forge script script/TestUseV4.s.sol:TestUseV4Script \
    --rpc-url=sepolia \
    --broadcast \
    --legacy \
    --unlocked \
    --sender 0xa9012Bdc1705edB039db00aCcd628373151c40Fc

注意: 请确保在运行脚本前设置正确的PRIVATE_KEY环境变量
*/