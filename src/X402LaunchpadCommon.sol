// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {stdError} from "forge-std/StdError.sol";

/**
 * @title X402LaunchpadCommon
 * @dev Base contract for X402 launchpad functionality
 * Provides common launchpad logic, admin management, pause controls, and upgradeability
 * This contract is designed to be inherited by the main X402Launchpad contract
 */
contract X402LaunchpadCommon is OwnableUpgradeable, UUPSUpgradeable {
    uint256 public constant SCALE_FACTOR = 1e6;
    uint24 public constant DEFAULT_SWAP_FEE_RATE = 3000; // 0.3%
    int24 public constant DEFAULT_TICK_SPACING = 60; //with 0.3%
    uint32 public constant DEFAULT_TOKEN_ADD_LIQUIDITY_RATE = 200_000; // 20%

    uint8 private _nonReentrantStatus;
    bool public paused;
    address public pauseAdmin;

    address public createTokenAdmin;
    address public addLiquidityAdmin;
    address public airdropAdmin;
    address public refundAdmin;
    address public fundingCollectAddress;
    address public swapFeeTo;
    uint24 public swapFeeRate; //default 3000 0.3%
    int24 public tickSpacing;
    uint32 public tokenAddLiquidityRate; //default 200000 20%

    uint256[50] __commGap;

    modifier nonReentrant() {
        if (_nonReentrantStatus != 0) revert ReentrancyGuardStatus();
        _nonReentrantStatus = 1;
        _;
        _nonReentrantStatus = 0;
    }

    modifier onlyCreateTokenAdmin() {
        if(msg.sender != createTokenAdmin) revert NotAdmin("create token admin");
        _;
    }

    modifier onlyAddLiquidityAdmin() {
        if(msg.sender != addLiquidityAdmin) revert NotAdmin("add liquidity admin");
        _;
    }

    modifier onlyAirdropAdmin() {
        if(msg.sender != airdropAdmin) revert NotAdmin("airdrop admin");
        _;
    }

    modifier onlyRefundAdmin() {
        if(msg.sender != refundAdmin) revert NotAdmin("refund admin");
        _;
    }

    /**
     * @dev Authorizes the upgrade of the contract
     * Only the contract owner can authorize upgrades (UUPS pattern)
     * @param _newImplementation The address of the new implementation contract
     */
    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner {
        // Only admin can upgrade the contract
    }

    /**
     * @dev Initializes the contract with the specified owner
     * Sets up basic ownership and upgradeability functionality
     * @param _initialOwner Address of the initial contract owner
     */
    function initialize(address _initialOwner) public virtual initializer {
        if (_initialOwner == address(0)) revert ZeroAddress("init owner");
        __Ownable_init_unchained(_initialOwner);
        __UUPSUpgradeable_init();
    }

    /**
     * @dev Initializes contract configuration after deployment
     * Sets up all essential contract addresses and parameters
     * Can only be called by contract owner
     * @param _createTokenAdmin Address of the token admin
     * @param _addLiquidityAdmin Address of the add liquidity admin
     * @param _airdropAdmin Address of the airdrop admin
     * @param _refundAdmin Address of the refund admin
     * @param _swapFeeTo Address of the swap fee recipient
     */
    function initConfig(
        address _createTokenAdmin,
        address _addLiquidityAdmin,
        address _airdropAdmin,
        address _refundAdmin,
        address _fundingCollectAddress,
        address _swapFeeTo
    )
        external
        onlyOwner
    {
        if (_createTokenAdmin == address(0)) revert ZeroAddress("token admin");
        if (_addLiquidityAdmin == address(0)) revert ZeroAddress("add liquidity admin");
        if (_airdropAdmin == address(0)) revert ZeroAddress("airdrop admin");
        if (_refundAdmin == address(0)) revert ZeroAddress("refund admin");
        if (_fundingCollectAddress == address(0)) revert ZeroAddress("funding collect address");
        if (_swapFeeTo == address(0)) revert ZeroAddress("swap fee to");

        createTokenAdmin = _createTokenAdmin;
        addLiquidityAdmin = _addLiquidityAdmin;
        airdropAdmin = _airdropAdmin;
        refundAdmin = _refundAdmin;
        fundingCollectAddress = _fundingCollectAddress;
        swapFeeTo = _swapFeeTo;
        swapFeeRate = DEFAULT_SWAP_FEE_RATE; //default 0.3%
        tickSpacing = DEFAULT_TICK_SPACING; //default for 0.3%
        tokenAddLiquidityRate = DEFAULT_TOKEN_ADD_LIQUIDITY_RATE; //default 20%

        emit InitConfig(
            msg.sender,
            _createTokenAdmin,
            _addLiquidityAdmin,
            _airdropAdmin,
            _refundAdmin,
            _fundingCollectAddress,
            _swapFeeTo
        );
    }

    /**
     * @dev Sets the token admin address
     * Token admin can create tokens and pools
     * @param _account Address of the token admin
     */
    function setCreateTokenAdmin(address _account) public onlyOwner {
        if (_account == address(0)) revert ZeroAddress("set createTokenAdmin");
        address oldCreateTokenAdmin = createTokenAdmin;
        createTokenAdmin = _account;
        emit CreateTokenAdminChanged(msg.sender, oldCreateTokenAdmin, createTokenAdmin);
    }

    /**
     * @dev Sets the add liquidity admin address
     * Add liquidity admin can add liquidity to pools
     * @param _account Address of the add liquidity admin
     */
    function setAddLiquidityAdmin(address _account) public onlyOwner {
        if (_account == address(0)) revert ZeroAddress("set addLiquidityAdmin");
        address oldAddLiquidityAdmin = addLiquidityAdmin;
        addLiquidityAdmin = _account;
        emit AddLiquidityAdminChanged(msg.sender, oldAddLiquidityAdmin, addLiquidityAdmin);
    }

    /**
     * @dev Sets the airdrop admin address
     * Airdrop admin can perform airdrop operations
     * @param _account Address of the airdrop admin
     */
    function setAirdropAdmin(address _account) public onlyOwner {
        if (_account == address(0)) revert ZeroAddress("set airdropAdmin");
        address oldAirdropAdmin = airdropAdmin;
        airdropAdmin = _account;
        emit AirdropAdminChanged(msg.sender, oldAirdropAdmin, airdropAdmin);
    }

    /**
     * @dev Sets the refund admin address
     * Refund admin can perform refund operations
     * @param _account Address of the refund admin
     */
    function setRefundAdmin(address _account) public onlyOwner {
        if (_account == address(0)) revert ZeroAddress("set refundAdmin");
        address oldRefundAdmin = refundAdmin;
        refundAdmin = _account;
        emit RefundAdminChanged(msg.sender, oldRefundAdmin, refundAdmin);
    }

    /**
     * @dev Sets the funding collect address
     * Funding collect address is used to collect funding tokens for liquidity
     * @param _account Address of the funding collect address
     */
    function setFundingCollectAddress(address _account) public onlyOwner {
        if (_account == address(0)) revert ZeroAddress("set fundingCollectAddress");
        address oldFundingCollectAddress = fundingCollectAddress;
        fundingCollectAddress = _account;
        emit FundingCollectAddressChanged(msg.sender, oldFundingCollectAddress, fundingCollectAddress);
    }

    /**
     * @dev Sets the swap fee recipient address
     * Swap fee recipient receives swap fees
     * @param _account Address of the swap fee recipient
     */
    function setSwapFeeTo(address _account) public onlyOwner {
        if (_account == address(0)) revert ZeroAddress("set swapFeeTo");
        address oldSwapFeeTo = swapFeeTo;
        swapFeeTo = _account;
        emit SwapFeeToChanged(msg.sender, oldSwapFeeTo, swapFeeTo);
    }

    /**
     * @dev Sets the swap fee rate
     * Swap fee rate is expressed in basis points (1e6 = 100%)
     * @param _rate Swap fee rate in basis points
     */
    function setSwapFeeRate(uint24 _rate, int24 _tickSpacing) public onlyOwner {
        if (_rate == 0) revert ZeroValue("rate");
        if (_tickSpacing == 0) revert ZeroValue("tickSpacing");

        uint24 oldSwapFeeRate = swapFeeRate;
        int24 oldTickSpacing = tickSpacing;
        swapFeeRate = _rate;
        tickSpacing = _tickSpacing;
        emit SwapFeeRateChanged(msg.sender, oldSwapFeeRate, swapFeeRate, oldTickSpacing, tickSpacing);
    }

    /**
     * @dev Sets the token add liquidity rate
     * Token add liquidity rate is expressed in basis points (1e6 = 100%)
     * @param _rate Token add liquidity rate in basis points
     */
    function setTokenAddLiquidityRate(uint32 _rate) public onlyOwner {
        if (_rate == 0) revert ZeroValue("rate");
        uint32 oldTokenAddLiquidityRate = tokenAddLiquidityRate;
        tokenAddLiquidityRate = _rate;
        emit TokenAddLiquidityRateChanged(msg.sender, oldTokenAddLiquidityRate, tokenAddLiquidityRate);
    }

    // Pause ...
    function setPauseAdmin(address _account) public onlyOwner {
        if (_account == address(0)) revert ZeroAddress("set pauseAdmin");
        address oldPauseAdmin = pauseAdmin;
        pauseAdmin = _account;
        emit PauseAdminChanged(msg.sender, oldPauseAdmin, pauseAdmin);
    }

    modifier whenNotPaused() {
        if (paused) revert AlreadyPaused();
        _;
    }

    /**
     * @dev Pause the activity, only by pauseAdmin.
     */
    function pause() public whenNotPaused {
        if (msg.sender != pauseAdmin) revert IllegalPausePermissions(msg.sender);
        paused = true;
        emit PauseEvent(msg.sender, paused);
    }

    /**
     * @dev Unpause the activity, only by owner.
     */
    function unpause() public onlyOwner {
        paused = false;
        emit PauseEvent(msg.sender, paused);
    }

    // Error definitions
    error ZeroAddress(string msg);
    error ZeroValue(string msg);
    error NotAdmin(string msg);
    error NotExistToken(IERC20 token);
    error AlreadyTokenExists(string symbol);
    error AlreadyAirdropped(address account);
    error AlreadyRefunded(address account);
    error InvalidTokenStatus(IERC20 token);
    error InvalidArrayLength();
    error IllegalPausePermissions(address sender);
    error AlreadyPaused();
    error ReentrancyGuardStatus();

    // Event definitions
    event PauseAdminChanged(address adminSetter, address oldAddress, address newAddress);
    event PauseEvent(address adminSetter, bool paused);

    // Admin events
    event CreateTokenAdminChanged(address adminSetter, address oldCreateTokenAdmin, address newCreateTokenAdmin);
    event AddLiquidityAdminChanged(address adminSetter, address oldAddLiquidityAdmin, address newAddLiquidityAdmin);
    event AirdropAdminChanged(address adminSetter, address oldAirdropAdmin, address newAirdropAdmin);
    event RefundAdminChanged(address adminSetter, address oldRefundAdmin, address newRefundAdmin);
    event FundingCollectAddressChanged(address adminSetter, address oldFundingCollectAddress, address newFundingCollectAddress);
    event SwapFeeToChanged(address adminSetter, address oldSwapFeeTo, address newSwapFeeTo);
    event SwapFeeRateChanged(address adminSetter, uint24 oldSwapFeeRate, uint24 newSwapFeeRate, int24 oldTickSpacing, int24 newTickSpacing);
    event TokenAddLiquidityRateChanged(
        address adminSetter, uint32 oldTokenAddLiquidityRate, uint32 newTokenAddLiquidityRate
    );
    event InitConfig(
        address adminSetter,
        address createTokenAdmin,
        address addLiquidityAdmin,
        address airdropAdmin,
        address refundAdmin,
        address fundingCollectAddress,
        address swapFeeTo
    );
}
