// SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./GyroPriceOracle.sol";
import "./GyroRouter.sol";
import "./Ownable.sol";

interface GyroFund is IERC20 {
    event Mint(address minter, uint256 amount);
    event Redeem(address redeemer, uint256 amount);

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
}

contract GyroFundV1 is GyroFund, Ownable, ERC20 {
    GyroPriceOracle gyroPriceOracle;
    GyroRouter gyroRouter;

    constructor(address _priceOracleAddress, address _routerAddress)
        ERC20("Gyro Stable Coin", "GYRO")
    {
        gyroPriceOracle = GyroPriceOracle(_priceOracleAddress);
        gyroRouter = GyroRouter(_routerAddress);
    }

    /**
     * [Check the inputted vault tokens are in the right proportions, if not, adjust, then mint.]
     *
     **/
    function mint(
        address[] memory _tokensIn,
        uint256[] memory _amountsIn,
        uint256 _minGyroMinted
    ) public override returns (uint256) {
        require(
            _tokensIn.length == _amountsIn.length,
            "tokensIn and valuesIn should have the same number of elements"
        );

        for (uint256 i = 0; i < _tokensIn.length; i++) {
            bool success =
                IERC20(_tokensIn[i]).transferFrom(msg.sender, address(this), _amountsIn[i]);
            require(success, "failed to transfer tokens, check allowance");
        }

        // this will ensure that the deposited amount does not break the
        // slack assumptions and revert otherwise
        // after this call, the balance of BPT of this contract will have increased
        gyroRouter.deposit(_tokensIn, _amountsIn);

        uint256 _amountToMint = gyroPriceOracle.getAmountToMint(_tokensIn, _amountsIn);

        require(_amountToMint >= _minGyroMinted, "too much slippage");

        _mint(msg.sender, _amountToMint);

        emit Mint(msg.sender, _amountToMint);

        return _amountToMint;
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

        emit Redeem(msg.sender, _gyroAmountBurned);

        return amountsOut;
    }
}
