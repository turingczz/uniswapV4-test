// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;
pragma abicoder v2;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ERC3009Token.sol";
import "./UniswapV4.sol";
import "./X402LaunchpadCommon.sol";

contract X402Launchpad is X402LaunchpadCommon, UniswapV4 {
	using SafeERC20 for IERC20;
   string public constant version = "1.0.0";

   struct PreSale {
       bool success;
       bool addedLiquidity;
       uint256 updateTimestamp;
   }
   mapping (string => IERC20) public tokens;
   mapping (IERC20 => uint) public supplies;
    mapping (IERC20 => uint) public suppliesAdd;
   mapping (IERC20 => IERC20) public currencies;
   mapping (IERC20 => uint) public amounts;
   mapping (IERC20 => uint) public amountsAdd;
   mapping (IERC20 => uint) public quotas;
   mapping (IERC20 => uint) public starts;
   mapping (IERC20 => uint) public expires;
   mapping (IERC20 => uint) public feeRates;

   mapping (IERC20 => TokenParams) public params;
   mapping (IERC20 => uint) public lpTokenIds;
   mapping (IERC20 => PreSale) public perSales;//后端设置结束，是否预售成功，添加了流动性。
   mapping (IERC20 => mapping (uint => bool)) public airdropped;//id是否空投
   mapping (IERC20 => mapping (address => uint)) public airdroppedAmount;//用户空投额度
   mapping (IERC20 => mapping (uint => bool)) public refunded;//id是否退款

   constructor(
       address _poolManger,
       address _positionManger,
       address _permit2
   ) UniswapV4(_poolManger, _positionManger, _permit2) {
       _disableInitializers();
   }

    function initialize(address _initialOwner) public override initializer {
        super.initialize(_initialOwner);
    }

   //角色一： 创建token，添加流动性
   //角色二： 空投token
   //角色三： 退款

   //创建token，创建交易池
   function createTokenAndCreatePool(string memory _name, string memory _symbol, uint8 _decimals, uint _cap, IERC20 _currency, uint _amount, uint _quota, uint _start, uint _expiry) external payable nonReentrant whenNotPaused {
       require(msg.sender == createTokenAdmin, "token admin only");
       require(_start < _expiry && block.timestamp < _expiry, "too early expiry");
       require(_cap > 0 && _amount > 0 && _quota > 0, "Invalid cap, amount or quota");
       require(tokens[_symbol] == IERC20(address(0)), "Token exists!"); //检查平台是否存在该token

       IERC20 token = IERC20(new ERC3009Token(_name, _symbol, _decimals, uint8(_cap)));
       bool paymentTokenIsToken0 = paymentToken < address(token);
       uint256 preAmountAdd = _amount * tokenAddRate / SCALE_FACTOR; //20%
       uint256 amountAdd = preAmountAdd - getFeeRateAmount(preAmountAdd, feeRate); //feeRate 5%
       uint256 supplyAdd = _cap * tokenAddRate / SCALE_FACTOR; //20%

       TokenParams memory p = TokenParams({
            paymentToken: paymentToken,
            newToken: address(token),
            paymentTokenAmount: amountAdd,
            newTokenAmount: supplyAdd,
            paymentTokenIsToken0: paymentTokenIsToken0,
            sqrtPricePaymentTokenFirst: 0,
            sqrtPriceNewTokenFirst: 0
        });
         (p.sqrtPricePaymentTokenFirst, p.sqrtPriceNewTokenFirst) = _calculateSqrtPrices(
             amountAdd, supplyAdd, paymentTokenIsToken0);
        _initializePool(p, uint24(feeRate), 200);
       emit CreateTokenAndCreatePool(msg.sender, _symbol, token, block.timestamp, p);

       tokens[_symbol] = token;
       supplies[token] = _cap;
       suppliesAdd[token] = supplyAdd;
       currencies[token] = _currency;
       amounts[token] = _amount;
       amountsAdd[token] = amountAdd;
       feeRates[token] = feeRate;
       params[token] = p;
       quotas[token] = _quota;
       starts[token] = _start;
       expires[token] = _expiry;
   }
   event CreateTokenAndCreatePool(address msgSender, string _symbol, IERC20 indexed token, uint timestamp, TokenParams p);

   //Completed
   function addLiquidity(IERC20 _token, bool _preSaleSuccess, uint256 _actualAmountAdd) external payable nonReentrant whenNotPaused {
       require(msg.sender == addLiquidityAdmin, "add liquidity admin only");
       require(block.timestamp > expires[_token], "not over expiry");
       require(perSales[_token].updateTimestamp > 0, "already added liquidity");
       require(_actualAmountAdd > 0, "invalid actual amount add");

       if (!_preSaleSuccess) {
           perSales[_token] = PreSale(false, false, block.timestamp);
           emit AddedLiquidity(msg.sender, _token, false, block.timestamp);
           return;
       }
       perSales[_token] = PreSale(true, true, block.timestamp);

       uint256 amountAdd = _actualAmountAdd - getFeeRateAmount(_actualAmountAdd, feeRate); //feeRate 5%
       uint256 fee = _actualAmountAdd - amountAdd;
       amountsAdd[_token] = amountAdd;
       params[_token].paymentTokenAmount = amountAdd;

       lpTokenIds[_token] = _deployLiquidity(params[_token], swapFeeRate, 200);
       currencies[_token].safeTransfer(feeTo, fee);
        emit AddedLiquidity(msg.sender, _token, _preSaleSuccess, block.timestamp);
   }
   event AddedLiquidity(address msgSender, IERC20 indexed token, bool success, uint timestamp);

   //空投，打满添加流动性后，官方会发放一半的代币给用户
   function airdrops(IERC20 _token, uint256[] calldata _ids, address[] calldata _tos, uint[] calldata _amounts) external nonReentrant whenNotPaused {
       require(msg.sender == airdropAdmin, "airdrop admin only");
       require(_ids.length == _tos.length && _ids.length == _amounts.length, "invalid length");

       for(uint i = 0; i < _ids.length; i++) {
           _airdrop(_token, _ids[i], _tos[i], _amounts[i]);
       }
   }
   function _airdrop(IERC20 _token, uint _id, address _to, uint _amount) internal {
       require(airdropped[_token][_id] == false, "airdropped already");
       airdropped[_token][_id] = true;

       airdroppedAmount[_token][_to] += _amount;
       require(airdroppedAmount[_token][_to] <= quotas[_token], "exceed user amount");

       require(perSales[_token].addedLiquidity, "need to add liquidity");

       //1.amount是x402支付的时候就确定的
       //2.token本身就在合约中，直接转移则ok
       _token.safeTransfer(_to, _amount);
       emit Airdropped(msg.sender, _id, _token, _to, _amount);
   }
   event Airdropped(address sender, uint id, IERC20 indexed token, address indexed to, uint amount);

   //退款，只能在结束时间之后，官方调用
   function refunds(IERC20 _token, uint256[] calldata _ids, address[] calldata _tos, uint[] calldata _amounts) external nonReentrant whenNotPaused {
       require(msg.sender == refundAdmin, "refund admin only");
       require(_ids.length == _tos.length && _ids.length == _amounts.length, "invalid length");

       for(uint i = 0; i < _ids.length; i++) {
           _refund(_token, _ids[i], _tos[i], _amounts[i]);
       }
   }
   function _refund(IERC20 token, uint id, address to, uint amount) internal {
       require(refunded[token][id] == false, "airdropped already");
       refunded[token][id] = true;
       require(!perSales[token].success && perSales[token].updateTimestamp >0, "need to set failed");

       uint fee = getFeeRateAmount(amount, feeRates[token]);
       uint refundAmount = amount - fee;

	    IERC20 currency = currencies[token];
       currency.safeTransfer(feeTo, fee);
       currency.safeTransfer(to, refundAmount);
       emit Refund(token, id, to, fee, refundAmount);
   }
   event Refund(IERC20 indexed token, uint id, address indexed to, uint fee, uint refundAmount);

   //手动操作，收集手续费用
   function collectFees(IERC20 _token) external nonReentrant {
       require(address(_token) != address(0), "invalid token");
       uint lpTokenId = lpTokenIds[_token];
       require(lpTokenId != 0, "not exist token");

       IERC20 currency = currencies[_token];
       uint amount = currency.balanceOf(address(this));
       uint volume = _token.balanceOf(address(this));
       _collectLpFees(lpTokenId);
       currency.safeTransfer(swapFeeTo, currency.balanceOf(address(this)) - amount);
       _token.safeTransfer(swapFeeTo, _token.balanceOf(address(this)) - volume);
   }

   //更新设置开始时间和结束时间
   function setTokenTimes(IERC20 _token, uint _start, uint _expiry) external onlyOwner {
       require(amounts[_token] > 0, "invalid token");
       require(_start > 0 && _expiry > 0 && _expiry > _start, "invalid start or expiry");

       emit SetTimes(msg.sender, _token, starts[_token], expires[_token], _start, _expiry);
       starts[_token] = _start;
       expires[_token] = _expiry;
   }
   event SetTimes(address indexed sender, IERC20 indexed token, uint oldStart, uint oldExpiry, uint start, uint expiry);

   function getTokenInfo(IERC20 _token) public view returns(uint,IERC20,uint,uint,uint, PreSale memory) {
       require(amounts[_token] > 0, "invalid token");
       return (supplies[_token], currencies[_token], amounts[_token], starts[_token], expires[_token], perSales[_token]);
   }

   function getFeeRateAmount(uint _amount, uint _feeRate) public pure returns(uint) {
       return _amount * _feeRate / 1e18;
   }
}
