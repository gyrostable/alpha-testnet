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

    mapping(address => address) _tokenAddressToOracleAddress;
    mapping(address => string) _tokenAddressToSymbol;
    mapping(address => bool) _checkPoolIsValid;

    address[] underlyingTokens;
    int128[] _originalBPTPrices;

    constructor(address[] _gyroPoolAddresses, address _priceOracleAddress, address _routerAddress, address[] _underlyingTokens, address[] _underlyingTokenOracleAddresses, string[] _underlyingTokenSymbols)
        ERC20("Gyro Stable Coin", "GYRO")
    {
        gyroPriceOracle = GyroPriceOracle(_priceOracleAddress);
        gyroRouter = GyroRouter(_routerAddress);

        underlyingTokens = _underlyingTokens;

        for (uint256 i = 0; i < _gyroPoolAddresses.length; i++) {
            _checkPoolIsValid[_gyroPoolAddresses[i]] = true;
        }

        struct poolProperties {
            address[] poolAddresses = ['0x..', '0x..'];
            uint256[] initialPoolWeights = [1, 1];
            int128[] initialPoolPrices;
        }

        for (uint256 i = 0; i < _underlyingTokens.length; i++) {
            _tokenAddressToOracleAddress[_underlyingTokens[i]] = _underlyingTokenOracleAddresses[i];
            _tokenAddressToSymbol[_underlyingTokens[i]] = _underlyingTokenSymbols[i];
        }

        
        for (uint256 i = 0; i < poolProperties.poolAddresses.length; i++) {
            _underlyingPrices
            _originalBPTPrices[i] = gyroPriceOracle();
             
        }

        uint256[] constant initialPoolWeights = 


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
        int128[] _underlyingPrices;

    for (uint256 i = 0; i < underlyingTokens.length; i++) {
        _underlyingPrices[i] = getPrice(underlyingTokens[i], _tokenAddressToSymbol[underlyingTokens[i]]);
    }
    }

    function calculateImpliedPoolWeights(address[] BPTAddresses, uint256[] _BPTPrices) public returns (uint256[]) {};


    function getPrice(address _token, string _tokenSymbol) external returns (int128) {
        return priceOracle(_tokenAddressToOracleAddress[token]).getPrice(_token, _tokenSymbol).fromUInt();
    }

    function registerToken(address token, address oracleAddress) external {
        tokens[token] = oracleAddress;
    }
    //

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

        //Filter 2: For each of the BPT tokens, make sure the stablecoin is OK
    

        //Filter 3: For the proposed bpt token deposit, make sure the result would be within 5% of the new implied portfolio weights. If not, revert
        if (_BPTokenAddresses.length == _gyroPoolAddresses.length) {
            //Check that the portfolio weights are maintained
            //1. check stablecoin in pool




        }
        else {

        }



        };




        address[] _gyroPoolAddresses = getPoolAddresses();


    //1. Check length of BPTTokenAddresses.
    //2. If length == total number of pools:
        //Check that the assets are in proportion with the portfolio
        //if they are, allow user to directly deposit into fund and return minted gyros
    //3. If length <total number of pools:
        //a. Check the stablecoins are clean
        //for each bpttoken determine what the stablecoin is
        //get oracle price for that stablecoin
        //Check that the stablecoin is ok relative to the USD
        //if not, return false

    //a2. get remaining prices if previous checks pass

    //b Check that the resultant weights of all the bpt tokens to be added would not put any pool out of the x% boundary
    //if all tokens pass, then add the bpt tokens to the buffer fund and mint gyro
    //else, return false

    {
        BPool _bPool = BPool(_bPoolAddress);
        address[] _bpoolTokens = _bPool.getFinalTokens();
    }


        //1. USDC price - assume is 1 USD
        //2. Get ETH and DAI prices from uniswap to the USDC pair
        //3. Use the Maker Oracle for the Bal price / if complex, make own twap

        // this will ensure that the deposited amount does not break the
        // slack assumptions and revert otherwise
        // after this call, the balance of BPT of this contract will have increased

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