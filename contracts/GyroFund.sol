// SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./GyroPriceOracle.sol";
import "./GyroRouter.sol";
import "./Ownable.sol";
import "./abdk/ABDKMath64x64.sol";

interface GyroFund is IERC20 {
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

    function getPoolAddresses() public returns (address[]);

    function getPoolWeights() public returns (uint256);

    function getStablecoinAddresses() public returns (address[]);

    function getTotalNumberOfPools() public returns (uint256);

    function checkAssetSafety(address memory _tokenIn) external returns (bool);
        //1. Check the price
        //2. Check the volume

    function checkPortfolioWeights(address memory _tokenIn, uint256 memory _amountIn) external returns(bool);

    // function updatePoolWeights(); 

 
}

contract GyroFundV1 is GyroFund, Ownable, ERC20 {
    using ExtendedMath for int128;
    using ABDKMath64x64 for uint256;
    using ABDKMath64x64 for int128;

    GyroPriceOracle gyroPriceOracle;
    GyroRouter gyroRouter;
    PriceOracle priceOracle;

    struct tokenProperties {
        address oracleAddress;
        bytes32 tokenSymbol;
        uint16 tokenIndex;
    }

    mapping(address => tokenProperties) _tokenAddressToProperties;
    mapping(address => bool) _checkPoolIsValid;
    mapping(address => bool) _checkIsStablecoin;

    address[] underlyingTokens;
    int128[] _originalBPTPrices;
    int128 portfolioWeightEpsilon;

    struct PoolProperties {
        address poolAddress;
        int128 initialPoolWeight;
        int128 initialPoolPrice;
    }
    
    PoolProperties[] poolProperties;

    constructor(int128 _portfolioWeightEpsilon, 
                int128[] _initialPoolWeights, 
                address[] _gyroPoolAddresses, 
                address _priceOracleAddress, 
                address _routerAddress, 
                address[] _underlyingTokens, 
                address[] _underlyingTokenOracleAddresses, 
                bytes32[] _underlyingTokenSymbols,
                address[] _stablecoinAddresses
                )
                
        ERC20("Gyro Stable Coin", "GYRO")
    {
        gyroPriceOracle = GyroPriceOracle(_priceOracleAddress);
        gyroRouter = GyroRouter(_routerAddress);

        underlyingTokens = _underlyingTokens;

        for (uint256 i = 0; i < _gyroPoolAddresses.length; i++) {
            _checkPoolIsValid[_gyroPoolAddresses[i]] = true;
        }

        for (uint256 i=0; i < _gyroPoolAddresses.length; i++) {
            poolProperties[i].poolAddress = _gyroPoolAddresses[i];
            poolProperties[i].initialPoolWeight = _initialPoolWeights[i];
            poolProperties[i].initialPoolPrice = _initialPoolPrices[i];
        }


        for (uint256 i = 0; i < _underlyingTokens.length; i++) {
            _tokenAddressToProperties[_underlyingtokens[i]].oracleAddress = _underlyingTokenOracleAddresses[i];
            _tokenAddressToProperties[_underlyingtokens[i]].tokenSymbol = _underlyingTokenSymbols[i];
            _tokenAddressToProperties[_underlyingtokens[i]].tokenIndex = i;
        }

        int128[] memory _underlyingPrices = getAllTokenPrices();

        int128 portfolioWeightEpsilon = _portfolioWeightEpsilon; 

        // Calculate BPT prices for all pools
        for (uint256 i = 0; i < poolProperties.length; i++) {

            BPool _bPool = BPool(poolProperties[i].poolAddress);

            //For each pool get the addresses of the underlying tokens
            address[] memory _bPoolUnderlyingTokens = _bpool.getFinalTokens();

            //For each pool fill the underlying token prices array
            int128 _bPoolUnderlyingTokenPrices;
            for (uint256 j = 0; j < _bPoolUnderlyingTokens.length; j++) {
                _bPoolUnderlyingTokenPrices[j] = _underlyingPrices[_tokenAddressToProperties[_bPoolUnderlyingTokens[j]].tokenIndex];
            }
            
            // Calculate BPT price for the pool
            _originalBPTPrices[i] = gyroPriceOracle.getBPTPrice(
                    poolProperties[i].poolAddress,
                    _bPoolUnderlyingTokens,
                    _bPoolUnderlyingTokenPrices
                    );
             
        }

        for (uint256 i=l; i < _stablecoinAddresses.length; i++) {
            _checkIsStablecoin[_stablecoinAddresses[i]] = true;
        }

    }

    address immutable daiethpool = '0x..';
    address immutable usdcethpool = '0x..';

    address immutable dai = '0x..';
    address immutable usdc = '0x..';

    function getPoolWeights() public returns (uint256[]) {
        return(daiethpoolweight, usdcethpoolweight);
    }

    function getPoolAddresses() public returns (address[]) {
        return(daiethpool, usdcethpool);
    }

    function getStablecoinAddresses() public returns (address[]) {
        return(dai, usdc);
    }

    function getAllTokenPrices() public returns (int128[]) {
        
        mapping(address => int128) _tokenToPrice;

        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            _underlyingPrices[i] = getPrice(underlyingTokens[i], _tokenAddressToProperties[underlyingTokens[i]].tokenSymbol);
        }
        return _underlyingPrices;
    }

    function calculateImpliedPoolWeights( int128[] _BPTPrices) public returns (int128[]) {
        // order of _BPTPrices must be same as order of poolProperties
        int128[] memory _newWeights;
        int128[] memory _weightedReturns;

        int128[] memory _initPoolPrices;
        int128[] memory _initWeights;
        for (uint256 i= 0; i< poolProperties.length; i++) {
            _initPoolPrices[i] = poolProperties[i].initialPoolPrice;
            _initWeights[i] = poolProperties[i].initialPoolWeight;
        }
        
        for (uint256 i =0; i < _BPTPrices.length; i++) {
            _weightedReturns[i] = BPTPrices[i].div(_initPoolPrices[i]).mul(_initWeights[i]);
        }
        
        int128 _returnsSum = 0;
        for (uint256 i =0; i < _BPTPrices.length; i++) {
            _returnsSum = _returnsSum.add(_returns[i]);
        }

        for (uint256 i =0; i < _BPTPrices.length; i++) {
            _newWeights[i] = _returns[i].div(_returnsSum);
        }

        return _newWeights;
    }

    function calculatePortfolioWeights(uint256[] _BPTAmounts, int128[] _BPTPrices) external returns (int128[]) {
        int128[] memory _weights;
        int128 _totalPortfolioValue = 0;

        for (uint256 i = 0; i < _BPTAmounts.length; i++) {
            _totalPortfolioValue += _BPTAmounts[i].mul(_BPTPrices[i]);
        }

        for (uint256 i = 0; i < _BPTAmounts.length; i++) {
            _weights[i] = _BPTAmounts[i].mul(_BPTPrices[i]).div(_totalPortfolioValue);
        }

        return _weights;

        
    }

    function checkStablecoinHealth(int128 stablecoinPrice, address stablecoinAddress) external returns (bool) {
        // TODO: revisit
        //Price
        bool _stablecoinHealthy = true;

        if (stablecoinPrice >= 1.05) {
            _stablecoinHealthy = false;
        }
        else if (stablecoinPrice <= 0.95) {
            _stablecoinHealthy = false;
        }

        //Volume (to do)

        return _stablecoinHealthy;

    }

    function absValue(int128 _number) public returns (int128) {
        if (_number >= 0) {
            return _number;
        } else {
            return _number.neg();
        }
    }


    function getPrice(address _token, string _tokenSymbol) external returns (int128) {
        return priceOracle(_tokenAddressToProperties[_token].oracleAddress).getPrice(_token, _tokenSymbol).fromUInt();
    }

    function registerToken(address token, address oracleAddress) external {
        tokens[token] = oracleAddress;
    }

    //_amountsIn in should have a zero index if nothing has been submitted for a particular token
    // _BPTokensIn and _amountsIn should have same indexes as poolProperties
    function mint(
        address[] memory _BPTokensIn,
        uint256[] memory _amountsIn,
        uint256 _minGyroMinted
    ) public override returns (uint256) {
        require(
            _BPTokensIn.length == _amountsIn.length,
            "tokensIn and valuesIn should have the same number of elements"
        );

        //Filter 1: Require that the tokens are supported
        for (uint256 i = 0; i < _BPTokensIn.length; i++) {
            require(_checkPoolIsValid[_BPTokensIn[i]], "Input token invalid");
        }

        int128[] memory _currentBPTPrices;
        int128[] memory _underlyingPrices = getAllTokenPrices();

        // Calculate BPT prices for all pools
        for (uint256 i = 0; i < poolProperties.length; i++) {

            BPool _bPool = BPool(poolProperties[i].poolAddress);

            //For each pool get the addresses of the underlying tokens
            address[] memory _bPoolUnderlyingTokens = _bpool.getFinalTokens();

            //For each pool fill the underlying token prices array
            int128[] memory _bPoolUnderlyingTokenPrices;
            for (uint256 j = 0; j < _bPoolUnderlyingTokens.length; j++) {
                _bPoolUnderlyingTokenPrices[j] = _underlyingPrices[_tokenAddressToProperties[_bPoolUnderlyingTokens[j]].tokenIndex];
            }
            
            // Calculate BPT price for the pool
            _currentBPTPrices[i] = gyroPriceOracle.getBPTPrice(
                    poolProperties[i].poolAddress,
                    _bPoolUnderlyingTokens,
                    _bPoolUnderlyingTokenPrices
                    );
             
        }

        //Calculate the up to date ideal portfolio weights
        int128[] memory _idealWeights = calculateImpliedPoolWeights(_currentBPTPrices);

        //Calculate the hypothetical weights if the new BPT tokens were added
        uint256[] memory _BPTNewAmounts;
        uint256[] memory _BPTCurrentAmounts;

        for (uint256 i = 0; i < _BPTokensIn.length; i++) {
            BPool _bPool = BPool(_BPTokensIn[i]);
            _BPTCurrentAmounts[i] = _bPool.balanceOf(msg.sender);
            _BPTNewAmounts[i] = _BPTCurrentAmounts[i] + _AmountsIn[i]; 
        }

        uint256[] memory _currentWeights = calculatePortfolioWeights(_BPTCurrentAmounts, _currentBPTPrices);

        uint256[] memory _hypotheticalWeights = calculatePortfolioWeights(_BPTNewAmounts, _currentBPTPrices);

        int128 memory _portfolioWeightEpsilon = portfolioWeightEpsilon;

        bool _launch = false;    
        bool _allPoolsWithinEpsilon = true;
        bool[] _poolsWithinEpsilon;
        bool[] memory _inputPoolHealth;
        bool _allPoolsHealthy = true;
        
        address[] memory _bPoolUnderlyingTokens = BPool.getFinalTokens();


        // Check safety of input tokens
        for (uint256 i=0; i < _BPTokensIn.length; i++) {

            // Check 1: check whether hypothetical weight will be within epsilon
            _poolsWithinEpsilon[i] = true;
            if (_hypotheticalWeights[i] >= _idealWeights[i] + _portfolioWeightEpsilon) {
                _allPoolsWithinEpsilon = false;
                _poolsWithinEpsilon[i] = false;
            } else if (_hypotheticalWeights[i] <= _idealWeights[i] - _portfolioWeightEpsilon) {
                _allPoolsWithinEpsilon = false;
                _poolsWithinEpsilon[i] = false;
            }

            _inputPoolHealth[i] = true;
            
            //Go through the underlying tokens within the pool
            for (uint256 j=0; j < _bPoolUnderlyingTokens.length; j++) {
                if(_checkIsStablecoin[_bPoolUnderlyingTokens[j]]) {
                    _stablecoinPrice = _underlyingPrices[_tokenAddressToProperties[_bPoolUnderlyingTokens[j]].tokenIndex];

                    if (! checkStablecoinHealth(_stablecoinPrice, _BPTokensIn[i])) {
                        _inputPoolHealth[i] = false;
                        _allPoolsHealthy = false;
                        break;
                    }
                }
            }
        }

        // if check 1 succeeds and all pools healthy, then proceed with minting
        if (_allPoolsHealthy) {
            if (_allPoolsWithinEpsilon) {
                _launch = true; 
            }
        }
        else {
            // calculate proportional values of assets user wants to pay with
            int128[] memory _inputBPTWeights = calculatePortfolioWeights(_amountsIn, _currentBPTPrices);
            if (_allPoolsWithinEpsilon) {
                //Check that unhealthy pools have input weight below ideal weight. If true, mint
                bool _unhealthyMovesTowardIdeal = true;
                for (uint256 i; i< _BPTokensIn.length; i++) {
                    if (! _inputPoolHealth[i]) {
                        if(_inputBPTWeights[i] > _idealWeights[i]) {
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
                //Check that amount above epsilon is decreasing
                //Check that unhealthy pools have input weight below ideal weight
                //If both true, then mint
                //note: should always be able to mint at the ideal weights!
                bool _anyCheckFail = false;
                for (uint256 i; i< _BPTokensIn.length; i++) {

                    if (! _inputPoolHealth[i]) {
                        if(_inputBPTWeights[i] > _idealWeights[i]) {
                            _anyCheckFail = true;
                            break;
                        }
                    }

                    if (! _poolsWithinEpsilon[i]) {

                        // check if _hypotheticalWeights[i] is closer to _idealWeights[i] than _currentWeights[i]
                        int128 _distanceHypotheticalToIdeal = absValue(_hypotheticalWeights[i].sub(_idealWeights[i]));
                        int128 _distanceCurrentToIdeal = absValue(_currentWeights[i].sub(_idealWeights[i]));
                        
                        if (_distanceHypotheticalToIdeal >= _distanceCurrentToIdeal) {
                            _anyCheckFail = true;
                            break;
                        }
                    }
                }

                if (! _anyCheckFail) {
                    _launch = true;
                }
            }
        }

        if (_launch) {

            uint256 amountToMint = gyroPriceOracle.getAmountToMint(_tokensIn, _amountsIn);

            require(amountToMint >= _minGyroMinted, "too much slippage");

            for (uint256 i = 0; i < _tokensIn.length; i++) {
                bool success =
                    IERC20(_tokensIn[i]).transferFrom(msg.sender, address(this), _amountsIn[i]);
                require(success, "failed to transfer tokens, check allowance");
            }

            _mint(msg.sender, amountToMint);

            return amountToMint;
        }
    }



    function redeem(
        uint256 _gyroAmountBurned,
        address[] memory _tokensOut,
        uint256[] memory _minAmountsOut
    ) public override returns (uint256[] memory) {
        require(
            _tokensOut.length == _minAmountsOut.length,
            "_tokensOut and _minValuesOut should have the same number of elements"
        );

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

        return amountsOut;
    }
}