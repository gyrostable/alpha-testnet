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

    function mintTest(
        address[] memory _BPTokensIn,
        uint256[] memory _amountsIn,
        uint256 _gyroToMint
    ) external returns (uint256);

    function redeem(
        address[] memory _BPTokensOut,
        uint256[] memory _amountsOut,
        uint256 _maxGyroRedeemed
    ) external returns (uint256);

    function estimateMint(address[] memory _tokensIn, uint256[] memory _amountsIn)
        external
        view
        returns (uint256);

    function estimateRedeem(address[] memory _BPTokensOut, uint256[] memory _amountsOut)
        external
        view
        returns (uint256);

    function wouldMintChecksPass(address[] memory _BPTokensIn, 
                            uint256[] memory _amountsIn, 
                            uint256 _minGyroMinted) 
                            external
                            view
                            returns(bool, string memory);


    function wouldRedeemChecksPass(address[] memory _BPTokensOut, 
                            uint256[] memory _amountsOut, 
                            uint256 _maxGyroRedeemed) 
                            external
                            view
                            returns(bool, string memory);
}

contract GyroFundV1 is GyroFund, Ownable, ERC20 {
    using ExtendedMath for int128;
    using ABDKMath64x64 for uint256;
    using ABDKMath64x64 for int128;
    using SafeMath for uint256;
    using ExtendedMath for uint256;

    GyroPriceOracle gyroPriceOracle;
    GyroRouter gyroRouter;
    PriceOracle priceOracle;

    struct TokenProperties {
        address oracleAddress;
        bytes32 tokenSymbol;
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
    }

    struct FlowLogger {
        uint256 _inflowHistory;
        uint256 _outflowHistory;
        uint256 _currentBlock;
        uint256 _lastSeenBlock;
    }

    PoolProperties[] public poolProperties;

    mapping(address => TokenProperties) _tokenAddressToProperties;
    mapping(address => bool) _checkPoolIsValid;

    mapping(address => bool) _checkIsStablecoin;

    address[] underlyingTokenAddresses;

    uint256 portfolioWeightEpsilon;
    uint256 lastSeenBlock;
    uint256 inflowHistory;
    uint256 outflowHistory;
    uint256 memoryParam;

    constructor(
        uint256 _portfolioWeightEpsilon,
        uint256[] memory _initialPoolWeights,
        address[] memory _gyroPoolAddresses,
        address _priceOracleAddress,
        address _routerAddress,
        address[] memory _underlyingTokenAddresses,
        address[] memory _underlyingTokenOracleAddresses,
        bytes32[] memory _underlyingTokenSymbols,
        address[] memory _stablecoinAddresses,
        uint256 _memoryParam
    ) ERC20("Gyro Stable Coin", "GYRO") {
        gyroPriceOracle = GyroPriceOracle(_priceOracleAddress);
        gyroRouter = GyroRouter(_routerAddress);

        lastSeenBlock = block.number;
        inflowHistory = 0;
        outflowHistory = 0;
        memoryParam = _memoryParam;

        underlyingTokenAddresses = _underlyingTokenAddresses;

        portfolioWeightEpsilon = _portfolioWeightEpsilon;

        for (uint256 i = 0; i < _gyroPoolAddresses.length; i++) {
            _checkPoolIsValid[_gyroPoolAddresses[i]] = true;
        }

        for (uint256 i = 0; i < _gyroPoolAddresses.length; i++) {
            PoolProperties storage poolProps;
            poolProps.poolAddress = _gyroPoolAddresses[i];
            poolProps.initialPoolWeight = _initialPoolWeights[i];
            poolProperties.push(poolProps);
        }

        for (uint256 i = 0; i < _underlyingTokenAddresses.length; i++) {
            TokenProperties storage tokenProps;
            tokenProps.oracleAddress = _underlyingTokenOracleAddresses[i];
            tokenProps.tokenSymbol = _underlyingTokenSymbols[i];
            tokenProps.tokenIndex = uint16(i);
            _tokenAddressToProperties[_underlyingTokenAddresses[i]] = tokenProps;
        }

        // Calculate BPT prices for all pools
        uint256[] memory _underlyingPrices = getAllTokenPrices();

        for (uint256 i = 0; i < poolProperties.length; i++) {
            BPool _bPool = BPool(poolProperties[i].poolAddress);

            //For each pool get the addresses of the underlying tokens
            address[] memory _bPoolUnderlyingTokens = _bPool.getFinalTokens();

            //For each pool fill the underlying token prices array
            uint256[] memory _bPoolUnderlyingTokenPrices =
                new uint256[](_bPoolUnderlyingTokens.length);
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

        for (uint256 i = 0; i < _stablecoinAddresses.length; i++) {
            _checkIsStablecoin[_stablecoinAddresses[i]] = true;
        }
    }

    function calculateImpliedPoolWeights(uint256[] memory _BPTPrices)
        public
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

    function nav(uint256 _totalPortfolioValue) public view returns (uint256 _nav) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply > 0) {
            _nav = _totalPortfolioValue.scaledDiv(totalSupply());
        } else {
            _nav = 1e18;
        }

        return _nav;
    }

    function calculatePortfolioWeights(uint256[] memory _BPTAmounts, uint256[] memory _BPTPrices)
        public
        pure
        returns (uint256[] memory, uint256)
    {
        uint256[] memory _weights;
        uint256 _totalPortfolioValue = 0;

        for (uint256 i = 0; i < _BPTAmounts.length; i++) {
            _totalPortfolioValue = _totalPortfolioValue.add(
                _BPTAmounts[i].scaledMul(_BPTPrices[i])
            );
        }

        if (_totalPortfolioValue == 0) {
            return (_weights, _totalPortfolioValue);
        }

        _weights = new uint256[](_BPTPrices.length);

        for (uint256 i = 0; i < _BPTAmounts.length; i++) {
            _weights[i] = _BPTAmounts[i].scaledMul(_BPTPrices[i]).scaledDiv(_totalPortfolioValue);
        }

        return (_weights, _totalPortfolioValue);
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

    function absValueSub(uint256 _number1, uint256 _number2) public pure returns (uint256) {
        if (_number1 >= _number2) {
            return _number1.sub(_number2);
        } else {
            return _number2.sub(_number1);
        }
    }

    function getPrice(address _token, bytes32 _tokenSymbol) public view returns (uint256) {
        return
            PriceOracle(_tokenAddressToProperties[_token].oracleAddress).getPrice(
                bytes32ToString(_tokenSymbol)
            );
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
            bytes32 _tokenSymbol =
                _tokenAddressToProperties[underlyingTokenAddresses[i]].tokenSymbol;
            uint256 _tokenPrice = getPrice(_tokenAddress, _tokenSymbol);
            _allUnderlyingPrices[i] = _tokenPrice;
        }
        return _allUnderlyingPrices;
    }

    function registerToken(address token, address oracleAddress) external {
        _tokenAddressToProperties[token].oracleAddress = oracleAddress;
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

    function poolHealthHelper(
        uint256[] memory _allUnderlyingPrices,
        uint256 _poolIndex,
        address[] memory _BPTokensIn,
        bool _allPoolsHealthy
    ) public view returns (bool, bool) {
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

    function checkPoolsWithinEpsilon(
        address[] memory _BPTokensIn,
        uint256[] memory _hypotheticalWeights,
        uint256[] memory _idealWeights
    ) public view returns (bool, bool[] memory) {
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
        public
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
            (_inputPoolHealth[i], _allPoolsHealthy) = poolHealthHelper(
                _allUnderlyingPrices,
                i,
                _BPTokensIn,
                _allPoolsHealthy
            );
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
    ) public pure returns (bool _anyCheckFail) {
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

    function checkBPTokenOrder(address[] memory _BPTokensIn) public view returns (bool _correct) {

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
    ) public pure returns (bool _launch) {
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
    ) public view returns (bool _launch) {
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
    ) public view returns (bool) {
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
        public
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

    function mintTest(
        address[] memory _BPTokensIn,
        uint256[] memory _amountsIn,
        uint256 _gyroToMint
    ) public override returns (uint256) {
        for (uint256 i = 0; i < _BPTokensIn.length; i++) {
            bool success =
                IERC20(_BPTokensIn[i]).transferFrom(msg.sender, address(this), _amountsIn[i]);
            require(success, "failed to transfer tokens, check allowance");
        }

        _mint(msg.sender, _gyroToMint);
        emit Mint(msg.sender, _gyroToMint);
        return _gyroToMint;
    }

    //_amountsIn in should have a zero index if nothing has been submitted for a particular token
    // _BPTokensIn and _amountsIn should have same indexes as poolProperties
    function mint(
        address[] memory _BPTokensIn,
        uint256[] memory _amountsIn,
        uint256 _minGyroMinted
    ) public override returns (uint256 amountToMint) {
        require(
            _BPTokensIn.length == _amountsIn.length,
            "tokensIn and valuesIn should have the same number of elements"
        );

        //Filter 1: Require that the tokens are supported and in correct order
        bool _orderCorrect = checkBPTokenOrder(_BPTokensIn);
        require(_orderCorrect, "Input tokens in wrong order or contains invalid tokens");

        uint256[] memory _zeroArray = new uint256[](_BPTokensIn.length);
        for (uint256 i = 0; i < _BPTokensIn.length; i++) {
            _zeroArray[i] = 0;
        }

        uint256[] memory _allUnderlyingPrices = getAllTokenPrices();

        uint256[] memory _currentBPTPrices = calculateAllPoolPrices(_allUnderlyingPrices);

        Weights memory weights;

        (
            weights._idealWeights,
            weights._currentWeights,
            weights._hypotheticalWeights,
            weights._nav,
            weights._totalPortfolioValue
        ) = calculateAllWeights(_currentBPTPrices, _BPTokensIn, _amountsIn, _zeroArray);

        bool _launch =
            safeToMint(
                _BPTokensIn,
                weights._hypotheticalWeights,
                weights._idealWeights,
                _allUnderlyingPrices,
                _amountsIn,
                _currentBPTPrices,
                weights._currentWeights
            );

        if (!_launch) {
            revert("Too windy for launch");
        }

        weights._dollarValue = 0;

        for (uint256 i = 0; i < _BPTokensIn.length; i++) {
            weights._dollarValue = weights._dollarValue.add(
                _amountsIn[i].scaledMul(_currentBPTPrices[i])
            );
        }

        FlowLogger memory flowLogger;
        (
            flowLogger._inflowHistory,
            flowLogger._outflowHistory,
            flowLogger._currentBlock,
            flowLogger._lastSeenBlock
        ) = initializeFlowLogger();

        amountToMint = gyroPriceOracle.getAmountToMint(
            weights._dollarValue,
            flowLogger._inflowHistory,
            weights._nav
        );

        require(amountToMint >= _minGyroMinted, "too much slippage");

        for (uint256 i = 0; i < _BPTokensIn.length; i++) {
            bool success =
                IERC20(_BPTokensIn[i]).transferFrom(msg.sender, address(this), _amountsIn[i]);
            require(success, "failed to transfer tokens, check allowance");
        }

        _mint(msg.sender, amountToMint);

        finalizeFlowLogger(
            flowLogger._inflowHistory,
            flowLogger._outflowHistory,
            amountToMint,
            0,
            flowLogger._currentBlock,
            flowLogger._lastSeenBlock
        );

        return amountToMint;
    }

    function wouldMintChecksPass(address[] memory _BPTokensIn, 
                            uint256[] memory _amountsIn, 
                            uint256 _minGyroMinted) 
                            public
                            override
                            view
                            returns(bool, string memory) {

        require(
            _BPTokensIn.length == _amountsIn.length,
            "tokensIn and valuesIn should have the same number of elements"
        );

        //Filter 1: Require that the tokens are supported and in correct order
        bool _orderCorrect = checkBPTokenOrder(_BPTokensIn);
        require(_orderCorrect, "Input tokens in wrong order or contains invalid tokens");

        uint256[] memory _zeroArray = new uint256[](_BPTokensIn.length);
        for (uint256 i = 0; i < _BPTokensIn.length; i++) {
            _zeroArray[i] = 0;
        }

        uint256[] memory _allUnderlyingPrices = getAllTokenPrices();

        uint256[] memory _currentBPTPrices = calculateAllPoolPrices(_allUnderlyingPrices);

        Weights memory weights;

        (
            weights._idealWeights,
            weights._currentWeights,
            weights._hypotheticalWeights,
            weights._nav,
            weights._totalPortfolioValue
        ) = calculateAllWeights(_currentBPTPrices, _BPTokensIn, _amountsIn, _zeroArray);

        bool _launch =
            safeToMint(
                _BPTokensIn,
                weights._hypotheticalWeights,
                weights._idealWeights,
                _allUnderlyingPrices,
                _amountsIn,
                _currentBPTPrices,
                weights._currentWeights
            );

        if (!_launch) {
            string memory errorMessage = "This combination of tokens would move gyroscope weights too far from target.";
            return (false, errorMessage);
        }

        weights._dollarValue = 0;

        for (uint256 i = 0; i < _BPTokensIn.length; i++) {
            weights._dollarValue = weights._dollarValue.add(
                _amountsIn[i].scaledMul(_currentBPTPrices[i])
            );
        }

        FlowLogger memory flowLogger;
        (
            flowLogger._inflowHistory,
            flowLogger._outflowHistory,
            flowLogger._currentBlock,
            flowLogger._lastSeenBlock
        ) = initializeFlowLogger();

        uint256 amountToMint = gyroPriceOracle.getAmountToMint(
            weights._dollarValue,
            flowLogger._inflowHistory,
            weights._nav
        );

        if (amountToMint < _minGyroMinted) {
            string memory errorMessage = "Too much slippage is expected";
            return (false, errorMessage);
        } else {
            string memory happyMessage = "Minting checks pass.";
            return (true, happyMessage);
        }


    }

    function wouldRedeemChecksPass(
        address[] memory _BPTokensOut,
        uint256[] memory _amountsOut,
        uint256 _maxGyroRedeemed
        ) public override view returns (bool, string memory) {

        require(
            _BPTokensOut.length == _amountsOut.length,
            "tokensIn and valuesIn should have the same number of elements"
        );

        //Filter 1: Require that the tokens are supported and in correct order
        require(
            checkBPTokenOrder(_BPTokensOut),
            "Input tokens in wrong order or contains invalid tokens"
        );

        uint256[] memory _zeroArray = new uint256[](_BPTokensOut.length);
        for (uint256 i = 0; i < _BPTokensOut.length; i++) {
            _zeroArray[i] = 0;
        }

        Weights memory weights;

        uint256[] memory _allUnderlyingPrices = getAllTokenPrices();

        uint256[] memory _currentBPTPrices = calculateAllPoolPrices(_allUnderlyingPrices);

        (
            weights._idealWeights,
            weights._currentWeights,
            weights._hypotheticalWeights,
            weights._nav,
            weights._totalPortfolioValue
        ) = calculateAllWeights(_currentBPTPrices, _BPTokensOut, _zeroArray, _amountsOut);

        bool _launch =
            safeToRedeem(
                _BPTokensOut,
                weights._hypotheticalWeights,
                weights._idealWeights,
                weights._currentWeights
            );



        if (!_launch) {
            string memory errorMessage = "This combination of tokens would move gyroscope weights too far from target.";
            return (false, errorMessage);
        }

        uint256 _dollarValueOut = 0;

        for (uint256 i = 0; i < _BPTokensOut.length; i++) {
            _dollarValueOut = _dollarValueOut.add(_amountsOut[i].scaledMul(_currentBPTPrices[i]));
        }

        FlowLogger memory flowLogger;
        (
            flowLogger._inflowHistory,
            flowLogger._outflowHistory,
            flowLogger._currentBlock,
            flowLogger._lastSeenBlock
        ) = initializeFlowLogger();

        uint256 _gyroRedeemed = gyroPriceOracle.getAmountToRedeem(
            _dollarValueOut,
            flowLogger._outflowHistory,
            weights._nav
        );

        if (_gyroRedeemed > _maxGyroRedeemed) {
            string memory errorMessage = "Too much slippage is expected";
            return (false, errorMessage);
        } else {
            string memory happyMessage = "Minting checks pass.";
            return (true, happyMessage);
        }
        }

    function estimateMint(address[] memory _BPTokensIn, uint256[] memory _amountsIn)
        public
        view
        override
        returns (uint256)
    {
        //Filter 1: Require that the tokens are supported and in correct order
        bool _orderCorrect = checkBPTokenOrder(_BPTokensIn);
        require(_orderCorrect, "Input tokens in wrong order or contains invalid tokens");

        FlowLogger memory flowLogger;
        (
            flowLogger._inflowHistory,
            flowLogger._outflowHistory,
            flowLogger._currentBlock,
            flowLogger._lastSeenBlock
        ) = initializeFlowLogger();

        uint256[] memory _allUnderlyingPrices = getAllTokenPrices();

        uint256[] memory _currentBPTPrices = calculateAllPoolPrices(_allUnderlyingPrices);

        uint256[] memory _zeroArray = new uint256[](_BPTokensIn.length);
        for (uint256 i = 0; i < _BPTokensIn.length; i++) {
            _zeroArray[i] = 0;
        }

        Weights memory weights;
        (
            weights._idealWeights,
            weights._currentWeights,
            weights._hypotheticalWeights,
            weights._nav,
            weights._totalPortfolioValue
        ) = calculateAllWeights(_currentBPTPrices, _BPTokensIn, _amountsIn, _zeroArray);

        uint256 _dollarValueIn = 0;
        for (uint256 i = 0; i < _BPTokensIn.length; i++) {
            _dollarValueIn = _dollarValueIn.add(_amountsIn[i].scaledMul(_currentBPTPrices[i]));
        }

        return
            gyroPriceOracle.getAmountToMint(
                _dollarValueIn,
                flowLogger._inflowHistory,
                weights._nav
            );
    }

    function estimateRedeem(address[] memory _BPTokensOut, uint256[] memory _amountsOut)
        public
        view
        override
        returns (uint256)
    {
        //Filter 1: Require that the tokens are supported and in correct order
        bool _orderCorrect = checkBPTokenOrder(_BPTokensOut);
        require(_orderCorrect, "Input tokens in wrong order or contains invalid tokens");

        FlowLogger memory flowLogger;
        (
            flowLogger._inflowHistory,
            flowLogger._outflowHistory,
            flowLogger._currentBlock,
            flowLogger._lastSeenBlock
        ) = initializeFlowLogger();

        uint256[] memory _allUnderlyingPrices = getAllTokenPrices();

        uint256[] memory _currentBPTPrices = calculateAllPoolPrices(_allUnderlyingPrices);

        uint256[] memory _zeroArray = new uint256[](_BPTokensOut.length);
        for (uint256 i = 0; i < _BPTokensOut.length; i++) {
            _zeroArray[i] = 0;
        }

        Weights memory weights;
        (
            weights._idealWeights,
            weights._currentWeights,
            weights._hypotheticalWeights,
            weights._nav,
            weights._totalPortfolioValue
        ) = calculateAllWeights(_currentBPTPrices, _BPTokensOut, _amountsOut, _zeroArray);

        uint256 _dollarValueOut = 0;
        for (uint256 i = 0; i < _BPTokensOut.length; i++) {
            _dollarValueOut = _dollarValueOut.add(_amountsOut[i].scaledMul(_currentBPTPrices[i]));
        }

        return
            gyroPriceOracle.getAmountToRedeem(
                _dollarValueOut,
                flowLogger._outflowHistory,
                weights._nav
            );
    }

    function redeem(
        address[] memory _BPTokensOut,
        uint256[] memory _amountsOut,
        uint256 _maxGyroRedeemed
    ) public override returns (uint256 _gyroRedeemed) {
        require(
            _BPTokensOut.length == _amountsOut.length,
            "tokensIn and valuesIn should have the same number of elements"
        );

        //Filter 1: Require that the tokens are supported and in correct order
        require(
            checkBPTokenOrder(_BPTokensOut),
            "Input tokens in wrong order or contains invalid tokens"
        );

        uint256[] memory _zeroArray = new uint256[](_BPTokensOut.length);
        for (uint256 i = 0; i < _BPTokensOut.length; i++) {
            _zeroArray[i] = 0;
        }

        Weights memory weights;

        uint256[] memory _allUnderlyingPrices = getAllTokenPrices();

        uint256[] memory _currentBPTPrices = calculateAllPoolPrices(_allUnderlyingPrices);

        (
            weights._idealWeights,
            weights._currentWeights,
            weights._hypotheticalWeights,
            weights._nav,
            weights._totalPortfolioValue
        ) = calculateAllWeights(_currentBPTPrices, _BPTokensOut, _zeroArray, _amountsOut);

        bool _launch =
            safeToRedeem(
                _BPTokensOut,
                weights._hypotheticalWeights,
                weights._idealWeights,
                weights._currentWeights
            );

        if (!_launch) {
            revert("Too windy for launch.");
        }

        uint256 _dollarValueOut = 0;

        for (uint256 i = 0; i < _BPTokensOut.length; i++) {
            _dollarValueOut = _dollarValueOut.add(_amountsOut[i].scaledMul(_currentBPTPrices[i]));
        }

        FlowLogger memory flowLogger;
        (
            flowLogger._inflowHistory,
            flowLogger._outflowHistory,
            flowLogger._currentBlock,
            flowLogger._lastSeenBlock
        ) = initializeFlowLogger();

        _gyroRedeemed = gyroPriceOracle.getAmountToRedeem(
            _dollarValueOut,
            flowLogger._outflowHistory,
            weights._nav
        );

        require(_gyroRedeemed <= _maxGyroRedeemed, "too much slippage");

        _burn(msg.sender, _gyroRedeemed);

        gyroRouter.withdraw(_BPTokensOut, _amountsOut);

        for (uint256 i = 0; i < _amountsOut.length; i++) {
            bool success =
                IERC20(_BPTokensOut[i]).transferFrom(address(this), msg.sender, _amountsOut[i]);
            require(success, "failed to transfer tokens");
        }

        // emit Redeem(msg.sender, _gyroRedeemed);
        finalizeFlowLogger(
            flowLogger._inflowHistory,
            flowLogger._outflowHistory,
            0,
            _gyroRedeemed,
            flowLogger._currentBlock,
            flowLogger._lastSeenBlock
        );
        return _gyroRedeemed;
    }

    function initializeFlowLogger()
        public
        view
        returns (
            uint256 _inflowHistory,
            uint256 _outflowHistory,
            uint256 _currentBlock,
            uint256 _lastSeenBlock
        )
    {
        _lastSeenBlock = lastSeenBlock;
        _currentBlock = block.number;
        _inflowHistory = inflowHistory;
        _outflowHistory = outflowHistory;

        uint256 _memoryParam = memoryParam;

        if (_lastSeenBlock < _currentBlock) {
            _inflowHistory = _inflowHistory.scaledMul(
                _memoryParam**(_currentBlock.sub(_lastSeenBlock))
            );
            _outflowHistory = _outflowHistory.scaledMul(
                _memoryParam**(_currentBlock.sub(_lastSeenBlock))
            );
        }

        return (_inflowHistory, _outflowHistory, _currentBlock, _lastSeenBlock);
    }

    function finalizeFlowLogger(
        uint256 _inflowHistory,
        uint256 _outflowHistory,
        uint256 _gyroMinted,
        uint256 _gyroRedeemed,
        uint256 _currentBlock,
        uint256 _lastSeenBlock
    ) public {
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
}
