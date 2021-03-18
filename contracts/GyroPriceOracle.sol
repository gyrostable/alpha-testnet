//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;


import "./balancer/BPool.sol";
import "./abdk/ABDKMath64x64.sol";
import "./compound/UniswapAnchoredView.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./ExtendedMath.sol";

/** 
* PriceOracle is the interface for asset price oracles
* Currently used with a proxy for the Compound oracle on testnet
*/
interface PriceOracle {
    function getPrice(string memory tokenSymbol) external view returns (uint256);
}


/** 
* GyroPriceOracle is the P-AMM implementation described here: 
* https://docs.gyro.finance/learn/gyro-amms/p-amm
* The testnet implementation (GyroPriceOracleV1) simplifications are detailed here: 
* https://docs.gyro.finance/testnet-alpha/gyroscope-amm
*/
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

    /**
    * Calculates the offer price to mint a new Gyro Dollar in the P-AMM.
    * @param _dollarValueIn = dollar value of user-provided input assets
    * @param _inflowHistory = current state of Gyroscope inflow history
    * @param _nav = current reserve value per Gyro Dollar
    * Returns the amount of GYD that the protocol will offer to mint in return
    * for the input assets.
     */
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
            uint256 _scaling = _eps.scaledMul(_inflowHistory);
            if (_scaling >= _one) {
                _gyroAmount = 0;
            } else {
                _gyroAmount = _dollarValueIn.scaledMul(_one.sub(_scaling));
            }
        }
        _gyroAmount = _dollarValueIn;
        return _gyroAmount;
    }

    /**
    * Calculates the offer price to redeem a Gyro Dollar in the P-AMM.
    * @param _dollarValueOut = dollar-value of user-requested outputs, to redeem from reserve
    * @param _outflowHistory = current state of Gyroscope outflow history
    * @param _nav = current reserve value per Gyro Dollar
    * Returns the amount of GYD the protocol will ask to redeem to fulfill the requested asset outputs
     */
    function getAmountToRedeem(
        uint256 _dollarValueOut,
        uint256 _outflowHistory,
        uint256 _nav
    ) external pure override returns (uint256 _gyroAmount) {
        if (_nav < 1e18) {
            // gyroAmount = dollarValueOut * (1 + eps*outflowHistory)
            uint256 _eps = 1e11;
            uint256 _scaling = _eps.scaledMul(_outflowHistory).add(1e18);
            _gyroAmount = _dollarValueOut.scaledMul(_scaling);
        } else {
            _gyroAmount = _dollarValueOut;
        }

        return _gyroAmount;
    }

    /**
    * Calculates the value of Balancer pool tokens using the logic described here:
    * https://docs.gyro.finance/learn/oracles/bpt-oracle
    * This is robust to price manipulations within the Balancer pool.
    * @param _bPoolAddress = address of Balancer pool
    * @param _underlyingPrices = array of prices for underlying assets in the pool, in the same
    * order as _bPool.getFinalTokens() will return
     */
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

        uint256 result = _k.scaledMul(_weightedProd).scaledDiv(_bptSupply);
        // console.log("final _weightedProd", _weightedProd, "supply", _bptSupply);
        // console.log("final _k", _k, "result", result);
        return result;
    }
}

/**
* Proxy contract for Compound asset price oracle, used in testnet implementation
 */
contract CompoundPriceWrapper is PriceOracle {
    using SafeMath for uint256;

    uint256 public constant oraclePriceScale = 1000000;
    address public compoundOracle;

    constructor(address _compoundOracle) {
        compoundOracle = _compoundOracle;
    }

    function getPrice(string memory tokenSymbol) public view override returns (uint256) {
        bytes32 symbolHash = keccak256(bytes(tokenSymbol));
        // Compound oracle uses "ETH", so change "WETH" to "ETH"
        if (symbolHash == keccak256(bytes("WETH"))) {
            tokenSymbol = "ETH";
        }

        if (symbolHash == keccak256(bytes("sUSD")) || symbolHash == keccak256(bytes("BUSD"))) {
            tokenSymbol = "DAI";
        }
        UniswapAnchoredView oracle = UniswapAnchoredView(compoundOracle);
        uint256 unscaledPrice = oracle.price(tokenSymbol);
        TokenConfig memory tokenConfig = oracle.getTokenConfigBySymbol(tokenSymbol);
        return unscaledPrice.mul(tokenConfig.baseUnit).div(oraclePriceScale);
    }
}

contract DummyPriceWrapper is PriceOracle {
    function getPrice(string memory tokenSymbol) public pure override returns (uint256) {
        bytes32 symbolHash = keccak256(bytes(tokenSymbol));
        if (symbolHash == keccak256(bytes("DAI"))) {
            return 1e18;
        } else if (symbolHash == keccak256(bytes("BUSD"))) {
            return 1e18;
        } else if (symbolHash == keccak256(bytes("sUSD"))) {
            return 1e18;
        } else if (symbolHash == keccak256(bytes("USDC"))) {
            return 1e6;
        } else if (symbolHash == keccak256(bytes("WETH"))) {
            return 2000e18;
        } else {
            revert("symbol not supported");
        }
    }
}
