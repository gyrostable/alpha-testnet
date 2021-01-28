//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "./Exponential.sol";
import "./compound/CTokenInterfaces.sol";
import "./compound/ComptrollerInterface.sol";

contract CompoundCore is Exponential {
    CTokenInterface private cdai;
    ComptrollerInterface private comptroller;

    constructor(address cdaiAddress, address comptrollerAddress) {
        cdai = CTokenInterface(cdaiAddress);
        comptroller = ComptrollerInterface(comptrollerAddress);
    }

    /**
     * Gets the collateral factor from Compound for cDai
     * Given an input amount of vdai, return the corresponding cdai
     * @return result in interval [0,1]
     */
    function getCdaiCollateralFactor() public view returns (uint256 result) {
        (bool listed, uint256 collateralFactor) = comptroller.markets(
            address(cdai)
        );
        require(listed, "cdai market is not listed");
        return collateralFactor;
    }

    function computeBorrowRatio(address account) internal view returns (uint256) {
        (
            uint256 _oErr,
            uint256 _cdaiHeld, // units of cdai
            uint256 _daiOwed, // units of dai
            uint256 _exchangeRate
        ) = cdai.getAccountSnapshot(account);
        uint256 _collateralFactor = getCdaiCollateralFactor();
        require(_oErr == 0, "computeBorrowRatio: getAccountSnapshot failed");
        return computeBorrowRatio(_cdaiHeld, _daiOwed, _exchangeRate, _collateralFactor);
    }

    /**
     * Computes the collateral ratio of the keeper
     * This function already takes into account the collateral factor
     * given collateral factor = 0.75, supplied = 100 and borrowed = 75
     * the result will be 1
     * @param _cdaiHeld amount of tokens held, in cToken
     * @param _daiOwed amount of tokens owed, in underlying currency
     * @param _daiCdaiExchangeRate is the exchange rate from the underlying to the cToken, dai -> cDai
     * @param _collateralFactor collateral factor from cToken to underlying between 0 and 1
     * @return the borrow ratio from 0 to 1, with 1 meaning we cannot borrow more without getting liquidated
     */
    function computeBorrowRatio(
        uint256 _cdaiHeld,
        uint256 _daiOwed,
        uint256 _daiCdaiExchangeRate,
        uint256 _collateralFactor
    ) internal pure returns (uint256) {
        // floor(floor(daiOwed * exchangeRate) / floor(cdaiHeld * collateralFactor))
        return
            mustDivExp(
                mustMulExp(_daiOwed, _daiCdaiExchangeRate), // convert dai to cdai
                mustMulExp(_cdaiHeld, _collateralFactor) // take the collateral factor into account
            );
    }
}
