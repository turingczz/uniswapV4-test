// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.28;

import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IPositionManager, PoolKey as PositionPoolKey} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "v4-periphery/src/libraries/LiquidityAmounts.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UniswapV4 {
    struct TokenParams {
        address paymentToken;
        address newToken;
        uint256 paymentTokenAmount;
        uint256 newTokenAmount;
        uint160 sqrtPricePaymentTokenFirst;
        uint160 sqrtPriceNewTokenFirst;
        bool paymentTokenIsToken0;
    }

    // -- immutable state --

    /// @notice The pool manager (Uniswap v4 PoolManager)
    IPoolManager public constant POOL_MANAGER = IPoolManager(0xE03A1074c86CFeDd5C142C4F04F1a1536e203543);

    /// @notice The PositionManager for managing liquidity NFTs
    IPositionManager public constant POSITION_MANAGER = IPositionManager(0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4);

    /// @notice Permit2 for token approvals
    IAllowanceTransfer public constant PERMIT2 = IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    // event
    event InitializePool(PoolKey poolKey);
    event LiquidityDeployed(uint256 tokenId, uint128 liquidity);
    event FeesCollected(address recipient, uint256 amountToken0, uint256 amountToken1);

    constructor(){}

    /// @dev Initialize the Uniswap v4 pool, mint a full range LP position, and settle funds in one flow.
    /// @param fee The pool fee in pips (e.g. 3000 = 0.3%)
    /// @param tickSpacing The tick spacing for the pool configuration
    function _initializePool(TokenParams memory p, uint24 fee, int24 tickSpacing) internal {
        (address token0, address token1, uint160 sqrtPriceX96) = _sortedTokenData(p);

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(0))
        });

        // Initialize pool via PositionManager's initializer interface
        // Note: This requires the PoolManager to be deployed and activated on the network
        try POOL_MANAGER.initialize(poolKey, sqrtPriceX96) {
            // Successfully initialized
        } catch {
            revert("PoolManager initialization failed - check if Uniswap v4 is deployed on this network");
        }
        emit InitializePool(poolKey);
    }

    /// @dev mint a full range LP position, and settle funds in one flow.
    /// @param fee The pool fee in pips (e.g. 3000 = 0.3%)
    /// @param tickSpacing The tick spacing for the pool configuration
    function _deployLiquidity(TokenParams memory p, uint24 fee, int24 tickSpacing) internal returns(uint256 lpTokenId) {
        (address token0, address token1,) = _sortedTokenData(p);

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(0))
        });

        // Prepare mint actions payload
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));

        // Transfer tokens from caller to contract first
        IERC20(p.paymentToken).transferFrom(msg.sender, address(this), p.paymentTokenAmount);
        IERC20(p.newToken).transferFrom(msg.sender, address(this), p.newTokenAmount);

        (uint128 amount0Max, uint128 amount1Max, uint128 liquidity) =
            _calculateMintParams(p, poolKey);

        (int24 tickLower, int24 tickUpper) = _fullRangeTicks(tickSpacing);

        // Set up approvals for Permit2 and PositionManager
        // Approve Permit2 to spend both tokens with the correct amount
        IERC20(p.paymentToken).approve(address(PERMIT2), p.paymentTokenAmount);
        IERC20(p.newToken).approve(address(PERMIT2), p.newTokenAmount);

        // Approve PositionManager via Permit2 for both tokens
        PERMIT2.approve(p.paymentToken, address(POSITION_MANAGER), SafeCast.toUint160(p.paymentTokenAmount), type(uint48).max);
        PERMIT2.approve(p.newToken, address(POSITION_MANAGER), SafeCast.toUint160(p.newTokenAmount), type(uint48).max);

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(poolKey, tickLower, tickUpper, liquidity, amount0Max, amount1Max, address(this), bytes("")); //todo 池子nft给msg.sender
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);

        uint256 tokenIdBefore = POSITION_MANAGER.nextTokenId();
        POSITION_MANAGER.modifyLiquidities(abi.encode(actions, params), block.timestamp);

        lpTokenId = tokenIdBefore;
        emit LiquidityDeployed(lpTokenId, liquidity);
    }

    /// @notice Collect outstanding fees from the protocol-owned LP position to the owner
    function _collectLpFees(uint256 lpTokenId) internal {
        require(lpTokenId != 0, "LP_NOT_INITIALIZED");

        (PositionPoolKey memory poolKey,) = POSITION_MANAGER.getPoolAndPositionInfo(lpTokenId);

        bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR));

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(lpTokenId, uint256(0), uint128(0), uint128(0), bytes(""));
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1, msg.sender);

        uint256 deadline = block.timestamp + 1 hours;
        POSITION_MANAGER.modifyLiquidities(abi.encode(actions, params), deadline);
    }

    function _calculateMintParams(TokenParams memory p, PoolKey memory poolKey)
        internal
        pure
        returns (uint128 amount0Max, uint128 amount1Max, uint128 liquidity)
    {
        uint256 amount0;
        uint256 amount1;

        if (p.paymentTokenIsToken0) {
            amount0 = p.paymentTokenAmount;
            amount1 = p.newTokenAmount;
        } else {
            amount0 = p.newTokenAmount;
            amount1 = p.paymentTokenAmount;
        }

        amount0Max = SafeCast.toUint128(amount0);
        amount1Max = SafeCast.toUint128(amount1);

        uint256 sqrtPriceX96 = p.paymentTokenIsToken0 ? p.sqrtPricePaymentTokenFirst : p.sqrtPriceNewTokenFirst;
        (int24 tickLower, int24 tickUpper) = _fullRangeTicks(poolKey.tickSpacing);

        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            SafeCast.toUint160(sqrtPriceX96),
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0,
            amount1
        );
    }

    function _fullRangeTicks(int24 tickSpacing) internal pure returns (int24 tickLower, int24 tickUpper) {
        tickLower = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
        if (tickLower < TickMath.MIN_TICK) {
            tickLower += tickSpacing;
        }

        tickUpper = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
        if (tickUpper > TickMath.MAX_TICK) {
            tickUpper -= tickSpacing;
        }
    }

     function _sortedTokenData(TokenParams memory p) internal pure returns (address token0, address token1, uint160 sqrtPriceX96) {
        if (p.paymentTokenIsToken0) {
            token0 = p.paymentToken;
            token1 = p.newToken;
            sqrtPriceX96 = p.sqrtPricePaymentTokenFirst;
        } else {
            token0 = p.newToken;
            token1 = p.paymentToken;
            sqrtPriceX96 = p.sqrtPriceNewTokenFirst;
        }
    }

   /// @notice 根据两个token的数量计算sqrt价格
   /// @param paymentTokenAmount 支付代币数量
   /// @param newTokenAmount 新代币数量
   /// @param paymentTokenIsToken0 支付代币是否为token0
   /// @return sqrtPricePaymentTokenFirst 支付代币优先的sqrt价格
   /// @return sqrtPriceNewTokenFirst 新代币优先的sqrt价格
   function _calculateSqrtPrices(
       uint paymentTokenAmount,
       uint newTokenAmount,
       bool paymentTokenIsToken0
   ) internal pure returns (uint160 sqrtPricePaymentTokenFirst, uint160 sqrtPriceNewTokenFirst) {
       require(paymentTokenAmount > 0 && newTokenAmount > 0, "Amounts must be positive");
       
       // 计算价格比例 (Q64.96格式)
       // 价格 = (token1数量 * 2^96) / token0数量
       uint256 priceRatio;
       
       if (paymentTokenIsToken0) {
           // paymentToken是token0，newToken是token1
           // 价格 = (newTokenAmount * 2^96) / paymentTokenAmount
           priceRatio = (uint256(newTokenAmount) << 96) / paymentTokenAmount;
           sqrtPricePaymentTokenFirst = uint160(_sqrt(priceRatio));
           
           // 反向价格 = (paymentTokenAmount * 2^96) / newTokenAmount
           uint256 reversePriceRatio = (uint256(paymentTokenAmount) << 96) / newTokenAmount;
           sqrtPriceNewTokenFirst = uint160(_sqrt(reversePriceRatio));
       } else {
           // newToken是token0，paymentToken是token1
           // 价格 = (paymentTokenAmount * 2^96) / newTokenAmount
           priceRatio = (uint256(paymentTokenAmount) << 96) / newTokenAmount;
           sqrtPriceNewTokenFirst = uint160(_sqrt(priceRatio));
           
           // 反向价格 = (newTokenAmount * 2^96) / paymentTokenAmount
           uint256 reversePriceRatio = (uint256(newTokenAmount) << 96) / paymentTokenAmount;
           sqrtPricePaymentTokenFirst = uint160(_sqrt(reversePriceRatio));
       }
   }

   /// @notice 计算平方根 (Babylonian method)
   /// @param x 输入值
   /// @return y 平方根结果
   function _sqrt(uint256 x) internal pure returns (uint256 y) {
       if (x == 0) return 0;
       
       uint256 z = (x + 1) / 2;
       y = x;
       
       while (z < y) {
           y = z;
           z = (x / z + z) / 2;
       }
   }

}
