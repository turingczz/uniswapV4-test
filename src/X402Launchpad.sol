//// SPDX-License-Identifier: MIT
//
//pragma solidity ^0.8.20;
//pragma abicoder v2;
//
////import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
////import { Common } from "./common.sol";
//import "./ERC3009Token.sol";
//import "./v4.sol";
//
//
//contract X402Launchpad is Common {
//	using SafeERC20 for IERC20;
//    string public constant version = "1.0.0";
//
//    struct PreSale {
//        bool success;
//        bool addedLiquidity;
//        uint32 timestamp;
//    }
//
//    mapping (string => IERC20) public tokens;
//    mapping (IERC20 => uint) public supplies;
//    mapping (IERC20 => IERC20) public currencies;
//    mapping (IERC20 => uint) public amounts;
//    mapping (IERC20 => uint) public quotas;
//    mapping (IERC20 => uint) public starts;
//    mapping (IERC20 => uint) public expiries;
//    mapping (IERC20 => uint) public feeRates;
//
//    mapping (IERC20 => address) public pools;
//    mapping (IERC20 => uint) public lpTokenIds;
//    mapping (IERC20 => PreSale) public perSales;//后端设置结束，是否预售成功，添加了流动性。
//    mapping (IERC20 => mapping (uint => bool)) public airdropped;//id是否空投
//    mapping (IERC20 => mapping (address => uint)) public airdroppedAmount;//用户空投额度
//    mapping (IERC20 => mapping (uint => bool)) public refunded;//id是否退款
//
//    //new
//    address public tokenAdmin;
//    address public airdropAdmin;
//    address public refundAdmin;
//    address public feeTo;
//    address public swapFeeTo;
//    uint256 public feeRate;
//    uint256 public swapFeeRate;
//
//    constructor() {
//        _disableInitializers();
//    }
//
//    function initialize(address _initialOwner) public override initializer {
//        super.initialize(_initialOwner);
//    }
//
//    //角色一： 创建token，添加流动性
//    //角色二： 空投token
//    //角色三： 退款
//
//    //创建token，创建交易池
//    function createTokenAndCreatePool(string memory _name, string memory _symbol, uint8 _decimals, uint _cap, IERC20 currency, uint amount, uint quota, uint start, uint expiry) external payable nonReentrant pauseable {
//        require(msg.sender == tokenAdmin, "token admin only");
//        require(start < expiry && block.timestamp < expiry, "too early expiry");
//        require(_cap > 0 && amount > 0 && quota > 0, "Invalid cap, amount or quota");
//        require(tokens[_symbol] == IERC20(address(0)), "Token exists!"); //检查平台是否存在该token
//
//        IERC20 token = IERC20(new ERC3009Token(_name, _symbol, _decimals, _cap));
//        address pool = FunPool.createPool(address(token), _cap / 2, address(currency), amount-getFeeRateAmount(amount, feeRate));
//        emit CreateTokenAndCreatePool(msg.sender, _symbol, token, pool, block.timestamp);
//
//        tokens[_symbol] = token;
//        supplies[token] = _cap;
//        currencies[token] = currency;
//        amounts[token] = amount;
//        feeRates[token] = feeRate;
//        pools[token] = pool;
//
//        quotas[token] = quota;
//        starts[token] = start;
//        expiries[token] = expiry;
//    }
//    event CreateTokenAndCreatePool(address msgSender, string _symbol, IERC20 indexed token, address pool, uint timestamp);
//
//    //Completed
//    function addLiquidity(IERC20 token, bool success) external payable nonReentrant pauseable {
//        require(msg.sender == tokenAdmin, "create token admin only");
//        require(amounts[token] > 0, "invalid token");
//        require(perSales[token].timestamp > 0, "already added liquidity");
//
//        if (!success) {
//            perSales[token].success = false;
//            perSales[token].addedLiquidity = false;
//            perSales[token].timestamp = block.timestamp;
//            emit AddLiquidity(msg.sender, token, success, block.timestamp);
//            return;
//        }
//
//        uint feeRateAmount = getFeeRateAmount(total, feeRates[token]);
//        uint amountLP;
//        (lpTokenIds[token],amountLP) = FunPool.addPool(address(token), supplies[token]/2, address(currency), amounts[token] - feeRateAmount);
//        currency.safeTransfer(feeTo, amounts[token] - amountLP);
//
//        perSales[token].success = true;
//        perSales[token].addedLiquidity = true;
//        perSales[token].timestamp = block.timestamp;
//        emit AddedLiquidity(msg.sender, token, success, block.timestamp);
//    }
//    event AddedLiquidity(address msgSender, IERC20 indexed token, bool success, uint timestamp);
//
//
//
//
//    //空投，打满添加流动性后，官方会发放一半的代币给用户
//    function airdrops(IERC20 token, uint256[] calldata ids, address[] calldata tos, uint[] calldata amounts) external nonReentrant pauseable {
//        require(msg.sender == airdropAdmin, "airdrop admin only");
//        require(ids.length == tos.length && ids.length == amounts.length, "invalid length");
//
//        for(uint i = 0; i < ids.length; i++) {
//            _airdrop(token, ids[i], tos[i], amounts[i]);
//        }
//    }
//    function _airdrop(IERC20 token, uint id, address to, uint amount) internal {
//        require(airdropped[token][id] == false, "airdropped already");
//        airdropped[token][id] = true;
//
//        airdroppedAmount[token][to] += amount;
//        require(airdroppedAmount[token][to] <= quota[token], "exceed user amount");
//
//        require(perSales[token].addedLiquidity, "need to add liquidity");
//
//        //1.amount是x402支付的时候就确定的
//        //2.token本身就在合约中，直接转移则ok
//        token.safeTransfer(to, amount);
//        emit Airdropped(msg.sender, id, token, to, amount);
//    }
//    event Airdropped(address sender, uint id, IERC20 indexed token, address indexed to, uint amount);
//
//    //退款，只能在结束时间之后，官方调用
//    function refunds(IERC20 token, uint256[] calldata ids, address[] calldata tos, uint[] calldata amounts) external nonReentrant pauseable {
//        require(msg.sender == refundAdmin, "refund admin only");
//        require(ids.length == tos.length && ids.length == amounts.length, "invalid length");
//
//        for(uint i = 0; i < ids.length; i++) {
//            _refund(token, ids[i], tos[i], amounts[i]);
//        }
//    }
//    function _refund(IERC20 token, uint id, address to, uint amount) internal {
//        require(refunded[token][id] == false, "airdropped already");
//        refunded[token][id] = true;
//
//        require(!perSales[token].success && perSales[token].timestamp>0, "need to set failed");
//
//        uint fee = getFeeRateAmount(amount, feeRates[token]);
//        uint refundAmount = amount - fee;
//        address feeTo = feeTo;
//		IERC20 currency = currencies[token];
//
//        currency.safeTransfer(feeTo, fee);
//        currency.safeTransfer(to, refundAmount);
//        emit Refund(token, id, to, fee, refundAmount);
//    }
//    event Refund(IERC20 indexed token, uint id, address indexed to, uint fee, uint refundAmount);
//
////    //手动操作，收集手续费用
////    function collectLpFees(IERC20 token) external nonReentrant {
////        require(address(token) != address(0), "invalid token");
////        IERC20 currency = currencies[token];
////        if(address(currency) == address(0))
////            currency = IERC20(ILiquidityManager(FunPool.liquidityManager()).WETH9());
////        uint amount = currency.balanceOf(address(this));
////        uint volume = token.balanceOf(address(this));
////        ILocker(FunPool.locker()).collect(tokenIds[token]);
////        address swapFeeTo = swapFeeTo;
////        currency.safeTransfer(swapFeeTo, currency.balanceOf(address(this)) - amount);
////        token.safeTransfer(swapFeeTo, token.balanceOf(address(this)) - volume);
////    }
////
//    //更新设置开始时间和结束时间
//    function setTokenTimes(IERC20 token, uint start, uint expiry) external governance {
//        require(amounts[token] > 0, "invalid token");
//        require(start > 0 && expiry > 0 && expiry > start, "invalid start or expiry");
//
//        emit SetTimes(msg.sender, token, starts[token], expiries[token], start, expiry);
//        starts[token] = start;
//        expiries[token] = expiry;
//    }
//    event SetTimes(address indexed sender, IERC20 indexed token, uint oldStart, uint oldExpiry, uint start, uint expiry);
//
//    function getTokenInfo(IERC20 token) public view returns(uint,IERC20,uint,uint,uint,uint, PreSale) {
//        require(amounts[token] > 0, "invalid token");
//        return (supplies[token], currencies[token], amounts[token], starts[token], expiries[token], perSales[token]);
//    }
//
//    function getFeeRateAmount(uint amount, uint _feeRate) public pure returns(uint) {
//        return amount * _feeRate / 1e18;
//    }
//}
