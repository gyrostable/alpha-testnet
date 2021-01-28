// SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./GyroPriceOracle.sol";
import "./GyroRouter.sol";
import "./Ownable.sol";
import "./abdk/ABDKMath64x64.sol";

interface GyroFund is IERC20 {
    event Mint(address minter, uint256 amount);
    event Redeem(address redeemer, uint256 amount);

    function mint(
        address[] memory _tokensIn,
        uint256[] memory _amountsIn,
        uint256 _minGyroMinted
    ) external returns (uint256);

    function redeem(
        uint256 _gyroAmountBurned,
        address[] memory _tokensOut,
        uint256[] memory _minValuesOut
    ) external returns (uint256[] memory);

    function getTotalNumberOfPools() external returns (uint256);

    function checkAssetSafety(address _tokenIn) external returns (bool);

    function checkPortfolioWeights(address _tokenIn, uint256 _amountIn) external returns (bool);
}

contract GyroFundV1 is Ownable, ERC20 {
    using ExtendedMath for int128;
    using ABDKMath64x64 for uint256;
    using ABDKMath64x64 for int128;
    using SafeMath for uint256;

    GyroPriceOracle gyroPriceOracle;
    GyroRouter gyroRouter;
    PriceOracle priceOracle;

    struct tokenProperties {
        address oracleAddress;
        bytes32 tokenSymbol;
        uint16 tokenIndex;
    }

    struct PoolProperties {
        address poolAddress;
        uint256 initialPoolWeight;
        uint256 initialPoolPrice;
    }

    PoolProperties[] poolProperties;

    mapping(address => tokenProperties) _tokenAddressToProperties;
    mapping(address => bool) _checkIsStablecoin;

    address[] underlyingTokenAddresses;

    uint256 portfolioWeightEpsilon;


    constructor(
        uint256 _portfolioWeightEpsilon,
        uint256[] memory _initialPoolWeights,
        address[] memory _gyroPoolAddresses,
        address _priceOracleAddress,
        address _routerAddress,
        address[] memory _underlyingTokenAddresses,
        address[] memory _underlyingTokenOracleAddresses,
        bytes32[] memory _underlyingTokenSymbols,
        address[] memory _stablecoinAddresses
    ) ERC20("Gyro Stable Coin", "GYRO") {
        gyroPriceOracle = GyroPriceOracle(_priceOracleAddress);
        gyroRouter = GyroRouter(_routerAddress);

        underlyingTokenAddresses = _underlyingTokenAddresses;

        portfolioWeightEpsilon = _portfolioWeightEpsilon;

        for (uint256 i = 0; i < _gyroPoolAddresses.length; i++) {
            poolProperties[i].poolAddress = _gyroPoolAddresses[i];
            poolProperties[i].initialPoolWeight = _initialPoolWeights[i];
        }

        for (uint256 i = 0; i < _underlyingTokenAddresses.length; i++) {
            _tokenAddressToProperties[_underlyingTokenAddresses[i]]
                .oracleAddress = _underlyingTokenOracleAddresses[i];
            _tokenAddressToProperties[_underlyingTokenAddresses[i]]
                .tokenSymbol = _underlyingTokenSymbols[i];
            _tokenAddressToProperties[_underlyingTokenAddresses[i]].tokenIndex = uint16(i);
        }

        // Calculate BPT prices for all pools
        uint256[] memory _underlyingPrices = getAllTokenPrices();
        for (uint256 i = 0; i < poolProperties.length; i++) {
            BPool _bPool = BPool(poolProperties[i].poolAddress);

            //For each pool get the addresses of the underlying tokens
            address[] memory _bPoolUnderlyingTokens = _bPool.getFinalTokens();

            //For each pool fill the underlying token prices array
            uint256[] memory _bPoolUnderlyingTokenPrices;
            for (uint256 j = 0; j < _bPoolUnderlyingTokens.length; j++) {
                _bPoolUnderlyingTokenPrices[j] = _underlyingPrices[
                    _tokenAddressToProperties[_bPoolUnderlyingTokens[j]].tokenIndex
                ];
            }

            // Calculate BPT price for the pool
            address poolAddress = poolProperties[i].poolAddress;
            poolProperties[i].initialPoolPrice = gyroPriceOracle.getBPTPrice(
                poolAddress,
                _bPoolUnderlyingTokenPrices
            );
        }

        for (uint256 i = 1; i < _stablecoinAddresses.length; i++) {
            _checkIsStablecoin[_stablecoinAddresses[i]] = true;
        }
    }

    function calculateImpliedPoolWeights(uint256[] memory _BPTPrices)
        public
        view
        returns (uint256[] memory)
    {
        // order of _BPTPrices must be same as order of poolProperties
        uint256[] memory _newWeights;
        uint256[] memory _weightedReturns;

        uint256[] memory _initPoolPrices;
        uint256[] memory _initWeights;
        uint256[] memory _returns;
        for (uint256 i = 0; i < poolProperties.length; i++) {
            _initPoolPrices[i] = poolProperties[i].initialPoolPrice;
            _initWeights[i] = poolProperties[i].initialPoolWeight;
        }

        for (uint256 i = 0; i < _BPTPrices.length; i++) {
            _weightedReturns[i] = _BPTPrices[i].div(_initPoolPrices[i]).mul(_initWeights[i]);
        }

        uint256 _returnsSum = 0;
        for (uint256 i = 0; i < _BPTPrices.length; i++) {
            _returnsSum = _returnsSum.add(_returns[i]);
        }

        for (uint256 i = 0; i < _BPTPrices.length; i++) {
            _newWeights[i] = _returns[i].div(_returnsSum);
        }

        return _newWeights;
    }

    function calculatePortfolioWeights(uint256[] memory _BPTAmounts, uint256[] memory _BPTPrices)
        public
        pure
        returns (uint256[] memory)
    {
        uint256[] memory _weights;
        uint256 _totalPortfolioValue = 0;

        for (uint256 i = 0; i < _BPTAmounts.length; i++) {
            _totalPortfolioValue += _BPTAmounts[i].mul(_BPTPrices[i]);
        }

        for (uint256 i = 0; i < _BPTAmounts.length; i++) {
            _weights[i] = _BPTAmounts[i].mul(_BPTPrices[i]).div(_totalPortfolioValue);
        }

        return _weights;
    }

    function checkStablecoinHealth(uint256 stablecoinPrice, address stablecoinAddress)
        public
        pure
        returns (bool)
    {
        // TODO: revisit
        //Price
        bool _stablecoinHealthy = true;

        if (stablecoinPrice >= 1.05e18) {
            _stablecoinHealthy = false;
        } else if (stablecoinPrice <= 0.95e18) {
            _stablecoinHealthy = false;
        }

        //Volume (to do)

        return _stablecoinHealthy;
    }

    function absValue(int128 _number) public pure returns (int128) {
        if (_number >= 0) {
            return _number;
        } else {
            return _number.neg();
        }
    }

    function getPrice(address _token, bytes32 _tokenSymbol) public returns (uint256) {
        return
            PriceOracle(_tokenAddressToProperties[_token].oracleAddress).getPrice(
                _token,
                _tokenSymbol
            );
    }

    function getAllTokenPrices() public returns (uint256[] memory) {
        uint256[] memory _allUnderlyingPrices;

        for (uint256 i = 0; i < underlyingTokenAddresses.length; i++) {
            _allUnderlyingPrices[i] = getPrice(
                underlyingTokenAddresses[i],
                _tokenAddressToProperties[underlyingTokenAddresses[i]].tokenSymbol
            );
        }
        return _allUnderlyingPrices;
    }

    function registerToken(address token, address oracleAddress) external {
        _tokenAddressToProperties[token].oracleAddress = oracleAddress;
    }

    function calculateAllPoolPrices(uint256[] memory _allUnderlyingPrices) public view returns (uint256[] memory _currentBPTPrices) {

        // Calculate BPT prices for all pools
        for (uint256 i = 0; i < poolProperties.length; i++) {
            BPool _bPool = BPool(poolProperties[i].poolAddress);

            address[] memory _bPoolUnderlyingTokens = _bPool.getFinalTokens();

            //For each pool fill the underlying token prices array
            uint256[] memory _bPoolUnderlyingTokenPrices;
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

            return _currentBPTPrices;
        }
    }

    function poolHealthHelper(uint256[] memory _allUnderlyingPrices, 
                              uint256 _poolIndex, 
                              address[] memory _BPTokensIn,
                              bool _allPoolsHealthy) 
                              public view returns(bool, bool ) {

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

                if (!checkStablecoinHealth(_stablecoinPrice, _BPTokensIn[_poolIndex])) {
                    _poolHealthy = false;
                    _allPoolsHealthy = false;
                    break;
                }
            }
        }

        return (_poolHealthy, _allPoolsHealthy);
    }

    function checkPoolsWithinEpsilon(address[] memory _BPTokensIn, 
                                  uint256[] memory _hypotheticalWeights, 
                                  uint256[] memory _idealWeights) 
                                  public view returns (bool[] memory, bool) {
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

    function checkAllPoolsHealthy(address[] memory _BPTokensIn, 
                                  uint256[] memory _hypotheticalWeights, 
                                  uint256[] memory _idealWeights, 
                                  uint256[] memory _allUnderlyingPrices) 
                                  public view returns (bool, bool, bool[] memory, bool[] memory) {

        // Check safety of input tokens
        bool _allPoolsWithinEpsilon;
        bool[] memory _poolsWithinEpsilon = new bool[](_BPTokensIn.length);
        bool[] memory _inputPoolHealth;
        bool _allPoolsHealthy = true;

        (_allPoolsWithinEpsilon, _poolsWithinEpsilon) = checkPoolsWithinEpsilon(_BPTokensIn, _hypotheticalWeights, _idealWeights);

        for (uint256 i = 0; i < _BPTokensIn.length; i++) {
            (_inputPoolHealth[i], _allPoolsHealthy) = poolHealthHelper(_allUnderlyingPrices, i, _BPTokensIn, _allPoolsHealthy);
        }

        return (_allPoolsHealthy, _allPoolsWithinEpsilon, _inputPoolHealth, _poolsWithinEpsilon);
    }

    function safeToMintOutsideEpsilon(address[] memory _BPTokensIn, 
                                        bool[] memory _inputPoolHealth, 
                                        uint256[] memory _inputBPTWeights, 
                                        uint256[] memory _idealWeights, 
                                        uint256[] memory _hypotheticalWeights, 
                                        uint256[] memory _currentWeights,
                                        bool[] memory _poolsWithinEpsilon) 
                                        public pure returns (bool _anyCheckFail) {
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
                int128 _idealWeight = _idealWeights[i].fromUInt();
                int128 _distanceHypotheticalToIdeal =
                    absValue(_hypotheticalWeights[i].fromUInt().sub(_idealWeight));
                int128 _distanceCurrentToIdeal =
                    absValue(_currentWeights[i].fromUInt().sub(_idealWeight));

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

    function checkBPTokenOrder(address[] memory _BPTokensIn) public view returns (bool _correct) {
        bool _correct = true;

        for (uint256 i = 0; i < poolProperties.length; i++) {
            if (poolProperties[i].poolAddress != _BPTokensIn[i]) {
                _correct = false;
                break;
            }
        }

        return _correct;
    }

    function safeToMint(address[] memory _BPTokensIn, 
                                  uint256[] memory _hypotheticalWeights, 
                                  uint256[] memory _idealWeights, 
                                  uint256[] memory _allUnderlyingPrices,
                                  uint256[] memory _amountsIn,
                                  uint256[] memory _currentBPTPrices,
                                  uint256[] memory _currentWeights)
                                  public view returns (bool _launch) {


        _launch = false;

        (bool _allPoolsHealthy, bool _allPoolsWithinEpsilon, bool[] memory _inputPoolHealth, bool[] memory _poolsWithinEpsilon) = checkAllPoolsHealthy(_BPTokensIn, _hypotheticalWeights, _idealWeights, _allUnderlyingPrices);

        // if check 1 succeeds and all pools healthy, then proceed with minting
        if (_allPoolsHealthy) {
            if (_allPoolsWithinEpsilon) {
                _launch = true;
            }
        } else {
            // calculate proportional values of assets user wants to pay with
            uint256[] memory _inputBPTWeights =
                calculatePortfolioWeights(_amountsIn, _currentBPTPrices);
            if (_allPoolsWithinEpsilon) {
                //Check that unhealthy pools have input weight below ideal weight. If true, mint
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
            //Outside of the epsilon boundary
            else {

                _launch = safeToMintOutsideEpsilon(_BPTokensIn, 
                                        _inputPoolHealth, 
                                        _inputBPTWeights, 
                                        _idealWeights, 
                                        _hypotheticalWeights, 
                                        _currentWeights,
                                        _poolsWithinEpsilon);
            }   
        }

        return _launch;
    }

    function safeToRedeem(address[] memory _BPTokensOut, 
                                  uint256[] memory _hypotheticalWeights, 
                                  uint256[] memory _idealWeights, 
                                  uint256[] memory _allUnderlyingPrices,
                                  uint256[] memory _amountsOut,
                                  uint256[] memory _currentBPTPrices,
                                  uint256[] memory _currentWeights)
                                  public view returns (bool _launch) {
        
        bool _launch = false;



    }

    function calculateAllWeights(uint256[] memory _currentBPTPrices, 
                                address[] memory _BPTokens, 
                                uint256[] memory _amountsIn,
                                uint256[] memory _amountsOut) 
                                public view returns (uint256[] memory _idealWeights, uint256[] memory _currentWeights, uint256[] memory _hypotheticalWeights) {
        //Calculate the up to date ideal portfolio weights
        _idealWeights = calculateImpliedPoolWeights(_currentBPTPrices);

        //Calculate the hypothetical weights if the new BPT tokens were added
        uint256[] memory _BPTNewAmounts;
        uint256[] memory _BPTCurrentAmounts;

        for (uint256 i = 0; i < _BPTokens.length; i++) {
            BPool _bPool = BPool(_BPTokens[i]);
            _BPTCurrentAmounts[i] = _bPool.balanceOf(msg.sender);
            _BPTNewAmounts[i] = _BPTCurrentAmounts[i].add(_amountsIn[i]).sub(_amountsOut[i]);
        }

        _currentWeights =
            calculatePortfolioWeights(_BPTCurrentAmounts, _currentBPTPrices);

        _hypotheticalWeights =
            calculatePortfolioWeights(_BPTNewAmounts, _currentBPTPrices);

        return (_idealWeights, _currentWeights, _hypotheticalWeights);

    }


    //_amountsIn in should have a zero index if nothing has been submitted for a particular token
    // _BPTokensIn and _amountsIn should have same indexes as poolProperties
    function mint(
        address[] memory _BPTokensIn,
        uint256[] memory _amountsIn,
        uint256 _minGyroMinted
    ) public returns (uint256 amountToMint) {
        require(
            _BPTokensIn.length == _amountsIn.length,
            "tokensIn and valuesIn should have the same number of elements"
        );

        //Filter 1: Require that the tokens are supported and in correct order
        bool _orderCorrect = checkBPTokenOrder(_BPTokensIn);
        require(
            _orderCorrect,
            "Input tokens in wrong order or contains invalid tokens"
        );

        uint256[] memory _zeroArray;
        for (uint256 i = 0; i < _BPTokensIn.length; i++) {
            _zeroArray[i] = 0;
        }

        uint256[] memory _allUnderlyingPrices = getAllTokenPrices();

        uint256[] memory _currentBPTPrices = calculateAllPoolPrices(_allUnderlyingPrices);

        (uint256[] memory _idealWeights, uint256[] memory _currentWeights, uint256[] memory _hypotheticalWeights) = calculateAllWeights(_currentBPTPrices, _BPTokensIn, _amountsIn, _zeroArray);

        bool _launch = safeToMint(_BPTokensIn, 
                                  _hypotheticalWeights, 
                                  _idealWeights, 
                                  _allUnderlyingPrices,
                                  _amountsIn,
                                  _currentBPTPrices,
                                  _currentWeights);

        if (_launch) {
            amountToMint = gyroPriceOracle.getAmountToMint(_BPTokensIn, _amountsIn);

            require(amountToMint >= _minGyroMinted, "too much slippage");

            for (uint256 i = 0; i < _BPTokensIn.length; i++) {
                bool success =
                    IERC20(_BPTokensIn[i]).transferFrom(msg.sender, address(this), _amountsIn[i]);
                require(success, "failed to transfer tokens, check allowance");
            }

            _mint(msg.sender, amountToMint);

            return amountToMint;
        }
    }

    function redeem(
        address[] memory _BPTokensOut,
        uint256[] memory _amountsOut,
        uint256 _maxGyroRedeemed
    ) public returns (uint256 gyroRedeemed) {
        require(
            _BPTokensOut.length == _amountsOut.length,
            "tokensIn and valuesIn should have the same number of elements"
        );

        //Filter 1: Require that the tokens are supported and in correct order
        bool _orderCorrect = checkBPTokenOrder(_BPTokensOut);
        require(
            _orderCorrect,
            "Input tokens in wrong order or contains invalid tokens"
        );

        uint256[] memory _zeroArray;
        for (uint256 i = 0; i < _BPTokensOut.length; i++) {
            _zeroArray[i] = 0;
        }

        uint256[] memory _allUnderlyingPrices = getAllTokenPrices();

        uint256[] memory _currentBPTPrices = calculateAllPoolPrices(_allUnderlyingPrices);

        (uint256[] memory _idealWeights, uint256[] memory _currentWeights, uint256[] memory _hypotheticalWeights) = calculateAllWeights(_currentBPTPrices, _BPTokensOut, _zeroArray, _amountsOut);

        bool _launch;



        _burn(msg.sender, _gyroAmountBurned);
        uint256[] memory amountsOut =
            gyroPriceOracle.getAmountsToPayback(_gyroAmountBurned, _tokensOut);
        gyroRouter.withdraw(_tokensOut, amountsOut);

        for (uint256 i = 0; i < _tokensOut.length; i++) {
            require(amountsOut[i] >= _minAmountsOut[i], "too much slippage");
            bool success =
                IERC20(_tokensOut[i]).transferFrom(address(gyroRouter), msg.sender, amountsOut[i]);
            require(success, "failed to transfer tokens");
        }

        // emit Redeem(msg.sender, _gyroAmountBurned);

        return amountsOut;
    }
}
