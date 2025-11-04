// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;
pragma abicoder v2;

import { Context } from "@openzeppelin/contracts/utils/Context.sol";
import { ContextUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ERC3009Token.sol";
import "./UniswapV4.sol";
import "./X402LaunchpadCommon.sol";

contract X402Launchpad is X402LaunchpadCommon, UniswapV4 {
    using SafeERC20 for IERC20;

    string public constant version = "1.0.0";

    enum TokenStatus {
        PreSale, // 0
        AddedLiquidity, // 1
        Refund // 2

    }

    mapping(string => IERC20) public tokens;
    mapping(IERC20 => uint256) public tokenSupplies;
    mapping(IERC20 => IERC20) public fundingTokens;
    mapping(IERC20 => uint256) public fundingAmounts;

    mapping(IERC20 => TokenParams) public params;
    mapping(IERC20 => uint256) public lpTokenIds;
    mapping(IERC20 => TokenStatus) public tokenStatus; //0 presale 1 added liquidity 2 refund
        //合约不管理失败，只看成功发射的状态；第一次refund，就标识为refund；只有成功才能空投
    mapping(IERC20 => mapping(address => bool)) public airdropped; //to是否空投
    mapping(IERC20 => mapping(address => bool)) public refunded; //to是否退款

    constructor(
        address _poolManger,
        address _positionManger,
        address _permit2
    )
        UniswapV4(_poolManger, _positionManger, _permit2)
    {
        _disableInitializers();
    }

    function initialize(address _initialOwner) public override initializer {
        super.initialize(_initialOwner);
    }

    //创建token，创建交易池
    function deploy(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _cap,
        IERC20 _fundingToken,
        uint256 _fundingAmount
    )
        external
        payable
        nonReentrant
        whenNotPaused
    {
        require(msg.sender == createTokenAdmin, "token admin only");
        require(_cap > 0 && _fundingAmount > 0, "Invalid cap, amount");
        require(tokens[_symbol] == IERC20(address(0)), "Token exists!");

        IERC20 token = IERC20(new ERC3009Token(_name, _symbol, _cap, _decimals));
        bool fundingTokenIsToken0 = address(_fundingToken) < address(token);
        uint256 tokenAddLiquidity = _cap * tokenAddLiquidityRate / SCALE_FACTOR; //20%
        uint256 fundingTokenAddLiquidity = _fundingAmount; //x402已经支付了fee 5%

        TokenParams memory p = TokenParams({
            fundingToken: address(_fundingToken),
            token: address(token),
            fundingTokenAmount: fundingTokenAddLiquidity,
            tokenAmount: tokenAddLiquidity,
            fundingTokenIsToken0: fundingTokenIsToken0,
            sqrtPriceFundingTokenFirst: 0,
            sqrtPriceTokenFirst: 0
        });
        (p.sqrtPriceFundingTokenFirst, p.sqrtPriceTokenFirst) =
            _calculateSqrtPrices(fundingTokenAddLiquidity, tokenAddLiquidity, fundingTokenIsToken0);
        _initializePool(p, uint24(swapFeeRate), 200);
        emit CreateTokenAndCreatePool(msg.sender, _symbol, token, block.timestamp, p);

        tokens[_symbol] = token;
        tokenSupplies[token] = _cap;
        fundingTokens[token] = _fundingToken;
        fundingAmounts[token] = _fundingAmount;
        params[token] = p;
    }

    event CreateTokenAndCreatePool(
        address msgSender, string _symbol, IERC20 indexed token, uint256 timestamp, TokenParams p
    );

    //Completed
    function addLiquidity(IERC20 _token) external payable nonReentrant whenNotPaused {
        require(msg.sender == addLiquidityAdmin, "add liquidity admin only");
        require(tokenStatus[_token] == TokenStatus.PreSale, "can not add liquidity");

        TokenParams storage p = params[_token];
        tokenStatus[_token] = TokenStatus.AddedLiquidity;

        fundingTokens[_token].safeTransferFrom(fundingCollectAddress, address(this), p.fundingTokenAmount);
        lpTokenIds[_token] = _deployLiquidity(p, swapFeeRate, 200);
        emit AddedLiquidity(msg.sender, _token, block.timestamp);
    }

    event AddedLiquidity(address msgSender, IERC20 indexed token, uint256 timestamp);

    //空投，打满添加流动性后，官方会发放80%的代币给用户
    function batchAirdrop(
        IERC20 _token,
        address[] calldata _tos,
        uint256[] calldata _amounts
    )
        external
        nonReentrant
        whenNotPaused
    {
        require(msg.sender == airdropAdmin, "airdrop admin only");
        require(_tos.length > 0 && _tos.length == _amounts.length, "invalid length");
        require(tokenStatus[_token] == TokenStatus.AddedLiquidity, "can not airdrop");

        for (uint256 i = 0; i < _tos.length; i++) {
            _airdrop(_token, _tos[i], _amounts[i]);
        }
    }

    function _airdrop(IERC20 _token, address _to, uint256 _amount) internal {
        require(airdropped[_token][_to] == false, "already airdropped");
        airdropped[_token][_to] = true;

        //1.单个用户amount是x402支付的时候就确定的
        //2.token本身就在合约中，直接转移则ok
        _token.safeTransfer(_to, _amount);
        emit Airdropped(msg.sender, _token, _to, _amount);
    }

    event Airdropped(address sender, IERC20 indexed token, address indexed to, uint256 amount);

    //退款，只能在结束时间之后，官方调用
    function batchRefund(
        IERC20 _token,
        address[] calldata _tos,
        uint256[] calldata _amounts
    )
        external
        nonReentrant
        whenNotPaused
    {
        require(msg.sender == refundAdmin, "refund admin only");
        require(_tos.length > 0 && _tos.length == _amounts.length, "invalid length");
        require(
            tokenStatus[_token] == TokenStatus.PreSale || tokenStatus[_token] == TokenStatus.Refund, "can not refund"
        );
        if (tokenStatus[_token] == TokenStatus.PreSale) tokenStatus[_token] = TokenStatus.Refund;

        for (uint256 i = 0; i < _tos.length; i++) {
            _refund(_token, _tos[i], _amounts[i]);
        }
    }

    function _refund(IERC20 token, address to, uint256 amount) internal {
        require(refunded[token][to] == false, "airdropped already");
        refunded[token][to] = true;

        IERC20 fundingToken = fundingTokens[token];
        fundingToken.safeTransfer(to, amount);
        emit Refund(token, to, amount);
    }

    event Refund(IERC20 indexed token, address indexed to, uint256 amount);

    //手动操作，收集手续费用
    function collectSwapFees(IERC20 _token) external nonReentrant {
        require(address(_token) != address(0), "invalid token");
        uint256 lpTokenId = lpTokenIds[_token];
        require(lpTokenId != 0, "not exist token");

        IERC20 fundingToken = fundingTokens[_token];
        uint256 fundingAmount = fundingToken.balanceOf(address(this));
        uint256 tokenAmount = _token.balanceOf(address(this));
        _collectLpSwapFees(lpTokenId);
        uint256 fundingSwapFee = fundingToken.balanceOf(address(this)) - fundingAmount;
        uint256 tokenSwapFee = _token.balanceOf(address(this)) - tokenAmount;

        fundingToken.safeTransfer(swapFeeTo, fundingSwapFee);
        _token.safeTransfer(swapFeeTo, tokenSwapFee);
        emit CollectSwapFees(_token, fundingSwapFee, tokenSwapFee);
    }

    event CollectSwapFees(IERC20 indexed _token, uint256 fundingSwapFee, uint256 tokenSwapFee);
}
