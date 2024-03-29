// SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./GyroPriceOracle.sol";
import "./GyroRouter.sol";
import "./Ownable.sol";
import "./abdk/ABDKMath64x64.sol";

/**
 * GyroFund contains the public interface of the Gyroscope Reserve
 * Its main functionality include minting and redeeming Gyro dollars
 * using supported tokens, which are currently only Balancer Pool Tokens.
 * To mint and redeem against other type of assets, please see the `GyroLib` contract
 * which contains helpers and uses a basic router to do so.
 */
interface GyroFund is IERC20Upgradeable {
    event Mint(address indexed minter, uint256 indexed amount);
    event Redeem(address indexed redeemer, uint256 indexed amount);

    /**
     * Mints GYD in return for user-input tokens
     * @param _tokensIn = array of pool token addresses, in the same order as stored in the contract
     * @param _amountsIn = user-input pool token amounts, in same order as _tokensIn
     * @param _minGyroMinted = slippage parameter for min GYD to mint or else revert
     * Returns amount of GYD to mint and emits a Mint event
     */
    function mint(
        address[] memory _tokensIn,
        uint256[] memory _amountsIn,
        uint256 _minGyroMinted
    ) external returns (uint256);

    /**
     * Same as `mint` but the minted tokens are received by `_onBehalfOf`
     */
    function mintFor(
        address[] memory _BPTokensIn,
        uint256[] memory _amountsIn,
        uint256 _minGyroMinted,
        address _onBehalfOf
    ) external returns (uint256 amountToMint);

    /**
     * Redeems GYD in return for user-specified token amounts from the reserve
     * @param _BPTokensOut = array of pool token addresses, in the same order as stored in the contract
     * @param _amountsOut = user-specified pool token amounts to redeem for, in same order as _BPTokensOut
     * @param _maxGyroRedeemed = slippage parameter for max GYD to redeem or else revert
     * Returns amount of GYD to redeem and emits Redeem event
     */
    function redeem(
        address[] memory _BPTokensOut,
        uint256[] memory _amountsOut,
        uint256 _maxGyroRedeemed
    ) external returns (uint256);

    /**
     * Takes in the same parameters as mint and returns whether the
     * mint will succeed or not as well as the estimated mint amount
     * @param _BPTokensIn addresses of the input balancer pool tokens
     * @param _amountsIn amounts of the input balancer pool tokens
     * @param _minGyroMinted mininum amount of gyro to mint
     * @return errorCode of 0 is no error happens or a value described in errors.json
     */
    function mintChecksPass(
        address[] memory _BPTokensIn,
        uint256[] memory _amountsIn,
        uint256 _minGyroMinted
    ) external view returns (uint256 errorCode, uint256 estimatedAmount);

    /**
     * Takes in the same parameters as redeem and returns whether the
     * redeem will succeed or not as well as the estimated redeem amount
     * @param _BPTokensOut = array of pool token addresses, in the same order as stored in the contract
     * @param _amountsOut = user-specified pool token amounts to redeem for, in same order as _BPTokensOut
     * @param _maxGyroRedeemed = slippage parameter for max GYD to redeem or else revert
     * @return errorCode of 0 is no error happens or a value described in errors.json
     */
    function redeemChecksPass(
        address[] memory _BPTokensOut,
        uint256[] memory _amountsOut,
        uint256 _maxGyroRedeemed
    ) external view returns (uint256 errorCode, uint256 estimatedAmount);

    /**
     * Gets the current values in the reserve pools
     * @return errorCode of 0 is no error happens or a value described in errors.json
     * @return BPTokenAddresses = array of pool token addresses, in the right order
     * @return BPReserveDollarValues = dollar-value held by the reserve in each pool, in same order
     */
    function getReserveValues()
        external
        view
        returns (
            uint256 errorCode,
            address[] memory BPTokenAddresses,
            uint256[] memory BPReserveDollarValues
        );
}

/**
 * GyroFundV1 contains the logic for the Gyroscope Reserve
 * The storage of this contract should be empty, as the Gyroscope storage will be
 * held in the proxy contract.
 * GyroFundV1 contains the mint and redeem functions for GYD and interacts with the
 * GyroPriceOracle for the P-AMM functionality.
 */
