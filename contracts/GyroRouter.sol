//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "./GyroFund.sol";
import "./Ownable.sol";
import "./abdk/ABDKMath64x64.sol";


interface GyroRouter
    function deposit(address[] memory _tokensIn, uint256[] memory _amountsIn) external returns(bool);

    function checkAssetSafety(address memory _tokenIn) external returns {
        //1. Check the price
        //2. Check the volume

    };

    function checkPortfolioWeights(address memory _tokenIn, uint256 memory _amountIn) external returns(bool);



    function withdraw(address[] memory _tokensOut, uint256[] memory _amountsOut) external;
}


contract GyroRouter is Ownable {
    using ExtendedMath for int128;
    using ABDKMath64x64 for uint256;
    using ABDKMath64x64 for int128;

    GyroFundAddress = '0x..';
    ERC20Interface GyroFund = ERC20Interface(GyroFundAddress);

    function checkPortFolioWeights(address memory _tokenIn, uint256 memory _amountIn) external returns(bool) {
        //1. Get state of pools
        //2. Compute the new weight with the tokens added in
        //3. If the weight is ok, return true
        //4. If the weight is not ok, return false

    address[] memory _poolList = GyroFund.getPoolAddresses();
    uint256[] memory _poolWeights = GyroFund.getPoolWeights();
    



    for (uint256 i = 0; i < _poolList.length; i++) {
        
        


    };



    function withdraw(address[] memory _tokensOut, uint256[] memory _amountsOut)
        external
        returns (address[] memory, uint256[] memory);
}
    
    UniswapAnchoredView private daiuniswapanchor;
    UniswapAnchoredView private wethuniswapanchor;
    ERC20 private dai;
    ERC20 private weth;

    int128 daiSafetyPrice = 0.9;
    int128 usdcSafetyPrice = 0.95;

    constructor(
        address _daiUniswapAnchorAddress
        address _wethUniswapAnchorAddress
    )
    public
    Ownable()
    {
        daiuniswapanchor = UniswapAnchoredView(_daiUniswapAnchorAddress);
        daiuniswapanchor = UniswapAnchoredView(_wethUniswapAnchorAddress);
    }
    
    function checkAssetSafety(address memory _poolTokenIn) external returns(bool) {
        //1. Given a pool token, find the tokens in the pool

        
        daiuniswapanchor.price("DAI")
        //1. Check the price
        //2. Check the volume

    };


    function deposit (address[] memory _BPTokenAddresses, uint256[] memory _BPTAmounts) external returns(bool) {
        address[] _gyroPoolAddresses = GyroFund.getPoolAddresses();

        if (_BPTokenAddresses.length == _gyroPoolAddresses.length) {
            //1. check stablecoin in pool


        }
        else {

        }



    };
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
}
