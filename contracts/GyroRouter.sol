//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

interface GyroRouter 
    function deposit(address[] memory _tokensIn, uint256[] memory _amountsIn) external returns {

    };

    function checkAssetSafety(address memory _tokenIn) external returns {
        //1. Check the price
        //2. Check the volume

    };

    function checkPortfolioWeights(address memory _tokenIn, uint256 memory _amountIn) external returns(bool) {
        //1. Get state of pools
        //2. Compute the new weight with the tokens added in
        //3. If the weight is ok, return true
        //4. If the weight is not ok, return false

    };



    function withdraw(address[] memory _tokensOut, uint256[] memory _amountsOut)
        external
        returns (address[] memory, uint256[] memory);
}
