// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Context } from "@openzeppelin/contracts/utils/Context.sol";
import { ContextUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "./ERC3009Token.sol";
import "./UniswapV4.sol";
import "./X402LaunchpadCommon.sol";

contract X402Launchpad is X402LaunchpadCommon, UniswapV4 {
	using SafeERC20 for IERC20;
   string public constant version = "1.0.0";

   struct PreSale {
       bool success;
       bool addedLiquidity;
       uint256 timestamp;
   }

   mapping (string => IERC20) public tokens;
   mapping (IERC20 => uint) public supplies;
   mapping (IERC20 => IERC20) public currencies;
   mapping (IERC20 => uint) public amounts;
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

   constructor() {
       // 由于调用了_disableInitializers()，无法通过initialize初始化
       // 直接设置部署者为所有者
       _transferOwnership(msg.sender);
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
       require(msg.sender == tokenAdmin, "token admin only");
       require(_start < _expiry && block.timestamp < _expiry, "too early expiry");
       require(_cap > 0 && _amount > 0 && _quota > 0, "Invalid cap, amount or quota");
       require(tokens[_symbol] == IERC20(address(0)), "Token exists!"); //检查平台是否存在该token

    //    IERC20 token = IERC20(new ERC3009Token(_name, _symbol, _decimals, uint8(_cap)));
    //    address pool;

        TokenParams memory p = TokenParams({
            paymentToken: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238,
            newToken: 0x0A3728E805073E5Aaf6755C872336c50b27114Ed,
            paymentTokenAmount: 100,
            newTokenAmount: 100,
            paymentTokenIsToken0: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238 < 0x0A3728E805073E5Aaf6755C872336c50b27114Ed,
            sqrtPricePaymentTokenFirst: 79228162514264337593543950336,
            sqrtPriceNewTokenFirst: 79228162514264337593543950336
        });
            // sqrtPricePaymentTokenFirst: 79228162514264337593543950336,
            // sqrtPriceNewTokenFirst: 79228162514264337593543950336,
        // (p.sqrtPricePaymentTokenFirst, p.sqrtPriceNewTokenFirst) = 
            // _calculateSqrtPrices(p.paymentTokenAmount, p.newTokenAmount, p.paymentTokenIsToken0);
        _initializePool(p, 211, 200);

        IERC20 token = IERC20(p.newToken);
       tokens[_symbol] = token;
       supplies[token] = _cap;
       currencies[token] = _currency;
       amounts[token] = _amount;
       feeRates[token] = feeRate;
       params[token] = p;

       quotas[token] = _quota;
       starts[token] = _start;
       expires[token] = _expiry;
   }
   event CreateTokenAndCreatePool(address msgSender, string _symbol, IERC20 indexed token, address pool, uint timestamp);

   //Completed
   function addLiquidity(IERC20 _token, bool _preSaleSuccess) external payable nonReentrant whenNotPaused {
       require(msg.sender == tokenAdmin, "create token admin only");
       require(amounts[_token] > 0, "invalid token");
       require(perSales[_token].timestamp > 0, "already added liquidity");

       if (!_preSaleSuccess) {
           perSales[_token].success = false;
           perSales[_token].addedLiquidity = false;
           perSales[_token].timestamp = block.timestamp;
          emit AddedLiquidity(msg.sender, _token, false, block.timestamp);
           return;
       }

//       uint feeRateAmount = getFeeRateAmount(total, feeRates[token]);
//       uint amountLP;
//       (lpTokenIds[token],amountLP) = FunPool.addPool(address(token), supplies[token]/2, address(currency), amounts[token] - feeRateAmount);
//       currency.safeTransfer(feeTo, amounts[token] - amountLP);

       lpTokenIds[_token] = _deployLiquidity(params[_token], 211, 200);   

       perSales[_token].success = true;
       perSales[_token].addedLiquidity = true;
       perSales[_token].timestamp = block.timestamp;
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
       require(!perSales[token].success && perSales[token].timestamp>0, "need to set failed");

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
       require(amounts[_token] > 0, "not exist token");
       uint lpTokenId = lpTokenIds[_token];
        
       collectLpFees(lpTokenId);

    //     //feeTo 是合约地址，需要手动提取
    //    IERC20 swapFeeCurrency;
    //    uint amountBefore = swapFeeCurrency.balanceOf(address(this));
       
    //    collectLpFees(lpTokenId); //todo 测试一下fee提取到哪里了，怎么正确配置一下；如果知道哪个用户调用；直接nft转给这个地址比较合适
    //     //是否提取到本合约中了，如果是从合约中提取

    //     uint amountAfter = swapFeeCurrency.balanceOf(address(this));
    //    swapFeeCurrency.safeTransfer(swapFeeTo, amountAfter - amountBefore);
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
   
    // Override functions to resolve diamond inheritance conflict
    function _msgSender() internal view virtual override(Context, ContextUpgradeable) returns (address) {
        return ContextUpgradeable._msgSender();
    }

    function _msgData() internal view virtual override(Context, ContextUpgradeable) returns (bytes calldata) {
        return ContextUpgradeable._msgData();
    }

    function _contextSuffixLength() internal view virtual override(Context, ContextUpgradeable) returns (uint256) {
        return ContextUpgradeable._contextSuffixLength();
    }
}
