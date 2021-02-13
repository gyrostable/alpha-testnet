// SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "./BalancerGyroRouter.sol";
import "./GyroFund.sol";

contract GyroLib {
    GyroFundV1 fund;
    BalancerExternalTokenRouter externalTokensRouter;

    constructor(address gyroFundAddress, address externalTokensRouterAddress) {
        fund = GyroFundV1(gyroFundAddress);
        externalTokensRouter = BalancerExternalTokenRouter(externalTokensRouterAddress);
    }

    function mintFromUnderlyingTokens(
        address[] memory _tokensIn,
        uint256[] memory _amountsIn,
        uint256 _minAmountOut
    ) public returns (uint256) {
        for (uint256 i = 0; i < _tokensIn.length; i++) {
            bool success =
                IERC20(_tokensIn[i]).transferFrom(msg.sender, address(this), _amountsIn[i]);
            require(success, "failed to transfer tokens from GyroFund to GryoRouter");
            IERC20(_tokensIn[i]).approve(address(externalTokensRouter), _amountsIn[i]);
        }
        (address[] memory bptTokens, uint256[] memory amounts) =
            externalTokensRouter.deposit(_tokensIn, _amountsIn);

        (address[] memory sortedAddresses, uint256[] memory sortedAmounts) =
            sortBPTokenstoPools(bptTokens, amounts);

        for (uint256 i = 0; i < sortedAddresses.length; i++) {
            IERC20(sortedAddresses[i]).approve(address(fund), sortedAmounts[i]);
        }
        uint256 minted = fund.mint(sortedAddresses, sortedAmounts, _minAmountOut);
        require(fund.transfer(msg.sender, minted), "failed to send back gyro");
        return minted;
    }

    function redeemToUnderlyingTokens(
        address[] memory _tokensOut,
        uint256[] memory _amountsOut,
        uint256 _maxRedeemed
    ) public returns (uint256) {
        (address[] memory _BPTokensIn, uint256[] memory _BPAmountsIn) =
            externalTokensRouter.estimateWithdraw(_tokensOut, _amountsOut);

        (address[] memory _sortedAddresses, uint256[] memory _sortedAmounts) =
            sortBPTokenstoPools(_BPTokensIn, _BPAmountsIn);

        (uint256 errorCode, uint256 _amountToRedeem) =
            fund.redeemChecksPass(_sortedAddresses, _sortedAmounts, _maxRedeemed);

        require(errorCode == 0, fund.errorCodeToString(errorCode));
        require(_amountToRedeem <= _maxRedeemed, "too much slippage");

        require(
            fund.transferFrom(msg.sender, address(this), _amountToRedeem),
            "failed to send gyro to lib"
        );

        uint256 _amountRedeemed = fund.redeem(_sortedAddresses, _sortedAmounts, _maxRedeemed);

        for (uint256 i = 0; i < _sortedAddresses.length; i++) {
            require(
                IERC20(_sortedAddresses[i]).approve(
                    address(externalTokensRouter),
                    _sortedAmounts[i]
                ),
                "failed to approve BPTokens"
            );
        }

        externalTokensRouter.withdraw(_tokensOut, _amountsOut);

        for (uint256 i = 0; i < _tokensOut.length; i++) {
            IERC20(_tokensOut[i]).transfer(msg.sender, _amountsOut[i]);
        }

        return _amountRedeemed;
    }

    function estimateMintedGyro(address[] memory _tokensIn, uint256[] memory _amountsIn)
        public
        view
        returns (uint256)
    {
        (address[] memory bptTokens, uint256[] memory amounts) =
            externalTokensRouter.estimateDeposit(_tokensIn, _amountsIn);

        (address[] memory _sortedAddresses, uint256[] memory _sortedAmounts) =
            sortBPTokenstoPools(bptTokens, amounts);

        (, uint256 _amountToMint) = fund.mintChecksPass(_sortedAddresses, _sortedAmounts, 10);

        return _amountToMint;
    }

    function wouldMintChecksPass(
        address[] memory _tokensIn,
        uint256[] memory _amountsIn,
        uint256 _minGyroMinted
    ) public view returns (uint256) {
        (address[] memory bptTokens, uint256[] memory amounts) =
            externalTokensRouter.estimateDeposit(_tokensIn, _amountsIn);

        (address[] memory sortedAddresses, uint256[] memory sortedAmounts) =
            sortBPTokenstoPools(bptTokens, amounts);

        (uint256 errorCode, ) = fund.mintChecksPass(sortedAddresses, sortedAmounts, _minGyroMinted);

        return errorCode;
    }

    function wouldRedeemChecksPass(
        address[] memory _tokensOut,
        uint256[] memory _amountsOut,
        uint256 _maxGyroRedeemed
    ) public view returns (uint256) {
        (address[] memory bptTokens, uint256[] memory amounts) =
            externalTokensRouter.estimateDeposit(_tokensOut, _amountsOut);

        (address[] memory sortedAddresses, uint256[] memory sortedAmounts) =
            sortBPTokenstoPools(bptTokens, amounts);

        (uint256 errorCode, ) =
            fund.redeemChecksPass(sortedAddresses, sortedAmounts, _maxGyroRedeemed);

        return errorCode;
    }

    function estimateRedeemedGyro(address[] memory _tokensOut, uint256[] memory _amountsOut)
        public
        view
        returns (uint256)
    {
        (address[] memory bptTokens, uint256[] memory amounts) =
            externalTokensRouter.estimateWithdraw(_tokensOut, _amountsOut);

        (address[] memory _sortedAddresses, uint256[] memory _sortedAmounts) =
            sortBPTokenstoPools(bptTokens, amounts);

        (, uint256 _amountToRedeem) = fund.redeemChecksPass(_sortedAddresses, _sortedAmounts, 10);

        return _amountToRedeem;
    }

    function getSupportedTokens() external view returns (address[] memory) {
        return fund.getUnderlyingTokenAddresses();
    }

    function sortBPTokenstoPools(address[] memory _BPTokensIn, uint256[] memory amounts)
        public
        view
        returns (address[] memory, uint256[] memory)
    {
        address[] memory sortedAddresses = fund.poolAddresses();
        uint256[] memory sortedAmounts = new uint256[](sortedAddresses.length);

        for (uint256 i = 0; i < _BPTokensIn.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < sortedAddresses.length; j++) {
                if (sortedAddresses[j] == _BPTokensIn[i]) {
                    sortedAmounts[j] += amounts[i];
                    found = true;
                    break;
                }
            }
            require(found, "could not find valid pool");
        }

        return (sortedAddresses, sortedAmounts);
    }
}
