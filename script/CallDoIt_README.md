# 调用doIt函数脚本使用说明

## 前置条件
1. 合约已经部署到网络
2. 调用者地址需要有MINTER_ROLE角色
3. 配置正确的环境变量

## 使用方法

### 1. 设置环境变量
```bash
export CONTRACT_ADDRESS="你的合约地址"
export PRIVATE_KEY="你的私钥"
export RPC_URL="https://sepolia.infura.io/v3/YOUR_PROJECT_ID"
```

### 2. 检查权限（可选）
```bash
# 检查调用者是否有MINTER_ROLE
forge script script/CallDoIt.sol:CallDoItScript \
    --rpc-url=$RPC_URL \
    --sig "checkMinterRole(address,address)" \
    $CONTRACT_ADDRESS $(cast wallet address $PRIVATE_KEY)
```

### 3. 调用doIt函数
```bash
forge script script/CallDoIt.sol:CallDoItScript \
    --rpc-url=$RPC_URL \
    --broadcast \
    --legacy
```

### 4. 验证结果（可选）
```bash
# 检查流动性是否已部署
forge script script/CallDoIt.sol:CallDoItScript \
    --rpc-url=$RPC_URL \
    --sig "isLiquidityDeployed(address)" \
    $CONTRACT_ADDRESS

# 获取LP token ID
forge script script/CallDoIt.sol:CallDoItScript \
    --rpc-url=$RPC_URL \
    --sig "getLpTokenId(address)" \
    $CONTRACT_ADDRESS
```

## 脚本功能

1. **主函数** (`run()`)：调用已部署合约的doIt函数
2. **权限检查** (`checkMinterRole()`)：验证地址是否有MINTER_ROLE
3. **状态查询** (`isLiquidityDeployed()`)：检查流动性部署状态
4. **LP Token查询** (`getLpTokenId()`)：获取协议拥有的LP token ID

## 注意事项

- 确保调用者地址在合约中有MINTER_ROLE
- 确保有足够的ETH支付gas费用
- doIt函数只能调用一次（流动性部署后无法再次调用）
- 建议在调用前先检查权限和状态