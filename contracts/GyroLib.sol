// SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "./BalancerGyroRouter.sol";
import "./GyroFund.sol";

contract GyroLib {
    GyroFund fund;
    BalancerExternalTokenRouter externalTokensRouter;

    constructor(address gyroFundAddress, address externalTokensRouterAddress) {
        fund = GyroFund(gyroFundAddress);
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
        for (uint256 i = 0; i < bptTokens.length; i++) {
            IERC20(bptTokens[i]).approve(address(fund), amounts[i]);
        }
        uint256 minted = fund.mint(bptTokens, amounts, _minAmountOut);
        require(fund.transfer(msg.sender, minted), "failed to send back gyro");
        return minted;
    }

    function estimateUnderlyingTokens(address[] memory _tokensIn, uint256[] memory _amountsIn)
        public
        view
        returns (uint256)
    {
        (address[] memory bptTokens, uint256[] memory amounts) =
            externalTokensRouter.estimateDeposit(_tokensIn, _amountsIn);
        return fund.estimateMint(bptTokens, amounts);
    }

    function getSupportedTokens() external view returns (address[] memory) {
        return externalTokensRouter.allTokens();
    }
}
