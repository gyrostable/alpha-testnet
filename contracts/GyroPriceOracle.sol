//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "hardhat/console.sol";
import "./balancer/BPool.sol";
import "./abdk/ABDKMath64x64.sol";
import "./compound/UniswapAnchoredView.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./ExtendedMath.sol";

interface PriceOracle {
    function getPrice(string memory tokenSymbol) external view returns (uint256);
}

interface GyroPriceOracle {
    function getAmountToMint(
        uint256 _dollarValueIn,
        uint256 _inflowHistory,
        uint256 _nav
    ) external view returns (uint256);

    function getAmountToRedeem(
        uint256 _dollarValueOut,
        uint256 _outflowHistory,
        uint256 _nav
    ) external view returns (uint256 _gyroAmount);

    function getBPTPrice(address _bPoolAddress, uint256[] memory _underlyingPrices)
        external
        view
        returns (uint256 _bptPrice);
}

contract GyroPriceOracleV1 is GyroPriceOracle {
    using ExtendedMath for int128;
    using ExtendedMath for uint256;
    using ABDKMath64x64 for uint256;
    using ABDKMath64x64 for int128;
    using SafeMath for uint256;

    uint256 constant bpoolDecimals = 18;

    function getAmountToMint(
        uint256 _dollarValueIn,
        uint256 _inflowHistory,
        uint256 _nav
    ) external pure override returns (uint256 _gyroAmount) {
        uint256 _one = 1e18;
        if (_nav < _one) {
            _gyroAmount = _dollarValueIn;
        } else {
            // gyroAmount = dollarValueIn * (1 - eps_inflowHistory) or min of 0
            uint256 _eps = 1e11;
            uint256 _scaling = _eps.mul(_inflowHistory);
            if (_scaling >= _one) {
                _gyroAmount = 0;
            } else {
                _gyroAmount = _dollarValueIn.mul(_one.sub(_scaling));
            }
        }
        _gyroAmount = _dollarValueIn;
        return _gyroAmount;
    }

    function getAmountToRedeem(
        uint256 _dollarValueOut,
        uint256 _outflowHistory,
        uint256 _nav
    ) external pure override returns (uint256 _gyroAmount) {
        if (_nav < 1e18) {
            // gyroAmount = dollarValueOut * (1 + eps*outflowHistory)
            uint256 _eps = 1e11;
            uint256 _scaling = _eps.mul(_outflowHistory).add(1e18);
            _gyroAmount = _dollarValueOut.mul(_scaling);
        } else {
            _gyroAmount = _dollarValueOut;
        }

        return _gyroAmount;
    }

    function getBPTPrice(address _bPoolAddress, uint256[] memory _underlyingPrices)
        public
        view
        override
        returns (uint256 _bptPrice)
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

        uint256 _k = uint256(1e18); // check that these are the right to get value 1
        uint256 _weightedProd = uint256(1e18);

        for (uint256 i = 0; i < _tokens.length; i++) {
            uint256 _weight = _bPool.getNormalizedWeight(_tokens[i]);
            uint256 _price = _underlyingPrices[i];
            uint256 _tokenBalance = _bPool.getBalance(_tokens[i]);
            uint256 _decimals = ERC20(_tokens[i]).decimals();
            // _k = _k * _tokenBalance ** _weight
            // console.log("balance", _tokenBalance, "weight", _weight, "decimal", _decimals);

            if (_decimals < bpoolDecimals) {
                _tokenBalance = _tokenBalance.mul(10**(bpoolDecimals - _decimals));
                _price = _price.mul(10**(bpoolDecimals - _decimals));
            }

            // console.log("balance", _tokenBalance, "weight", _weight);
            // console.log("decimal", _decimals, "price", _price);

            _k = _k.mulPow(_tokenBalance, _weight, bpoolDecimals);

            // _weightedProd = _weightedProd * (_price / _weight) ** _weight;
            _weightedProd = _weightedProd.mulPow(
                _price.scaledDiv(_weight, bpoolDecimals),
                _weight,
                bpoolDecimals
            );
            // console.log("_k", _k, "_weightedProd", _weightedProd);
        }

        uint256 result = _k.mul(_weightedProd).div(_bptSupply);
        // console.log("final _weightedProd", _weightedProd, "supply", _bptSupply);
        console.log("final _k", _k, "result", result);
        return result;
    }
}

contract CompoundPriceWrapper is PriceOracle {
    address compoundOracle;

    constructor(address _compoundOracle) {
        compoundOracle = _compoundOracle;
    }

    function getPrice(string memory tokenSymbol) public view override returns (uint256) {
        return UniswapAnchoredView(compoundOracle).price(tokenSymbol);
    }
}

contract DummyPriceWrapper is PriceOracle {
    function getPrice(string memory tokenSymbol) public pure override returns (uint256) {
        if (keccak256(bytes(tokenSymbol)) == keccak256(bytes("DAI"))) {
            return 1e18;
        } else if (keccak256(bytes(tokenSymbol)) == keccak256(bytes("USDC"))) {
            return 1e6;
        } else if (keccak256(bytes(tokenSymbol)) == keccak256(bytes("WETH"))) {
            return 1350e18;
        } else {
            revert("symbol not supported");
        }
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
