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
   uint256 public constant MIN_AMOUNT = 1e15;
   uint256 public constant ONE_MBTC = 1e18;
   uint256 public constant SECONDS_PER_YEAR = 365 * 86400;
   uint256 public constant SCALE_FACTOR = 1e6;
   uint32 public constant SECONDS_PER_DAY = 86400;
   uint256 private _nonReentrantStatus;
   address public pauseAdmin;
   bool public paused;

   address public tokenAdmin;
   address public airdropAdmin;
   address public refundAdmin;
    address public paymentToken;//default usdc
   address public feeTo;
   address public swapFeeTo;
   uint256 public feeRate; //default 50000 5%
   uint256 public swapFeeRate; //default 10000 1%
    uint256 public tokenAddRate;//default 800000 80%

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
    * @param _tokenAdmin Address of the token admin
    * @param _airdropAdmin Address of the airdrop admin
    * @param _refundAdmin Address of the refund admin
    * @param _feeTo Address of the fee recipient
    * @param _swapFeeTo Address of the swap fee recipient
    */
   function initConfig(address _tokenAdmin, address _airdropAdmin, address _refundAdmin, address _paymentToken, address _feeTo, address _swapFeeTo) external onlyOwner {
       if (_tokenAdmin == address(0)) revert ZeroAddress("token admin");
       if (_airdropAdmin == address(0)) revert ZeroAddress("airdrop admin");
       if (_refundAdmin == address(0)) revert ZeroAddress("refund admin");
       if (_paymentToken == address(0)) revert ZeroAddress("payment token");
       if (_feeTo == address(0)) revert ZeroAddress("fee to");
       if (_swapFeeTo == address(0)) revert ZeroAddress("swap fee to");

       tokenAdmin = _tokenAdmin;
       airdropAdmin = _airdropAdmin;
       refundAdmin = _refundAdmin;
       paymentToken = _paymentToken;
       feeTo = _feeTo;
       swapFeeTo = _swapFeeTo;
       feeRate = 50000; //default 5%
       swapFeeRate = 10000; //default 1%
       tokenAddRate = 800000; //default 80%

       emit InitConfig(msg.sender, _tokenAdmin, _airdropAdmin, _refundAdmin, _paymentToken, _feeTo, _swapFeeTo);
   }

   /**
    * @dev Sets the token admin address
    * Token admin can create tokens and pools
    * @param _account Address of the token admin
    */
   function setTokenAdmin(address _account) public onlyOwner {
       if (_account == address(0)) revert ZeroAddress("set tokenAdmin");
       address oldTokenAdmin = tokenAdmin;
       tokenAdmin = _account;
       emit TokenAdminChanged(msg.sender, oldTokenAdmin, tokenAdmin);
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
       uint256 oldFeeRate = feeRate;
       feeRate = _rate;
       emit FeeRateChanged(msg.sender, oldFeeRate, feeRate);
   }

   /**
    * @dev Sets the swap fee rate
    * Swap fee rate is expressed in basis points (1e18 = 100%)
    * @param _rate Swap fee rate in basis points
    */
   function setSwapFeeRate(uint256 _rate) public onlyOwner {
       uint256 oldSwapFeeRate = swapFeeRate;
       swapFeeRate = _rate;
       emit SwapFeeRateChanged(msg.sender, oldSwapFeeRate, swapFeeRate);
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

//   event UpdateStakeCap(address adminSetter, uint256 oldStakeCap, uint256 stakeCap);
//   event UpdateEndTimestamp(address adminSetter, uint256 oldEndTimestamp, uint256 endTimestamp);
//   event UpdateStakePaused(address adminSetter, bool stakePaused);
//   event SetSpecialCallers(address adminSetter, address caller, bool status);
//   event Stake(address msgSender, StakeItem stakeItem, uint256 stakeTimestamp);
//   event Unstake(address msgSender, StakeItem stakeItem, uint256 unstakeTimestamp);
//   event Withdraw(address msgSender, StakeItem stakeItem, uint256 withdrawTimestamp);
//   event MigrateStake(address msgSender, StakeItem stakeItem, uint256 migrateTimestamp);
//   event MigrateCallerChanged(address adminSetter, address oldCaller, address newCaller);

   // Admin events
   event TokenAdminChanged(address adminSetter, address oldTokenAdmin, address newTokenAdmin);
   event AirdropAdminChanged(address adminSetter, address oldAirdropAdmin, address newAirdropAdmin);
   event RefundAdminChanged(address adminSetter, address oldRefundAdmin, address newRefundAdmin);
   event FeeToChanged(address adminSetter, address oldFeeTo, address newFeeTo);
   event SwapFeeToChanged(address adminSetter, address oldSwapFeeTo, address newSwapFeeTo);
   event FeeRateChanged(address adminSetter, uint256 oldFeeRate, uint256 newFeeRate);
   event SwapFeeRateChanged(address adminSetter, uint256 oldSwapFeeRate, uint256 newSwapFeeRate);
    event InitConfig(address adminSetter, address tokenAdmin, address airdropAdmin, address refundAdmin, address paymentToken, address feeTo, address swapFeeTo);
}
