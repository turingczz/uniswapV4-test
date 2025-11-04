// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title Common
 * @dev Base contract for BTC staking functionality
 * Provides common staking logic, period management, pause controls, and upgradeability
 * This contract is designed to be inherited by specific staking implementations
 */
contract X402LaunchpadCommon is OwnableUpgradeable, UUPSUpgradeable {
    uint256 public constant SCALE_FACTOR = 1e6;
    uint256 private _nonReentrantStatus;
    address public pauseAdmin;
    bool public paused;

    address public createTokenAdmin;
    address public addLiquidityAdmin;
    address public airdropAdmin;
    address public refundAdmin;
    address public usdcReceiveAddress;
    address public feeTo;
    address public swapFeeTo;
    uint256 public FeeRate; //default 50000 5%
    uint24 public swapFeeRate; //default 3000 0.3% 标准交易对（最常用）
    uint256 public tokenAddLiquidityRate; //default 200000 20%

    uint256[50] __commGap;

    modifier nonReentrant() {
        if (_nonReentrantStatus != 0) revert ReentrancyGuardStatus();
        _nonReentrantStatus = 1;
        _;
        _nonReentrantStatus = 0;
    }

    receive() external payable {
        emit DepositBtc(msg.sender, msg.value, block.number, block.timestamp);
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
     * @param _feeTo Address of the fee recipient
     * @param _swapFeeTo Address of the swap fee recipient
     */
    function initConfig(
        address _createTokenAdmin,
        address _addLiquidityAdmin,
        address _airdropAdmin,
        address _refundAdmin,
        address _usdcReceiveAddress,
        address _feeTo,
        address _swapFeeTo
    )
        external
        onlyOwner
    {
        if (_createTokenAdmin == address(0)) revert ZeroAddress("token admin");
        if (_addLiquidityAdmin == address(0)) revert ZeroAddress("add liquidity admin");
        if (_airdropAdmin == address(0)) revert ZeroAddress("airdrop admin");
        if (_refundAdmin == address(0)) revert ZeroAddress("refund admin");
        if (_usdcReceiveAddress == address(0)) revert ZeroAddress("usdc receive address");
        if (_feeTo == address(0)) revert ZeroAddress("fee to");
        if (_swapFeeTo == address(0)) revert ZeroAddress("swap fee to");

        createTokenAdmin = _createTokenAdmin;
        addLiquidityAdmin = _addLiquidityAdmin;
        airdropAdmin = _airdropAdmin;
        refundAdmin = _refundAdmin;
        usdcReceiveAddress = _usdcReceiveAddress;
        feeTo = _feeTo;
        swapFeeTo = _swapFeeTo;
        FeeRate = 50_000; //default 5%
        swapFeeRate = 10_000; //default 1%
        tokenAddLiquidityRate = 200_000; //default 20%

        emit InitConfig(
            msg.sender,
            _createTokenAdmin,
            _addLiquidityAdmin,
            _airdropAdmin,
            _refundAdmin,
            _usdcReceiveAddress,
            _feeTo,
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
     * @dev Sets the payment token address
     * Payment token is used for swaps and airdrops
     * @param _account Address of the payment token
     */
    function setUsdcReceiveAddress(address _account) public onlyOwner {
        if (_account == address(0)) revert ZeroAddress("set usdcReceiveAddress");
        address oldUsdcReceiveAddress = usdcReceiveAddress;
        usdcReceiveAddress = _account;
        emit UsdcReceiveAddressChanged(msg.sender, oldUsdcReceiveAddress, usdcReceiveAddress);
    }

    /**
     * @dev Sets the fee recipient address
     * Fee recipient receives protocol fees
     * @param _account Address of the fee recipient
     */
    function setFeeTo(address _account) public onlyOwner {
        if (_account == address(0)) revert ZeroAddress("set feeTo");
        address oldFeeTo = feeTo;
        feeTo = _account;
        emit FeeToChanged(msg.sender, oldFeeTo, feeTo);
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
     * @dev Sets the protocol fee rate
     * Fee rate is expressed in basis points (1e18 = 100%)
     * @param _rate Fee rate in basis points
     */
    function setFeeRate(uint256 _rate) public onlyOwner {
        uint256 oldFeeRate = FeeRate;
        FeeRate = _rate;
        emit FeeRateChanged(msg.sender, oldFeeRate, FeeRate);
    }

    /**
     * @dev Sets the swap fee rate
     * Swap fee rate is expressed in basis points (1e18 = 100%)
     * @param _rate Swap fee rate in basis points
     */
    function setSwapFeeRate(uint24 _rate) public onlyOwner {
        uint24 oldSwapFeeRate = swapFeeRate;
        swapFeeRate = _rate;
        emit SwapFeeRateChanged(msg.sender, oldSwapFeeRate, swapFeeRate);
    }

    /**
     * @dev Sets the token add rate
     * Token add rate is expressed in basis points (1e18 = 100%)
     * @param _rate Token add rate in basis points
     */
    function setTokenAddLiquidityRate(uint256 _rate) public onlyOwner {
        uint256 oldTokenAddLiquidityRate = tokenAddLiquidityRate;
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
    error DirectTransferRejected(uint32 period, address caller);
    error OverStakeCap();
    error InvalidSpecialCaller();
    error InvalidEndTime(string msg);
    error StakePaused();
    error InvalidAmount();
    error AlreadyWithdrawRewards(address staker);
    error IllegalPausePermissions(address sender);
    error AlreadyPaused();
    error ReentrancyGuardStatus();
    error InvalidMigratePeriod();
    error CanNotMigrate(uint32 period);
    error InvalidMigrateCaller();
    error NotFoundStakingItem(uint32 id);
    error InvalidMigrateId(uint32 id);
    error ExistStakingItem(uint32 id);
    error NotDueYetItem(uint32 id);
    error NotExistNextItem(uint32 id);
    error AlreadyUnstakedItem(uint32 id);
    error AlreadyWithdrawn(uint32 id);
    error UnsetPeriodApr(uint32 period);
    error InsufficientRewardsAmount(uint32 id);
    error InsufficientAmount(uint32 id);
    error InvalidArrayLength();
    error InvalidPeriod(uint32 period);
    error PeriodNotStake(uint32 period);
    error PeriodNotStart(uint32 period);
    error PeriodExpired(uint32 period);

    // Event definitions
    event DepositBtc(address indexed from, uint256 amount, uint256 blockNumber, uint256 blockTimestamp);
    event PauseAdminChanged(address adminSetter, address oldAddress, address newAddress);
    event PauseEvent(address adminSetter, bool paused);

    // Admin events
    event CreateTokenAdminChanged(address adminSetter, address oldCreateTokenAdmin, address newCreateTokenAdmin);
    event AddLiquidityAdminChanged(address adminSetter, address oldAddLiquidityAdmin, address newAddLiquidityAdmin);
    event AirdropAdminChanged(address adminSetter, address oldAirdropAdmin, address newAirdropAdmin);
    event RefundAdminChanged(address adminSetter, address oldRefundAdmin, address newRefundAdmin);
    event UsdcReceiveAddressChanged(address adminSetter, address oldUsdcReceiveAddress, address newUsdcReceiveAddress);
    event FeeToChanged(address adminSetter, address oldFeeTo, address newFeeTo);
    event SwapFeeToChanged(address adminSetter, address oldSwapFeeTo, address newSwapFeeTo);
    event FeeRateChanged(address adminSetter, uint256 oldFeeRate, uint256 newFeeRate);
    event SwapFeeRateChanged(address adminSetter, uint24 oldSwapFeeRate, uint24 newSwapFeeRate);
    event TokenAddLiquidityRateChanged(
        address adminSetter, uint256 oldTokenAddLiquidityRate, uint256 newTokenAddLiquidityRate
    );
    event InitConfig(
        address adminSetter,
        address createTokenAdmin,
        address addLiquidityAdmin,
        address airdropAdmin,
        address refundAdmin,
        address paymentToken,
        address feeTo,
        address swapFeeTo
    );
}
