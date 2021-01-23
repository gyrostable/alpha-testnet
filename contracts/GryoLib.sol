// SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "./BalancerGyroRouter.sol";
import "./GyroFund.sol";

contract GyroLib {
    BalancerExternalTokenRouter externalTokensRouter;
    GyroFund fund;

    constructor(address externalTokensRouterAddress, address gyroFundAddress) {
        externalTokensRouter = BalancerExternalTokenRouter(externalTokensRouterAddress);
        fund = GyroFund(gyroFundAddress);
    }

    function mintFromArbitraryTokens(
        address[] memory _tokensIn,
        uint256[] memory _amountsIn,
        uint256 _minAmountOut
    ) public returns (uint256) {
        for (uint256 i = 0; i < _tokensIn.length; i++) {
            bool success =
                IERC20(_tokensIn[i]).transferFrom(msg.sender, address(this), _amountsIn[i]);
            require(success, "failed to transfer tokens from GyroFund to GryoRouter");
        }
        (address[] memory bptTokens, uint256[] memory amounts) =
            externalTokensRouter.deposit(_tokensIn, _amountsIn);
        return fund.mint(bptTokens, amounts, _minAmountOut);
    }
}
