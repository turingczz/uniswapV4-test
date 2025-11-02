#!/bin/bash

# V4 函数执行脚本
# 这个脚本完全按照用户提供的 cast 命令执行

set -e  # 遇到错误时退出

echo "=== V4 Functions Execution Script ==="
echo "开始执行 V4 函数调用..."

RPC_URL="https://virulent-delicate-wish.ethereum-sepolia.quiknode.pro/"
PRIVATE_KEY="0xf6ba0bbff94e3b7cdbe1d876128d6b4495346b110e4e83987823aa5973a12e31"
PING_CONTRACT="0x3a73Fd4CCC9F1caf1DadBc6b6Afc87a7e5D02b68"
USDC_TOKEN="0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"
MOSS_TOKEN="0x0A3728E805073E5Aaf6755C872336c50b27114Ed"

# 步骤1: USDC 授权
echo ""
echo "1. 执行 USDC 授权..."
cast send $USDC_TOKEN "approve(address,uint256)" $PING_CONTRACT 100 \
    --rpc-url="$RPC_URL" \
    --private-key $PRIVATE_KEY

echo "✓ USDC 授权成功"

# 步骤2: MOSS 授权
echo ""
echo "2. 执行 MOSS 授权..."
cast send $MOSS_TOKEN "approve(address,uint256)" $PING_CONTRACT 100 \
    --rpc-url="$RPC_URL" \
    --private-key $PRIVATE_KEY

echo "✓ MOSS 授权成功"

# 步骤3: 执行 doItWithDifferentFee
echo ""
echo "3. 执行 doItWithDifferentFee 函数..."
RESULT=$(cast call $PING_CONTRACT \
    "doItWithDifferentFee((address,address,uint256,uint256,uint160,uint160,bool),uint24,int24)(uint256)" \
    "($USDC_TOKEN,$MOSS_TOKEN,100,100,79228162514264337593543950336,79228162514264337593543950336,false)" \
    184 200 \
    --rpc-url="$RPC_URL" \
    --private-key $PRIVATE_KEY)

echo "✓ doItWithDifferentFee 执行成功"
echo "返回的 LP Token ID: $RESULT"

echo ""
echo "=== 执行完成 ==="
echo "最终 LP Token ID: $RESULT"
echo ""
echo "脚本执行成功！"