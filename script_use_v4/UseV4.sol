// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;
pragma abicoder v2;

import "./UniswapV4.sol";

contract UseV4 is UniswapV4 {
   string public constant version = "1.0.0";
    TokenParams p;

   constructor() {}

   //创建token，创建交易池
   function initializePool() external {
        TokenParams memory p1 = TokenParams({
            paymentToken: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238,
            newToken: 0x0A3728E805073E5Aaf6755C872336c50b27114Ed,
            paymentTokenAmount: 100,
            newTokenAmount: 100,
            paymentTokenIsToken0: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238 < 0x0A3728E805073E5Aaf6755C872336c50b27114Ed,
            sqrtPricePaymentTokenFirst: 79228162514264337593543950336,
            sqrtPriceNewTokenFirst: 79228162514264337593543950336
        });
        _initializePool(p1, 213, 200);
       p = p1;
   }

   function addLiquidity() external returns(uint256 lpTokenId) {
       lpTokenId = _deployLiquidity(p, 213, 200);
   }

   function collectFees(uint256 lpTokenId) external {
       _collectLpFees(lpTokenId);
   }
}
