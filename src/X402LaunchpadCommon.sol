// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
//import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
//import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

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
   uint256 public constant APR_SCALE_FACTOR = 1e6;
   uint32 public constant SECONDS_PER_DAY = 86400;
   uint256 private _nonReentrantStatus;
   address public pauseAdmin;
   bool public paused;
   bool public stakePaused = false;

   uint256 public totalStakeAmount;
   uint32 public currentPeriod;
   uint32 public totalPeriods;
   uint32 public stakeId;
   address public mbtcToken;
   address public swapContract;
   address public oldStakeBtcContract;
   address public rewardsSourceAddress;
   address public migrateCaller;
   mapping(address => bool) public specialCallers;


   //new
   address public tokenAdmin;
   address public airdropAdmin;
   address public refundAdmin;
   address public feeTo;
   address public swapFeeTo;
   uint256 public feeRate;
   uint256 public swapFeeRate;

   // Period struct
   struct PeriodConfig {
       uint32 startTimestamp;  // Period start time, staking not allowed before this time
       uint32 ndays;           // Number of days for the staking period
       uint32 endTimestamp;    // Period end time, staking not allowed after this time
       uint32 apr;             // Annual percentage rate for the period (150000 = 15%)
       uint256 stakeCap;       // Maximum staking amount cap for the period
   }
   mapping(uint32 => PeriodConfig) public periodConfigs;

   struct StakeItem {
       address account;
       uint32 id;
       uint32 period;
       uint32 startTimestamp;
       uint32 endTimestamp;
       uint32 unstakeTimestamp;
       uint32 withdrawTimestamp;
       uint32 updateTimestamp;
       uint256 amount;
       uint256 rewards;
   }
   mapping(uint256 => StakeItem) public stakeItems; // id => StakeItem
   mapping(address => uint256) public userStakeAmount; // user => total amount
   mapping(uint32 => uint256) public periodStakeAmount; // period => total amount

   modifier nonReentrant() {
       if (_nonReentrantStatus != 0) revert ReentrancyGuardStatus();
       _nonReentrantStatus = 1;
       _;
       _nonReentrantStatus = 0;
   }

   receive() external payable {
       if (currentPeriod != 0 || msg.sender != oldStakeBtcContract) {
           revert DirectTransferRejected(currentPeriod, msg.sender);
       }
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
    * @param _mbtcToken MBTC token contract address
    * @param _rewardsSourceAddress Address that holds MBTC rewards
    * @param _swapContract Swap contract for ETH to MBTC conversion
    * @param _oldStakeBtcContract Previous staking contract for migration
    * @param _specialCaller Address authorized for special operations
    * @param _migrateCaller Address authorized for stake migration
    */
   function initConfig(address _mbtcToken, address _rewardsSourceAddress, address _swapContract, address _oldStakeBtcContract, address _specialCaller, address _migrateCaller) external onlyOwner {
       if (_mbtcToken == address(0)) revert ZeroAddress("set mbtc token");
       if (_rewardsSourceAddress == address(0)) revert ZeroAddress("rewards source address");
       if (_swapContract == address(0)) revert ZeroAddress("swap contract");
       if (_oldStakeBtcContract == address(0)) revert ZeroAddress("set old stake btc contract");
       if (_specialCaller == address(0)) revert ZeroAddress("special caller");
       if (_migrateCaller == address(0)) revert ZeroAddress("migrate caller");

       mbtcToken = _mbtcToken;
       rewardsSourceAddress = _rewardsSourceAddress;
       swapContract = _swapContract;
       oldStakeBtcContract = _oldStakeBtcContract;
       specialCallers[_specialCaller] = true;
       migrateCaller = _migrateCaller;
       emit InitConfig(msg.sender, _mbtcToken, _rewardsSourceAddress, _swapContract, _oldStakeBtcContract, _specialCaller, _migrateCaller);
   }

   /**
    * @dev Sets authorization status for special callers
    * Special callers can perform operations like staking on behalf of users
    * @param _caller Address to set authorization for
    * @param _status Authorization status (true = authorized, false = not authorized)
    */
   function setSpecialCallers(address _caller, bool _status) external onlyOwner {
       if (_caller == address(0)) revert ZeroAddress("set special callers");
       specialCallers[_caller] = _status;
       emit SetSpecialCallers(msg.sender, _caller, _status);
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

   /**
    * @dev Updates the address authorized to migrate stakes
    * @param _caller New address authorized for migration operations
    */
   function setMigrateCaller(address _caller) public onlyOwner {
       if (_caller == address(0)) revert ZeroAddress("set migrate caller");
       emit MigrateCallerChanged(msg.sender, migrateCaller, _caller);
       migrateCaller = _caller;
   }

   /**
    * @dev Creates a new staking period
    * Defines the parameters for a new staking period including timing, APR, and capacity
    * @param _startTimestamp Start timestamp of the period
    * @param _ndays Duration of the period in days
    * @param _apr Annual percentage rate (150000 = 15%)
    * @param _stakeCap Maximum staking capacity for the period
    *
    * Requirements:
    * - Duration must be greater than 0
    * - Stake cap must be greater than 0
    * - APR can be 0 initially and updated later
    */
   function createNewPeriod(
       uint32 _startTimestamp,
       uint32 _ndays,
       uint32 _apr,
       uint256 _stakeCap
   ) external onlyOwner {
       if (_ndays == 0) revert ZeroValue("create period ndays");
       if (_stakeCap == 0) revert ZeroValue("create period stake cap");
       uint32 _endTimestamp = _startTimestamp + _ndays * SECONDS_PER_DAY;
       if (totalPeriods >= 1 && _endTimestamp <= block.timestamp) revert InvalidEndTime("create period end timestamp"); // Cannot create periods ending in the past

       uint32 newPeriod = totalPeriods;
       periodConfigs[newPeriod] = PeriodConfig({
           startTimestamp: _startTimestamp,
           ndays: _ndays,
           endTimestamp: _endTimestamp,
           apr: _apr,
           stakeCap: _stakeCap
       });

       totalPeriods++;
       emit PeriodCreated(msg.sender, newPeriod, _startTimestamp, _ndays, _endTimestamp, _apr, _stakeCap);
   }

   /**
    * @dev Sets the current active period
    * Updates which period is currently accepting new stakes
    * @param _period Period number to set as current
    */
   function setCurrentPeriod(uint32 _period) external onlyOwner {
       if (_period >= totalPeriods) revert InvalidPeriod(_period);
       emit CurrentPeriodChanged(msg.sender, currentPeriod, _period);
       currentPeriod = _period;
   }

   /**
    * @dev Updates all configuration parameters for an existing period
    * Allows modification of period timing, APR, and capacity
    * @param _period Period number to update
    * @param _startTimestamp New start timestamp
    * @param _ndays New duration in days
    * @param _apr New annual percentage rate
    * @param _stakeCap New staking capacity
    *
    * Requirements:
    * - Period must exist
    * - All parameters must be valid (non-zero)
    */
   function updatePeriodConfig(
       uint32 _period,
       uint32 _startTimestamp,
       uint32 _ndays,
       uint32 _apr,
       uint256 _stakeCap
   ) external onlyOwner {
       if (_period >= totalPeriods) revert InvalidPeriod(_period);
       if (_ndays == 0) revert ZeroValue("update period ndays");
       if (_apr == 0) revert ZeroValue("update period apr");
       if (_stakeCap == 0) revert ZeroValue("update period stake cap");
       uint32 _endTimestamp = _startTimestamp + _ndays * SECONDS_PER_DAY;

       PeriodConfig storage config = periodConfigs[_period];
       config.startTimestamp = _startTimestamp;
       config.ndays = _ndays;
       config.endTimestamp = _endTimestamp;
       config.apr = _apr;
       config.stakeCap = _stakeCap;

       emit PeriodConfigUpdated(msg.sender, _period, _startTimestamp, _ndays, _endTimestamp, _apr, _stakeCap);
   }

   /**
    * @dev Updates only the APR for a specific period
    * Allows adjustment of reward rates without changing other parameters
    * @param _period Period number to update
    * @param _apr New annual percentage rate
    */
   function updatePeriodApr(
       uint32 _period,
       uint32 _apr
   ) external onlyOwner {
       if (_period >= totalPeriods) revert InvalidPeriod(_period);
       if (_apr == 0) revert ZeroValue("update period _apr");

       PeriodConfig storage config = periodConfigs[_period];
       emit PeriodAprUpdated(msg.sender, _period, config.apr, _apr);
       config.apr = _apr;
   }

   /**
    * @dev Updates only the staking cap for a specific period
    * Allows adjustment of maximum staking capacity
    * @param _period Period number to update
    * @param _stakeCap New staking capacity
    */
   function updatePeriodCap(
       uint32 _period,
       uint256 _stakeCap
   ) external onlyOwner {
       if (_period >= totalPeriods) revert InvalidPeriod(_period);
       if (_stakeCap == 0) revert ZeroValue("update period stake cap");

       PeriodConfig storage config = periodConfigs[_period];
       emit PeriodCapUpdated(msg.sender, _period, config.stakeCap, _stakeCap);
       config.stakeCap = _stakeCap;
   }

   /**
    * @dev Returns the configuration for a specific period
    * @param _period Period number to query
    * @return PeriodConfig memory Structure containing period parameters
    */
   function getPeriodConfig(uint32 _period) external view returns (PeriodConfig memory) {
       if (_period >= totalPeriods) revert InvalidPeriod(_period);
       return periodConfigs[_period];
   }

   /**
    * @dev Returns the total staked amount for a specific period
    * @param _period Period number to query
    * @return uint256 Total amount staked in the period
    */
   function getPeriodStakeAmount(uint32 _period) external view returns (uint256) {
       if (_period >= totalPeriods) revert InvalidPeriod(_period);
       return periodStakeAmount[_period];
   }

   /**
    * @dev Returns the total staked amount for a specific user
    * @param _user User address to query
    * @return uint256 Total amount staked by the user across all periods
    */
   function getUserStakeAmount(address _user) external view returns (uint256) {
       return userStakeAmount[_user];
   }

   /**
    * @dev Calculates rewards for a specific stake item
    * @param _id Stake ID to calculate rewards for
    * @return uint256 Calculated rewards amount
    */
   function calStakeItemRewards(uint32 _id) external view returns (uint256) {
       StakeItem storage item = stakeItems[_id];
       if (item.startTimestamp == 0) revert NotFoundStakingItem(_id);
       return _calRewards(item.period, item.amount);
   }

   /**
    * @dev Calculates rewards for a given amount staked in a period
    * Uses APR and staking duration to compute rewards
    * @param _period Period number to calculate rewards for
    * @param _amount Amount to calculate rewards for
    * @return uint256 Calculated rewards amount
    */
   function _calRewards(uint32 _period, uint256 _amount) internal view returns (uint256) {
       PeriodConfig storage config = periodConfigs[_period];
       return (_amount * config.apr * config.ndays) / 365 / APR_SCALE_FACTOR;
   }

   /**
    * @dev Generates a unique stake ID
    * Increments the nextStakeId counter for each new stake
    * @return uint32 New unique stake ID
    */
   function getNextStakeId() internal returns (uint32) {
       if (stakeId < 10000) {
           stakeId = 10000;
       }
       return ++stakeId;
   }

   /**
    * @dev Pauses staking operations only
    * Can be called by pause admin or contract owner
    * Allows unstaking while preventing new stakes
    */
   function updateStakePaused(bool _stakePaused) external onlyOwner {
       stakePaused = _stakePaused;
       emit UpdateStakePaused(msg.sender, _stakePaused);
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
   event UpdateStakeCap(address adminSetter, uint256 oldStakeCap, uint256 stakeCap);
   event UpdateEndTimestamp(address adminSetter, uint256 oldEndTimestamp, uint256 endTimestamp);
   event UpdateStakePaused(address adminSetter, bool stakePaused);
   event SetSpecialCallers(address adminSetter, address caller, bool status);
   event PauseAdminChanged(address adminSetter, address oldAddress, address newAddress);
   event PauseEvent(address adminSetter, bool paused);
   event Stake(address msgSender, StakeItem stakeItem, uint256 stakeTimestamp);
   event Unstake(address msgSender, StakeItem stakeItem, uint256 unstakeTimestamp);
   event Withdraw(address msgSender, StakeItem stakeItem, uint256 withdrawTimestamp);
   event MigrateStake(address msgSender, StakeItem stakeItem, uint256 migrateTimestamp);
   event MigrateCallerChanged(address adminSetter, address oldCaller, address newCaller);
   
   // Admin events
   event TokenAdminChanged(address adminSetter, address oldTokenAdmin, address newTokenAdmin);
   event AirdropAdminChanged(address adminSetter, address oldAirdropAdmin, address newAirdropAdmin);
   event RefundAdminChanged(address adminSetter, address oldRefundAdmin, address newRefundAdmin);
   event FeeToChanged(address adminSetter, address oldFeeTo, address newFeeTo);
   event SwapFeeToChanged(address adminSetter, address oldSwapFeeTo, address newSwapFeeTo);
   event FeeRateChanged(address adminSetter, uint256 oldFeeRate, uint256 newFeeRate);
   event SwapFeeRateChanged(address adminSetter, uint256 oldSwapFeeRate, uint256 newSwapFeeRate);

   // Period event definitions
   event PeriodCreated(address adminSetter, uint32 indexed period, uint32 startTimestamp, uint256 ndays, uint32 endTimestamp, uint256 apr, uint256 stakeCap);
   event CurrentPeriodChanged(address adminSetter, uint32 indexed oldPeriod, uint32 indexed newPeriod);
   event PeriodConfigUpdated(address adminSetter, uint32 indexed period, uint32 startTimestamp, uint256 ndays, uint32 endTimestamp, uint256 apr, uint256 stakeCap);
   event PeriodAprUpdated(address adminSetter, uint32 indexed period, uint32 oldApr, uint32 newApr);
   event PeriodCapUpdated(address adminSetter, uint32 indexed period, uint256 oldStakeCap, uint256 newStakeCap);
   event InitConfig(address adminSetter, address mbtcToken, address rewardsSourceAddress, address swapContract, address oldStakeBtcContract, address specialCaller, address migrateCaller);
}
