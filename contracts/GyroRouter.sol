//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "./GyroFund.sol";
import "./Ownable.sol";
import "./abdk/ABDKMath64x64.sol";


interface GyroRouter
    function deposit(address[] memory _tokensIn, uint256[] memory _amountsIn) external returns(bool);


    function withdraw(address[] memory _tokensOut, uint256[] memory _amountsOut) external;
}


contract GyroRouter is Ownable {
    using ExtendedMath for int128;
    using ABDKMath64x64 for uint256;
    using ABDKMath64x64 for int128;

    function checkPortFolioWeights(address memory _tokenIn, uint256 memory _amountIn) external returns(bool) {
        //1. Get state of pools
        //2. Compute the new weight with the tokens added in
        //3. If the weight is ok, return true
        //4. If the weight is not ok, return false

    address[] memory _poolList = GyroFund.getPoolAddresses();
    uint256[] memory _poolWeights = GyroFund.getPoolWeights();

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




}
