//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "hardhat/console.sol";
import "./balancer/BPool.sol";
import "./abdk/ABDKMath64x64.sol";
import "./compound/UniswapAnchoredView.sol";

import "./ExtendedMath.sol";

interface PriceOracle {
    function getPrice(address token, bytes32 tokenSymbol) external returns (uint256);
}

interface GyroPriceOracle {
    function getAmountToMint(address[] memory _tokensIn, uint256[] memory _amountsIn)
        external
        view
        returns (uint256);

    function getAmountToRedeem(uint256 _dollarValueOut)
        external
        view
        returns (uint256 _gyroAmount);

    function getBPTPrice(address _bPoolAddress, uint256[] memory _underlyingPrices)
        external
        view
        returns (uint64 _bptPrice);
}

contract DummyGyroPriceOracle is GyroPriceOracle {
    using ExtendedMath for int128;
    using ABDKMath64x64 for uint256;
    using ABDKMath64x64 for int128;

    function getAmountToMint(address[] memory _tokensIn, uint256[] memory _amountsIn)
        external
        pure
        override
        returns (uint256)
    {
        uint256 result = 0;
        for (uint256 i = 0; i < _tokensIn.length; i++) {
            result += _amountsIn[i];
        }
        return result;
    }

    function getAmountToRedeem(uint256 _dollarValueOut)
        external
        pure
        override
        returns (uint256 _gyroAmount)
    {
        _gyroAmount = _dollarValueOut;
        return _gyroAmount;
    }

    function getBPTPrice(address _bPoolAddress, uint256[] memory _underlyingPrices)
        public
        view
        override
        returns (uint64 _bptPrice)
    {
        /* calculations:
            bptSupply = # of BPT tokens
            bPoolWeights = array of pool weights (require _underlyingPrices comes in same order)
            k = constant = product of reserves^weight
            bptPrice = (k * product of (p_i / w_i)^w_i ) / bptSupply

            functions from ABDKMath64x64 library
            -- exp_2 = binary exponent
            -- log_2 = binary logarithm
            -- mul = calculate x*y

            x^y = 2^(y log_2 x)
            exp_2( mul(y, log_2(x)) )
        */
        BPool _bPool = BPool(_bPoolAddress);
        uint256 _bptSupply = _bPool.totalSupply();
        address[] memory _tokens = _bPool.getFinalTokens();

        int128 _k = uint256(1).fromUInt(); // check that these are the right to get value 1
        int128 _weightedProd = uint256(1).fromUInt();

        for (uint256 i = 0; i < _tokens.length; i++) {
            int128 _weight = _bPool.getNormalizedWeight(_tokens[i]).fromUInt();
            int128 _price = _underlyingPrices[i].fromUInt();
            int128 _tokenBalance = _bPool.getBalance(_tokens[i]).fromUInt();
            _k = _k.mul(_tokenBalance.powf(_weight));
            _weightedProd = _weightedProd.mul(_price.div(_weight).powf(_weight));
        }

        return _k.mul(_weightedProd).div(_bptSupply.fromUInt()).toUInt();
    }
}

abstract contract CompoundPriceWrapper is PriceOracle {
    address compoundOracle;
    UniswapAnchoredView private uniswapanchor;

    constructor(address _compoundOracle) {
        compoundOracle = _compoundOracle;
    }

    function getPrice(string memory tokenSymbol) public returns (uint256) {
        uniswapanchor = UniswapAnchoredView(compoundOracle);
        return uniswapanchor.price(tokenSymbol);
    }
}

// contract MakerPriceWrapper is PriceOracle {
//     address makerOracle;

//     constructor(address _makerOracle) {
//         makerOracle = _makerOracle;
//     }

//     // function getPrice(address token, string tokenSymbol) external returns (uint256) {
//     //     return UniswapPriceOracle(makerOracle).getPriceOtherName(token);
//     // }
// }