contract GyroFundV1 is GyroFund, Ownable, ERC20Upgradeable {
    using ExtendedMath for int128;
    using ABDKMath64x64 for uint256;
    using ABDKMath64x64 for int128;
    using SafeMath for uint256;
    using ExtendedMath for uint256;

    GyroPriceOracle public gyroPriceOracle;
    GyroRouter public gyroRouter;
    PriceOracle public priceOracle;

    struct TokenProperties {
        address oracleAddress;
        string tokenSymbol;
        uint16 tokenIndex;
    }

    struct PoolProperties {
        address poolAddress;
        uint256 initialPoolWeight;
        uint256 initialPoolPrice;
    }

    struct PoolStatus {
        bool _allPoolsHealthy;
        bool _allPoolsWithinEpsilon;
        bool[] _inputPoolHealth;
        bool[] _poolsWithinEpsilon;
    }

    struct Weights {
        uint256[] _idealWeights;
        uint256[] _currentWeights;
        uint256[] _hypotheticalWeights;
        uint256 _nav;
        uint256 _dollarValue;
        uint256 _totalPortfolioValue;
        uint256[] _zeroArray;
        uint256 gyroAmount;
    }

    struct FlowLogger {
        uint256 inflowHistory;
        uint256 outflowHistory;
        uint256 currentBlock;
        uint256 lastSeenBlock;
    }

    PoolProperties[] public poolProperties;

    mapping(address => TokenProperties) _tokenAddressToProperties;
    mapping(address => bool) _checkPoolIsValid;

    mapping(address => bool) _checkIsStablecoin;

    address[] underlyingTokenAddresses;

    uint256 public portfolioWeightEpsilon;
    uint256 lastSeenBlock;
    uint256 inflowHistory;
    uint256 outflowHistory;
    uint256 memoryParam;

    uint256 constant WOULD_UNBALANCE_GYROSCOPE = 1;
    uint256 constant TOO_MUCH_SLIPPAGE = 2;

    function initialize(
        uint256 _portfolioWeightEpsilon,
        address _priceOracleAddress,
        address _routerAddress,
        uint256 _memoryParam
    ) public initializer {
        __ERC20_init("Gyro Dollar", "GYD");
        gyroPriceOracle = GyroPriceOracle(_priceOracleAddress);
        gyroRouter = GyroRouter(_routerAddress);

        lastSeenBlock = block.number;
        memoryParam = _memoryParam;

        portfolioWeightEpsilon = _portfolioWeightEpsilon;
    }

    function addToken(
        address tokenAddress,
        address oracleAddress,
        bool isStable
    ) external onlyOwner {
        for (uint256 i = 0; i < underlyingTokenAddresses.length; i++) {
            require(underlyingTokenAddresses[i] != tokenAddress, "this token already exists");
        }

        _checkIsStablecoin[tokenAddress] = isStable;
        string memory tokenSymbol = ERC20(tokenAddress).symbol();
        _tokenAddressToProperties[tokenAddress] = TokenProperties({
            oracleAddress: oracleAddress,
            tokenSymbol: tokenSymbol,
            tokenIndex: uint16(underlyingTokenAddresses.length)
        });
        underlyingTokenAddresses.push(tokenAddress);
    }

    function addPool(address _bpoolAddress, uint256 _initialPoolWeight) external onlyOwner {
        // check we do not already have this pool
        for (uint256 i = 0; i < poolProperties.length; i++) {
            require(poolProperties[i].poolAddress != _bpoolAddress, "this pool already exists");
        }

        BPool _bPool = BPool(_bpoolAddress);
        _checkPoolIsValid[_bpoolAddress] = true;

        // get the addresses of the underlying tokens
        address[] memory _bPoolUnderlyingTokens = _bPool.getFinalTokens();

        // fill the underlying token prices array
        uint256[] memory _bPoolUnderlyingTokenPrices = new uint256[](_bPoolUnderlyingTokens.length);
        for (uint256 i = 0; i < _bPoolUnderlyingTokens.length; i++) {
            address tokenAddress = _bPoolUnderlyingTokens[i];
            string memory tokenSymbol = ERC20(tokenAddress).symbol();
            _bPoolUnderlyingTokenPrices[i] = getPrice(tokenAddress, tokenSymbol);
        }

        // Calculate BPT price for the pool
        uint256 initialPoolPrice =
            gyroPriceOracle.getBPTPrice(_bpoolAddress, _bPoolUnderlyingTokenPrices);

        poolProperties.push(
            PoolProperties({
                poolAddress: _bpoolAddress,
                initialPoolWeight: _initialPoolWeight,
                initialPoolPrice: initialPoolPrice
            })
        );
    }

    function calculateImpliedPoolWeights(uint256[] memory _BPTPrices)
        internal
        view
        returns (uint256[] memory)
    {
        // order of _BPTPrices must be same as order of poolProperties
        uint256[] memory _newWeights = new uint256[](_BPTPrices.length);
        uint256[] memory _weightedReturns = new uint256[](_BPTPrices.length);

        uint256[] memory _initPoolPrices = new uint256[](_BPTPrices.length);
        uint256[] memory _initWeights = new uint256[](_BPTPrices.length);

        for (uint256 i = 0; i < poolProperties.length; i++) {
            _initPoolPrices[i] = poolProperties[i].initialPoolPrice;
            _initWeights[i] = poolProperties[i].initialPoolWeight;
        }

        for (uint256 i = 0; i < _BPTPrices.length; i++) {
            _weightedReturns[i] = _BPTPrices[i].scaledDiv(_initPoolPrices[i]).scaledMul(
                _initWeights[i]
            );
        }

        uint256 _returnsSum = 0;
        for (uint256 i = 0; i < _BPTPrices.length; i++) {
            _returnsSum = _returnsSum.add(_weightedReturns[i]);
        }

        for (uint256 i = 0; i < _BPTPrices.length; i++) {
            _newWeights[i] = _weightedReturns[i].scaledDiv(_returnsSum);
        }

        return _newWeights;
    }

    function nav(uint256 _totalPortfolioValue) internal view returns (uint256 _nav) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply > 0) {
            _nav = _totalPortfolioValue.scaledDiv(totalSupply());
        } else {
            _nav = 1e18;
        }

        return _nav;
    }

    function calculatePortfolioWeights(uint256[] memory _BPTAmounts, uint256[] memory _BPTPrices)
        internal
        pure
        returns (uint256[] memory, uint256)
    {
        uint256[] memory _weights = new uint256[](_BPTPrices.length);
        uint256 _totalPortfolioValue = 0;

        for (uint256 i = 0; i < _BPTAmounts.length; i++) {
            _totalPortfolioValue = _totalPortfolioValue.add(
                _BPTAmounts[i].scaledMul(_BPTPrices[i])
            );
        }

        if (_totalPortfolioValue == 0) {
            return (_weights, _totalPortfolioValue);
        }

        for (uint256 i = 0; i < _BPTAmounts.length; i++) {
            _weights[i] = _BPTAmounts[i].scaledMul(_BPTPrices[i]).scaledDiv(_totalPortfolioValue);
        }

        return (_weights, _totalPortfolioValue);
    }

    function checkStablecoinHealth(uint256 stablecoinPrice, address stablecoinAddress)
        internal
        view
        returns (bool)
    {
        // TODO: revisit
        //Price
        bool _stablecoinHealthy = true;

        uint256 decimals = ERC20(stablecoinAddress).decimals();

        uint256 maxDeviation = 5 * 10**(decimals - 2);
        uint256 idealPrice = 10**decimals;

        if (stablecoinPrice >= idealPrice + maxDeviation) {
            _stablecoinHealthy = false;
        } else if (stablecoinPrice <= idealPrice - maxDeviation) {
            _stablecoinHealthy = false;
        }

        //Volume (to do)

        return _stablecoinHealthy;
    }

    function absValueSub(uint256 _number1, uint256 _number2) internal pure returns (uint256) {
        if (_number1 >= _number2) {
            return _number1.sub(_number2);
        } else {
            return _number2.sub(_number1);
        }
    }

    function getPrice(address _token, string memory _tokenSymbol) internal view returns (uint256) {
        return PriceOracle(_tokenAddressToProperties[_token].oracleAddress).getPrice(_tokenSymbol);
    }

    function bytes32ToString(bytes32 x) private pure returns (string memory) {
        bytes memory bytesString = new bytes(32);
        uint256 charCount = 0;
        for (uint256 j = 0; j < 32; j++) {
            bytes1 char = bytes1(bytes32(uint256(x) * 2**(8 * j)));
            if (char != 0) {
                bytesString[charCount] = char;
                charCount++;
            }
        }
        bytes memory bytesStringTrimmed = new bytes(charCount);
        for (uint256 j = 0; j < charCount; j++) {
            bytesStringTrimmed[j] = bytesString[j];
        }
        return string(bytesStringTrimmed);
    }

    function getAllTokenPrices() public view returns (uint256[] memory) {
        uint256[] memory _allUnderlyingPrices = new uint256[](underlyingTokenAddresses.length);
        for (uint256 i = 0; i < underlyingTokenAddresses.length; i++) {
            address _tokenAddress = underlyingTokenAddresses[i];
            string memory _tokenSymbol =
                _tokenAddressToProperties[underlyingTokenAddresses[i]].tokenSymbol;
            uint256 _tokenPrice = getPrice(_tokenAddress, _tokenSymbol);
            _allUnderlyingPrices[i] = _tokenPrice;
        }
        return _allUnderlyingPrices;
    }

    function mintTest(address[] memory _BPTokensIn, uint256[] memory _amountsIn)
        public
        onlyOwner
        returns (uint256)
    {
        for (uint256 i = 0; i < _BPTokensIn.length; i++) {
            bool success =
                ERC20(_BPTokensIn[i]).transferFrom(msg.sender, address(this), _amountsIn[i]);
            require(success, "failed to transfer tokens, check allowance");
        }
        uint256[] memory _allUnderlyingPrices = getAllTokenPrices();
        uint256[] memory _currentBPTPrices = calculateAllPoolPrices(_allUnderlyingPrices);
        uint256 _dollarValue = 0;

        for (uint256 i = 0; i < _BPTokensIn.length; i++) {
            _dollarValue = _dollarValue.add(_amountsIn[i].scaledMul(_currentBPTPrices[i]));
        }

        uint256 _gyroToMint = gyroPriceOracle.getAmountToMint(_dollarValue, 0, 1e18);

        _mint(msg.sender, _gyroToMint);
        return _gyroToMint;
    }

    function calculateAllPoolPrices(uint256[] memory _allUnderlyingPrices)
        public
        view
        returns (uint256[] memory)
    {
        uint256[] memory _currentBPTPrices = new uint256[](poolProperties.length);

        // Calculate BPT prices for all pools
        for (uint256 i = 0; i < poolProperties.length; i++) {
            BPool _bPool = BPool(poolProperties[i].poolAddress);

            address[] memory _bPoolUnderlyingTokens = _bPool.getFinalTokens();

            //For each pool fill the underlying token prices array
            uint256[] memory _bPoolUnderlyingTokenPrices =
                new uint256[](underlyingTokenAddresses.length);
            for (uint256 j = 0; j < _bPoolUnderlyingTokens.length; j++) {
                _bPoolUnderlyingTokenPrices[j] = _allUnderlyingPrices[
                    _tokenAddressToProperties[_bPoolUnderlyingTokens[j]].tokenIndex
                ];
            }

            // Calculate BPT price for the pool
            _currentBPTPrices[i] = gyroPriceOracle.getBPTPrice(
                poolProperties[i].poolAddress,
                _bPoolUnderlyingTokenPrices
            );
        }

        return _currentBPTPrices;
    }

    function poolHealthHelper(uint256[] memory _allUnderlyingPrices, uint256 _poolIndex)
        internal
        view
        returns (bool)
    {
        bool _poolHealthy = true;

        BPool _bPool = BPool(poolProperties[_poolIndex].poolAddress);
        address[] memory _bPoolUnderlyingTokens = _bPool.getFinalTokens();

        //Go through the underlying tokens within the pool
        for (uint256 j = 0; j < _bPoolUnderlyingTokens.length; j++) {
            if (_checkIsStablecoin[_bPoolUnderlyingTokens[j]]) {
                uint256 _stablecoinPrice =
                    _allUnderlyingPrices[
                        _tokenAddressToProperties[_bPoolUnderlyingTokens[j]].tokenIndex
                    ];

                if (!checkStablecoinHealth(_stablecoinPrice, _bPoolUnderlyingTokens[j])) {
                    _poolHealthy = false;
                    break;
                }
            }
        }

        return _poolHealthy;
    }

    function checkPoolsWithinEpsilon(
        address[] memory _BPTokensIn,
        uint256[] memory _hypotheticalWeights,
        uint256[] memory _idealWeights
    ) internal view returns (bool, bool[] memory) {
        bool _allPoolsWithinEpsilon = true;
        bool[] memory _poolsWithinEpsilon = new bool[](_BPTokensIn.length);

        for (uint256 i = 0; i < _BPTokensIn.length; i++) {
            // Check 1: check whether hypothetical weight will be within epsilon
            _poolsWithinEpsilon[i] = true;
            if (_hypotheticalWeights[i] >= _idealWeights[i].add(portfolioWeightEpsilon)) {
                _allPoolsWithinEpsilon = false;
                _poolsWithinEpsilon[i] = false;
            } else if (_hypotheticalWeights[i].add(portfolioWeightEpsilon) <= _idealWeights[i]) {
                _allPoolsWithinEpsilon = false;
                _poolsWithinEpsilon[i] = false;
            }
        }

        return (_allPoolsWithinEpsilon, _poolsWithinEpsilon);
    }

    function checkAllPoolsHealthy(
        address[] memory _BPTokensIn,
        uint256[] memory _hypotheticalWeights,
        uint256[] memory _idealWeights,
        uint256[] memory _allUnderlyingPrices
    )
        internal
        view
        returns (
            bool,
            bool,
            bool[] memory,
            bool[] memory
        )
    {
        // Check safety of input tokens
        bool _allPoolsWithinEpsilon;
        bool[] memory _poolsWithinEpsilon = new bool[](_BPTokensIn.length);
        bool[] memory _inputPoolHealth = new bool[](_BPTokensIn.length);
        bool _allPoolsHealthy = true;

        (_allPoolsWithinEpsilon, _poolsWithinEpsilon) = checkPoolsWithinEpsilon(
            _BPTokensIn,
            _hypotheticalWeights,
            _idealWeights
        );

        for (uint256 i = 0; i < _BPTokensIn.length; i++) {
            _inputPoolHealth[i] = poolHealthHelper(_allUnderlyingPrices, i);
            _allPoolsHealthy = _allPoolsHealthy && _inputPoolHealth[i];
        }

        return (_allPoolsHealthy, _allPoolsWithinEpsilon, _inputPoolHealth, _poolsWithinEpsilon);
    }

    function safeToMintOutsideEpsilon(
        address[] memory _BPTokensIn,
        bool[] memory _inputPoolHealth,
        uint256[] memory _inputBPTWeights,
        uint256[] memory _idealWeights,
        uint256[] memory _hypotheticalWeights,
        uint256[] memory _currentWeights,
        bool[] memory _poolsWithinEpsilon
    ) internal pure returns (bool _anyCheckFail) {
        //Check that amount above epsilon is decreasing
        //Check that unhealthy pools have input weight below ideal weight
        //If both true, then mint
        //note: should always be able to mint at the ideal weights!
        _anyCheckFail = false;
        for (uint256 i; i < _BPTokensIn.length; i++) {
            if (!_inputPoolHealth[i]) {
                if (_inputBPTWeights[i] > _idealWeights[i]) {
                    _anyCheckFail = true;
                    break;
                }
            }

            if (!_poolsWithinEpsilon[i]) {
                // check if _hypotheticalWeights[i] is closer to _idealWeights[i] than _currentWeights[i]
                uint256 _distanceHypotheticalToIdeal =
                    absValueSub(_hypotheticalWeights[i], _idealWeights[i]);
                uint256 _distanceCurrentToIdeal = absValueSub(_currentWeights[i], _idealWeights[i]);

                if (_distanceHypotheticalToIdeal >= _distanceCurrentToIdeal) {
                    _anyCheckFail = true;
                    break;
                }
            }
        }

        if (!_anyCheckFail) {
            return true;
        }
    }

    function checkBPTokenOrder(address[] memory _BPTokensIn) internal view returns (bool _correct) {
        require(
            _BPTokensIn.length == poolProperties.length,
            "bptokens do not have the correct number of addreses"
        );
        _correct = true;

        for (uint256 i = 0; i < poolProperties.length; i++) {
            if (poolProperties[i].poolAddress != _BPTokensIn[i]) {
                _correct = false;
                break;
            }
        }

        return _correct;
    }

    function checkUnhealthyMovesToIdeal(
        address[] memory _BPTokensIn,
        bool[] memory _inputPoolHealth,
        uint256[] memory _inputBPTWeights,
        uint256[] memory _idealWeights
    ) internal pure returns (bool _launch) {
        bool _unhealthyMovesTowardIdeal = true;
        for (uint256 i; i < _BPTokensIn.length; i++) {
            if (!_inputPoolHealth[i]) {
                if (_inputBPTWeights[i] > _idealWeights[i]) {
                    _unhealthyMovesTowardIdeal = false;
                    break;
                }
            }
        }

        if (_unhealthyMovesTowardIdeal) {
            _launch = true;
        }
    }

    function safeToMint(
        address[] memory _BPTokensIn,
        uint256[] memory _hypotheticalWeights,
        uint256[] memory _idealWeights,
        uint256[] memory _allUnderlyingPrices,
        uint256[] memory _amountsIn,
        uint256[] memory _currentBPTPrices,
        uint256[] memory _currentWeights
    ) internal view returns (bool _launch) {
        _launch = false;

        PoolStatus memory poolStatus;

        (
            poolStatus._allPoolsHealthy,
            poolStatus._allPoolsWithinEpsilon,
            poolStatus._inputPoolHealth,
            poolStatus._poolsWithinEpsilon
        ) = checkAllPoolsHealthy(
            _BPTokensIn,
            _hypotheticalWeights,
            _idealWeights,
            _allUnderlyingPrices
        );

        // if check 1 succeeds and all pools healthy, then proceed with minting
        if (poolStatus._allPoolsHealthy) {
            if (poolStatus._allPoolsWithinEpsilon) {
                _launch = true;
            }
        } else {
            // calculate proportional values of assets user wants to pay with
            (uint256[] memory _inputBPTWeights, uint256 _totalPortfolioValue) =
                calculatePortfolioWeights(_amountsIn, _currentBPTPrices);
            if (_totalPortfolioValue == 0) {
                _inputBPTWeights = _idealWeights;
            }

            //Check that unhealthy pools have input weight below ideal weight. If true, mint
            if (poolStatus._allPoolsWithinEpsilon) {
                _launch = checkUnhealthyMovesToIdeal(
                    _BPTokensIn,
                    poolStatus._inputPoolHealth,
                    _inputBPTWeights,
                    _idealWeights
                );
            }
            //Outside of the epsilon boundary
            else {
                _launch = safeToMintOutsideEpsilon(
                    _BPTokensIn,
                    poolStatus._inputPoolHealth,
                    _inputBPTWeights,
                    _idealWeights,
                    _hypotheticalWeights,
                    _currentWeights,
                    poolStatus._poolsWithinEpsilon
                );
            }
        }

        return _launch;
    }

    function safeToRedeem(
        address[] memory _BPTokensOut,
        uint256[] memory _hypotheticalWeights,
        uint256[] memory _idealWeights,
        uint256[] memory _currentWeights
    ) internal view returns (bool) {
        bool _launch = false;
        bool _allPoolsWithinEpsilon;
        bool[] memory _poolsWithinEpsilon = new bool[](_BPTokensOut.length);

        (_allPoolsWithinEpsilon, _poolsWithinEpsilon) = checkPoolsWithinEpsilon(
            _BPTokensOut,
            _hypotheticalWeights,
            _idealWeights
        );
        if (_allPoolsWithinEpsilon) {
            _launch = true;
            return _launch;
        }

        // check if weights that are beyond epsilon boundary are closer to ideal than current weights
        bool _checkFail = false;
        for (uint256 i; i < _BPTokensOut.length; i++) {
            if (!_poolsWithinEpsilon[i]) {
                // check if _hypotheticalWeights[i] is closer to _idealWeights[i] than _currentWeights[i]
                uint256 _distanceHypotheticalToIdeal =
                    absValueSub(_hypotheticalWeights[i], _idealWeights[i]);
                uint256 _distanceCurrentToIdeal = absValueSub(_currentWeights[i], _idealWeights[i]);

                if (_distanceHypotheticalToIdeal >= _distanceCurrentToIdeal) {
                    _checkFail = true;
                    break;
                }
            }
        }

        if (!_checkFail) {
            _launch = true;
        }

        return _launch;
    }

    function calculateAllWeights(
        uint256[] memory _currentBPTPrices,
        address[] memory _BPTokens,
        uint256[] memory _amountsIn,
        uint256[] memory _amountsOut
    )
        internal
        view
        returns (
            uint256[] memory _idealWeights,
            uint256[] memory _currentWeights,
            uint256[] memory _hypotheticalWeights,
            uint256 _nav,
            uint256 _totalPortfolioValue
        )
    {
        //Calculate the up to date ideal portfolio weights
        _idealWeights = calculateImpliedPoolWeights(_currentBPTPrices);

        //Calculate the hypothetical weights if the new BPT tokens were added
        uint256[] memory _BPTNewAmounts = new uint256[](_BPTokens.length);
        uint256[] memory _BPTCurrentAmounts = new uint256[](_BPTokens.length);

        for (uint256 i = 0; i < _BPTokens.length; i++) {
            BPool _bPool = BPool(_BPTokens[i]);
            _BPTCurrentAmounts[i] = _bPool.balanceOf(address(this));
            _BPTNewAmounts[i] = _BPTCurrentAmounts[i].add(_amountsIn[i]).sub(_amountsOut[i]);
        }

        (_currentWeights, _totalPortfolioValue) = calculatePortfolioWeights(
            _BPTCurrentAmounts,
            _currentBPTPrices
        );
        if (_totalPortfolioValue == 0) {
            _currentWeights = _idealWeights;
        }

        _nav = nav(_totalPortfolioValue);

        (_hypotheticalWeights, ) = calculatePortfolioWeights(_BPTNewAmounts, _currentBPTPrices);

        return (_idealWeights, _currentWeights, _hypotheticalWeights, _nav, _totalPortfolioValue);
    }

    //_amountsIn in should have a zero index if nothing has been submitted for a particular token
    // _BPTokensIn and _amountsIn should have same indexes as poolProperties
    function mint(
        address[] memory _BPTokensIn,
        uint256[] memory _amountsIn,
        uint256 _minGyroMinted
    ) public override returns (uint256 amountToMint) {
        return mintFor(_BPTokensIn, _amountsIn, _minGyroMinted, msg.sender);
    }

    function mintFor(
        address[] memory _BPTokensIn,
        uint256[] memory _amountsIn,
        uint256 _minGyroMinted,
        address _onBehalfOf
    ) public override returns (uint256 amountToMint) {
        (uint256 errorCode, Weights memory weights, FlowLogger memory flowLogger) =
            mintChecksPassInternal(_BPTokensIn, _amountsIn, _minGyroMinted);
        require(errorCode == 0, errorCodeToString(errorCode));

        for (uint256 i = 0; i < _BPTokensIn.length; i++) {
            bool success =
                ERC20(_BPTokensIn[i]).transferFrom(msg.sender, address(this), _amountsIn[i]);
            require(success, "failed to transfer tokens, check allowance");
        }

        amountToMint = weights.gyroAmount;

        _mint(_onBehalfOf, amountToMint);

        finalizeFlowLogger(
            flowLogger.inflowHistory,
            flowLogger.outflowHistory,
            weights.gyroAmount,
            0,
            flowLogger.currentBlock,
            flowLogger.lastSeenBlock
        );

        emit Mint(_onBehalfOf, amountToMint);

        return amountToMint;
    }

    function mintChecksPass(
        address[] memory _BPTokensIn,
        uint256[] memory _amountsIn,
        uint256 _minGyroMinted
    ) public view override returns (uint256 errorCode, uint256 estimatedMint) {
        (uint256 _errorCode, Weights memory weights, ) =
            mintChecksPassInternal(_BPTokensIn, _amountsIn, _minGyroMinted);

        return (_errorCode, weights.gyroAmount);
    }

    function getReserveValues()
        public
        view
        override
        returns (
            uint256,
            address[] memory,
            uint256[] memory
        )
    {
        address[] memory _BPTokens = new address[](poolProperties.length);
        uint256[] memory _zeroAmounts = new uint256[](poolProperties.length);
        for (uint256 i = 0; i < poolProperties.length; i++) {
            _BPTokens[i] = poolProperties[i].poolAddress;
        }

        (uint256 _errorCode, Weights memory weights, ) =
            mintChecksPassInternal(_BPTokens, _zeroAmounts, uint256(0));

        uint256[] memory _BPReserveDollarValues = new uint256[](_BPTokens.length);

        for (uint256 i = 0; i < _BPTokens.length; i++) {
            _BPReserveDollarValues[i] = weights._currentWeights[i].scaledMul(
                weights._totalPortfolioValue
            );
        }

        return (_errorCode, _BPTokens, _BPReserveDollarValues);
    }

    function mintChecksPassInternal(
        address[] memory _BPTokensIn,
        uint256[] memory _amountsIn,
        uint256 _minGyroMinted
    )
        internal
        view
        returns (
            uint256 errorCode,
            Weights memory weights,
            FlowLogger memory flowLogger
        )
    {
        require(
            _BPTokensIn.length == _amountsIn.length,
            "tokensIn and valuesIn should have the same number of elements"
        );

        //Filter 1: Require that the tokens are supported and in correct order
        bool _orderCorrect = checkBPTokenOrder(_BPTokensIn);
        require(_orderCorrect, "Input tokens in wrong order or contains invalid tokens");

        uint256[] memory _allUnderlyingPrices = getAllTokenPrices();

        uint256[] memory _currentBPTPrices = calculateAllPoolPrices(_allUnderlyingPrices);

        weights._zeroArray = new uint256[](_BPTokensIn.length);
        for (uint256 i = 0; i < _BPTokensIn.length; i++) {
            weights._zeroArray[i] = 0;
        }

        (
            weights._idealWeights,
            weights._currentWeights,
            weights._hypotheticalWeights,
            weights._nav,
            weights._totalPortfolioValue
        ) = calculateAllWeights(_currentBPTPrices, _BPTokensIn, _amountsIn, weights._zeroArray);

        bool _safeToMint =
            safeToMint(
                _BPTokensIn,
                weights._hypotheticalWeights,
                weights._idealWeights,
                _allUnderlyingPrices,
                _amountsIn,
                _currentBPTPrices,
                weights._currentWeights
            );

        if (!_safeToMint) {
            errorCode |= WOULD_UNBALANCE_GYROSCOPE;
        }

        weights._dollarValue = 0;

        for (uint256 i = 0; i < _BPTokensIn.length; i++) {
            weights._dollarValue = weights._dollarValue.add(
                _amountsIn[i].scaledMul(_currentBPTPrices[i])
            );
        }

        flowLogger = initializeFlowLogger();

        weights.gyroAmount = gyroPriceOracle.getAmountToMint(
            weights._dollarValue,
            flowLogger.inflowHistory,
            weights._nav
        );

        if (weights.gyroAmount < _minGyroMinted) {
            errorCode |= TOO_MUCH_SLIPPAGE;
        }

        return (errorCode, weights, flowLogger);
    }

    function redeemChecksPass(
        address[] memory _BPTokensOut,
        uint256[] memory _amountsOut,
        uint256 _maxGyroRedeemed
    ) public view override returns (uint256 errorCode, uint256 estimatedAmount) {
        (uint256 _errorCode, Weights memory weights, ) =
            redeemChecksPassInternal(_BPTokensOut, _amountsOut, _maxGyroRedeemed);
        return (_errorCode, weights.gyroAmount);
    }

    function redeemChecksPassInternal(
        address[] memory _BPTokensOut,
        uint256[] memory _amountsOut,
        uint256 _maxGyroRedeemed
    )
        internal
        view
        returns (
            uint256 errorCode,
            Weights memory weights,
            FlowLogger memory flowLogger
        )
    {
        require(
            _BPTokensOut.length == _amountsOut.length,
            "tokensIn and valuesIn should have the same number of elements"
        );

        //Filter 1: Require that the tokens are supported and in correct order
        require(
            checkBPTokenOrder(_BPTokensOut),
            "Input tokens in wrong order or contains invalid tokens"
        );

        weights._zeroArray = new uint256[](_BPTokensOut.length);
        for (uint256 i = 0; i < _BPTokensOut.length; i++) {
            weights._zeroArray[i] = 0;
        }

        uint256[] memory _allUnderlyingPrices = getAllTokenPrices();

        uint256[] memory _currentBPTPrices = calculateAllPoolPrices(_allUnderlyingPrices);

        (
            weights._idealWeights,
            weights._currentWeights,
            weights._hypotheticalWeights,
            weights._nav,
            weights._totalPortfolioValue
        ) = calculateAllWeights(_currentBPTPrices, _BPTokensOut, weights._zeroArray, _amountsOut);

        bool _safeToRedeem =
            safeToRedeem(
                _BPTokensOut,
                weights._hypotheticalWeights,
                weights._idealWeights,
                weights._currentWeights
            );

        if (!_safeToRedeem) {
            errorCode |= WOULD_UNBALANCE_GYROSCOPE;
        }

        weights._dollarValue = 0;

        for (uint256 i = 0; i < _BPTokensOut.length; i++) {
            weights._dollarValue = weights._dollarValue.add(
                _amountsOut[i].scaledMul(_currentBPTPrices[i])
            );
        }

        flowLogger = initializeFlowLogger();

        weights.gyroAmount = gyroPriceOracle.getAmountToRedeem(
            weights._dollarValue,
            flowLogger.outflowHistory,
            weights._nav
        );

        if (weights.gyroAmount > _maxGyroRedeemed) {
            errorCode |= TOO_MUCH_SLIPPAGE;
        }

        return (errorCode, weights, flowLogger);
    }

    function redeem(
        address[] memory _BPTokensOut,
        uint256[] memory _amountsOut,
        uint256 _maxGyroRedeemed
    ) public override returns (uint256 _gyroRedeemed) {
        (uint256 errorCode, Weights memory weights, FlowLogger memory flowLogger) =
            redeemChecksPassInternal(_BPTokensOut, _amountsOut, _maxGyroRedeemed);
        require(errorCode == 0, errorCodeToString(errorCode));

        _gyroRedeemed = weights.gyroAmount;

        _burn(msg.sender, _gyroRedeemed);

        gyroRouter.withdraw(_BPTokensOut, _amountsOut);

        for (uint256 i = 0; i < _amountsOut.length; i++) {
            bool success =
                ERC20(_BPTokensOut[i]).transferFrom(address(this), msg.sender, _amountsOut[i]);
            require(success, "failed to transfer tokens");
        }

        emit Redeem(msg.sender, _gyroRedeemed);
        finalizeFlowLogger(
            flowLogger.inflowHistory,
            flowLogger.outflowHistory,
            0,
            _gyroRedeemed,
            flowLogger.currentBlock,
            flowLogger.lastSeenBlock
        );
        return _gyroRedeemed;
    }

    function initializeFlowLogger() internal view returns (FlowLogger memory flowLogger) {
        flowLogger.lastSeenBlock = lastSeenBlock;
        flowLogger.currentBlock = block.number;
        flowLogger.inflowHistory = inflowHistory;
        flowLogger.outflowHistory = outflowHistory;

        uint256 _memoryParam = memoryParam;

        if (flowLogger.lastSeenBlock < flowLogger.currentBlock) {
            flowLogger.inflowHistory = flowLogger.inflowHistory.scaledMul(
                _memoryParam.scaledPow(flowLogger.currentBlock.sub(flowLogger.lastSeenBlock))
            );
            flowLogger.outflowHistory = flowLogger.outflowHistory.scaledMul(
                _memoryParam.scaledPow(flowLogger.currentBlock.sub(flowLogger.lastSeenBlock))
            );
        }

        return flowLogger;
    }

    function finalizeFlowLogger(
        uint256 _inflowHistory,
        uint256 _outflowHistory,
        uint256 _gyroMinted,
        uint256 _gyroRedeemed,
        uint256 _currentBlock,
        uint256 _lastSeenBlock
    ) internal {
        if (_gyroMinted > 0) {
            inflowHistory = _inflowHistory.add(_gyroMinted);
        }
        if (_gyroRedeemed > 0) {
            outflowHistory = _outflowHistory.add(_gyroRedeemed);
        }
        if (_lastSeenBlock < _currentBlock) {
            lastSeenBlock = _currentBlock;
        }
    }

    function poolAddresses() public view returns (address[] memory) {
        address[] memory _addresses = new address[](poolProperties.length);
        for (uint256 i = 0; i < poolProperties.length; i++) {
            _addresses[i] = poolProperties[i].poolAddress;
        }
        return _addresses;
    }

    function getUnderlyingTokenAddresses() external view returns (address[] memory) {
        address[] memory _addresses = new address[](underlyingTokenAddresses.length);
        for (uint256 i = 0; i < underlyingTokenAddresses.length; i++) {
            _addresses[i] = underlyingTokenAddresses[i];
        }
        return _addresses;
    }

    function errorCodeToString(uint256 errorCode) public pure returns (string memory) {
        if ((errorCode & WOULD_UNBALANCE_GYROSCOPE) != 0) {
            return "ERR_WOULD_UNBALANCE_GYROSCOPE";
        } else if ((errorCode & TOO_MUCH_SLIPPAGE) != 0) {
            return "ERR_TOO_MUCH_SLIPPAGE";
        } else {
            return "ERR_UNKNOWN";
        }
    }
}
