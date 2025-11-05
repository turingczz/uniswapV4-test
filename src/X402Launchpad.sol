// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;
pragma abicoder v2;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./ERC3009Token.sol";
import "./UniswapV4.sol";
import "./X402LaunchpadCommon.sol";

/**
 * @title X402Launchpad
 * @dev Main launchpad contract for token deployment, liquidity management, and airdrop functionality
 * This contract handles the complete lifecycle of token launches including deployment,
 * liquidity provisioning, airdrops, and refunds. It integrates with Uniswap V4 for liquidity management
 * and follows the UUPS upgradeable pattern for future enhancements.
 */
contract X402Launchpad is X402LaunchpadCommon, UniswapV4 {
    using SafeERC20 for IERC20;

    /// @notice Contract version identifier
    string public constant version = "1.0.0";

    /// @notice Enum representing the different statuses a token can have in the launchpad
    enum TokenStatus {
        Presale, // 0
        AddedLiquidity, // 1
        Refund // 2
    }

    mapping(string => IERC20) public tokens;
    mapping(IERC20 => uint256) public tokenSupplies;
    mapping(IERC20 => IERC20) public fundingTokens;
    mapping(IERC20 => uint256) public fundingAmounts;

    mapping(IERC20 => TokenParams) public params;
    mapping(IERC20 => uint256) public lpTokenIds;
    mapping(IERC20 => TokenStatus) public tokenStatus;
    mapping(IERC20 => mapping(address => bool)) public airdropped;
    mapping(IERC20 => mapping(address => bool)) public refunded;

    // Event definitions
    event Deploy(address msgSender, string symbol, IERC20 indexed token, uint256 timestamp, TokenParams p);
    event LiquidityAdded(address msgSender, IERC20 indexed token, uint256 lpTokenId, uint256 timestamp, TokenParams p);
    event Airdropped(address sender, IERC20 indexed token, address indexed to, uint256 amount);
    event Refund(IERC20 indexed token, IERC20 indexed fundingToken, address indexed to, uint256 amount);
    event SwapFeesCollected(IERC20 indexed _token, uint256 fundingSwapFee, uint256 tokenSwapFee);

    /**
     * @dev Constructor for X402Launchpad contract
     * Initializes the Uniswap V4 integration and disables initializers for upgradeable pattern
     * @param _poolManger Address of the Uniswap V4 Pool Manager contract
     * @param _positionManger Address of the Uniswap V4 Position Manager contract
     * @param _permit2 Address of the Permit2 contract for token approvals
     */
    constructor(
        address _poolManger,
        address _positionManger,
        address _permit2
    )
        UniswapV4(_poolManger, _positionManger, _permit2)
    {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with the specified owner
     * Sets up the upgradeable contract with initial ownership
     * @param _initialOwner Address of the initial contract owner
     */
    function initialize(address _initialOwner) public override initializer {
        super.initialize(_initialOwner);
    }

    /**
     * @dev Deploys a new token and sets up the initial pool configuration
     * Creates a new ERC3009 token, calculates liquidity parameters, and initializes the Uniswap pool
     * Can only be called by the token admin when contract is not paused
     * @param _name Name of the new token
     * @param _symbol Symbol of the new token
     * @param _decimals Number of decimals for the token
     * @param _cap Total supply cap of the token
     * @param _fundingToken Address of the funding token (e.g., USDC, USDT)
     * @param _fundingAmount Amount of funding token for liquidity
     */
    function deploy(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _cap,
        IERC20 _fundingToken,
        uint256 _fundingAmount
    )
        external
        nonReentrant
        whenNotPaused
        onlyCreateTokenAdmin
    {
        if(bytes(_name).length == 0) revert ZeroValue("name");
        if(bytes(_symbol).length == 0) revert ZeroValue("symbol");
        if(_cap == 0) revert ZeroValue("cap");
        if(fundingTokens[_fundingToken] == IERC20(address(0))) revert ZeroAddress("fundingToken");
        if(_fundingAmount == 0) revert ZeroValue("fundingAmount");
        if(tokens[_symbol] != IERC20(address(0))) revert AlreadyTokenExists(_symbol);

        IERC20 token = IERC20(new ERC3009Token(_name, _symbol, _cap, _decimals));
        uint256 tokenAddLiquidity = _cap * tokenAddLiquidityRate / SCALE_FACTOR; // 20% of total supply for liquidity
        uint256 fundingTokenAddLiquidity = _fundingAmount; // x402 has already paid 5% fee
        bool fundingTokenIsToken0 = address(_fundingToken) < address(token);

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

        _initializePool(p, uint24(swapFeeRate), tickSpacing);
        emit Deploy(msg.sender, _symbol, token, block.timestamp, p);

        tokens[_symbol] = token;
        tokenSupplies[token] = _cap;
        fundingTokens[token] = _fundingToken;
        fundingAmounts[token] = _fundingAmount;
        params[token] = p;
    }

    /**
     * @dev Adds liquidity to the token's Uniswap pool
     * Transfers funding tokens and deploys liquidity to the Uniswap pool
     * Can only be called by the liquidity admin when contract is not paused and token is in presale status
     * @param _token Address of the token to add liquidity for
     */
    function addLiquidity(IERC20 _token)
        external
        nonReentrant
        whenNotPaused
        onlyAddLiquidityAdmin
    {
        if(tokenSupplies[_token] == 0) revert NotExistToken(_token);
        if(tokenStatus[_token] != TokenStatus.Presale) revert InvalidTokenStatus(_token);
        TokenParams storage p = params[_token];
        tokenStatus[_token] = TokenStatus.AddedLiquidity;

        fundingTokens[_token].safeTransferFrom(fundingCollectAddress, address(this), p.fundingTokenAmount);
        lpTokenIds[_token] = _deployLiquidity(p, swapFeeRate, tickSpacing);
        emit LiquidityAdded(msg.sender, _token, lpTokenIds[_token], block.timestamp, p);
    }

    /**
     * @dev Batch airdrop tokens to multiple users
     * After liquidity is fully added, the official will distribute 80% of tokens to users
     * Can only be called by the airdrop admin when contract is not paused and token has liquidity
     * @param _token Address of the token to airdrop
     * @param _tos Array of recipient addresses
     * @param _amount Amount of tokens to airdrop to each recipient
     */
    function batchAirdrop(
        IERC20 _token,
        address[] calldata _tos,
        uint256 _amount
    )
        external
        nonReentrant
        whenNotPaused
        onlyAirdropAdmin
    {
        if(_tos.length <= 0) revert InvalidArrayLength();
        if(tokenStatus[_token] != TokenStatus.AddedLiquidity) revert InvalidTokenStatus(_token);

        for (uint256 i = 0; i < _tos.length; i++) {
            _airdrop(_token, _tos[i], _amount);
        }
    }

    /**
     * @dev Internal function to airdrop tokens to a single user
     * 1. The amount per user is determined when x402 payment is made
     * 2. Tokens are already in the contract, so direct transfer is sufficient
     * @param _token Address of the token to airdrop
     * @param _to Recipient address
     * @param _amount Amount of tokens to airdrop
     */
    function _airdrop(IERC20 _token, address _to, uint256 _amount) internal {
        if (airdropped[_token][_to]) revert AlreadyAirdropped(_to);
        airdropped[_token][_to] = true;

        _token.safeTransfer(_to, _amount);
        emit Airdropped(msg.sender, _token, _to, _amount);
    }

    /**
     * @dev Batch refund funding tokens to multiple users
     * Can only be called after the end time by the official
     * @param _token Address of the token to process refunds for
     * @param _tos Array of recipient addresses
     * @param _amounts Array of funding tokens
     */
    function batchRefund(
        IERC20 _token,
        address[] calldata _tos,
        uint256[] calldata _amounts
    )
        external
        nonReentrant
        whenNotPaused
        onlyRefundAdmin
    {
        if(tokenSupplies[_token] == 0) revert NotExistToken(_token);
        if(_tos.length == 0 || _tos.length != _amounts.length) revert InvalidArrayLength();
        if(tokenStatus[_token] != TokenStatus.Presale && tokenStatus[_token] != TokenStatus.Refund) revert InvalidTokenStatus(_token);

        if (tokenStatus[_token] == TokenStatus.Presale) tokenStatus[_token] = TokenStatus.Refund;
        for (uint256 i = 0; i < _tos.length; i++) {
            _refund(_token, _tos[i], _amounts[i]);
        }
    }

    /**
     * @dev Internal function to refund funding tokens to a single user
     * @param _token Address of the token to process refund for
     * @param _to Recipient address
     * @param _amount Amount of funding tokens to refund
     */
    function _refund(IERC20 _token, address _to, uint256 _amount) internal {
        if (refunded[_token][_to]) revert AlreadyRefunded(_to);
        refunded[_token][_to] = true;

        fundingTokens[_token].safeTransferFrom(fundingCollectAddress, _to, _amount);
        emit Refund(_token, fundingTokens[_token], _to, _amount);
    }

    /**
     * @dev Manually collect swap fees from the liquidity pool
     * Collects accumulated swap fees and transfers them to the designated fee recipient
     * @param _token Address of the token to collect fees for
     */
    function collectSwapFees(IERC20 _token) external nonReentrant {
        if(tokenStatus[_token] != TokenStatus.AddedLiquidity) revert InvalidTokenStatus(_token);
        uint256 lpTokenId = lpTokenIds[_token];
        if(lpTokenId == 0) revert ZeroValue("lpTokenId");

        IERC20 fundingToken = fundingTokens[_token];
        uint256 fundingAmount = fundingToken.balanceOf(address(this));
        uint256 tokenAmount = _token.balanceOf(address(this));
        _collectLpSwapFees(lpTokenId);
        uint256 fundingSwapFee = fundingToken.balanceOf(address(this)) - fundingAmount;
        uint256 tokenSwapFee = _token.balanceOf(address(this)) - tokenAmount;

        fundingToken.safeTransfer(swapFeeTo, fundingSwapFee);
        _token.safeTransfer(swapFeeTo, tokenSwapFee);
        emit SwapFeesCollected(_token, fundingSwapFee, tokenSwapFee);
    }
}
