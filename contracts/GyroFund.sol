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

    function getTotalNumberOfPools() external returns (uint256);

    function checkAssetSafety(address _tokenIn) external returns (bool);

    function checkPortfolioWeights(address _tokenIn, uint256 _amountIn) external returns(bool);

}

abstract contract GyroFundV1 is GyroFund, Ownable, ERC20 {
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

    struct PoolProperties {
    address poolAddress;
    int128 initialPoolWeight;
    int128 initialPoolPrice;
    }
    
    PoolProperties[] poolProperties;

    mapping(address => tokenProperties) _tokenAddressToProperties;
    mapping(address => bool) _checkPoolIsValid;
    mapping(address => bool) _checkIsStablecoin;

    uint64[] _originalBPTPrices;

    address[] underlyingTokenAddresses;

    int128 portfolioWeightEpsilon;

    constructor(int128 _portfolioWeightEpsilon, 
                int128[] memory _initialPoolWeights, 
                address[] memory _gyroPoolAddresses, 
                address _priceOracleAddress, 
                address _routerAddress, 
                address[] memory _underlyingTokenAddresses, 
                address[] memory _underlyingTokenOracleAddresses, 
                bytes32[] memory _underlyingTokenSymbols,
                address[] memory _stablecoinAddresses
                )
                
        ERC20("Gyro Stable Coin", "GYRO")

    {
        gyroPriceOracle = GyroPriceOracle(_priceOracleAddress);
        gyroRouter = GyroRouter(_routerAddress);

        underlyingTokenAddresses = _underlyingTokenAddresses;
        
        portfolioWeightEpsilon = _portfolioWeightEpsilon; 


        for (uint256 i = 0; i < _gyroPoolAddresses.length; i++) {
            _checkPoolIsValid[_gyroPoolAddresses[i]] = true;
        }

        for (uint256 i=0; i < _gyroPoolAddresses.length; i++) {
            poolProperties[i].poolAddress = _gyroPoolAddresses[i];
            poolProperties[i].initialPoolWeight = _initialPoolWeights[i];
        }

        for (uint256 i = 0; i < _underlyingTokenAddresses.length; i++) {
            _tokenAddressToProperties[_underlyingTokenAddresses[i]].oracleAddress = _underlyingTokenOracleAddresses[i];
            _tokenAddressToProperties[_underlyingTokenAddresses[i]].tokenSymbol = _underlyingTokenSymbols[i];
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
                _bPoolUnderlyingTokenPrices[j] = _underlyingPrices[_tokenAddressToProperties[_bPoolUnderlyingTokens[j]].tokenIndex];
            }
            
            // Calculate BPT price for the pool
            _originalBPTPrices[i] = gyroPriceOracle.getBPTPrice(
                    poolProperties[i].poolAddress,
                    _bPoolUnderlyingTokenPrices
                    );
             
        }

        for (uint256 i = 0; i < _gyroPoolAddresses.length; i++) {
            poolProperties[i].initialPoolPrice = _originalBPTPrices[i];
        }

        for (uint256 i = 1; i < _stablecoinAddresses.length; i++) {
            _checkIsStablecoin[_stablecoinAddresses[i]] = true;
        }

    }

    function calculateImpliedPoolWeights(int128[] memory _BPTPrices) public returns (int128[] memory) {
        // order of _BPTPrices must be same as order of poolProperties
        int128[] memory _newWeights;
        int128[] memory _weightedReturns;

        int128[] memory _initPoolPrices;
        int128[] memory _initWeights;
        int128[] memory _returns;
        for (uint256 i= 0; i< poolProperties.length; i++) {
            _initPoolPrices[i] = poolProperties[i].initialPoolPrice;
            _initWeights[i] = poolProperties[i].initialPoolWeight;
        }
        
        for (uint256 i =0; i < _BPTPrices.length; i++) {
            _weightedReturns[i] = _BPTPrices[i].div(_initPoolPrices[i]).mul(_initWeights[i]);
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

    function calculatePortfolioWeights(uint256[] memory _BPTAmounts, int128[] memory _BPTPrices) public returns (int128[] memory) {
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

    function checkStablecoinHealth(int128 stablecoinPrice, address stablecoinAddress) public returns (bool) {
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


    function getPrice(address _token, bytes32 _tokenSymbol) public returns (int128) {
        return priceOracle(_tokenAddressToProperties[_token].oracleAddress).getPrice(_token, _tokenSymbol).fromUInt();
    }

    function getAllTokenPrices() public returns (uint256[] memory) {

        uint256[] memory _allUnderlyingPrices;
        
        for (uint256 i = 0; i < underlyingTokenAddresses.length; i++) {
            _allUnderlyingPrices[i] = getPrice(underlyingTokenAddresses[i], _tokenAddressToProperties[underlyingTokenAddresses[i]].tokenSymbol);
        }
        return _allUnderlyingPrices;
    }


    function registerToken(address token, address oracleAddress) external {
        token[token] = oracleAddress;
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
        uint256[] memory _allUnderlyingPrices = getAllTokenPrices();

        // Calculate BPT prices for all pools
        for (uint256 i = 0; i < poolProperties.length; i++) {

            BPool _bPool = BPool(poolProperties[i].poolAddress);

            address[] memory _bPoolUnderlyingTokens = _bPool.getFinalTokens();

            //For each pool fill the underlying token prices array
            int128[] memory _bPoolUnderlyingTokenPrices;
            for (uint256 j = 0; j < _bPoolUnderlyingTokens.length; j++) {
                _bPoolUnderlyingTokenPrices[j] = _allUnderlyingPrices[_tokenAddressToProperties[_bPoolUnderlyingTokens[j]].tokenIndex];
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
            _BPTNewAmounts[i] = _BPTCurrentAmounts[i] + _amountsIn[i]; 
        }

        uint256[] memory _currentWeights = calculatePortfolioWeights(_BPTCurrentAmounts, _currentBPTPrices);

        uint256[] memory _hypotheticalWeights = calculatePortfolioWeights(_BPTNewAmounts, _currentBPTPrices);

        int128 _portfolioWeightEpsilon = portfolioWeightEpsilon;

        bool _launch = false;    
        bool _allPoolsWithinEpsilon = true;
        bool[] memory _poolsWithinEpsilon;
        bool[] memory _inputPoolHealth;
        bool _allPoolsHealthy = true;
        
        

        // Core minting logic
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

            BPool _bPool = BPool(poolProperties[i].poolAddress);
            address[] memory _bPoolUnderlyingTokens = _bPool.getFinalTokens();
            
            //Go through the underlying tokens within the pool
            for (uint256 j=0; j < _bPoolUnderlyingTokens.length; j++) {
                if(_checkIsStablecoin[_bPoolUnderlyingTokens[j]]) {
                    int128 _stablecoinPrice = _allUnderlyingPrices[_tokenAddressToProperties[_bPoolUnderlyingTokens[j]].tokenIndex];

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

            uint256 amountToMint = gyroPriceOracle.getAmountToMint(_BPTokensIn, _amountsIn);

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