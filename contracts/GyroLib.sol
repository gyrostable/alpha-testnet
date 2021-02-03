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

        (address[] memory poolAddresses, uint256[] memory orderedAmounts) =
            sortBPTokenstoPools(bptTokens, amounts);

        for (uint256 i = 0; i < bptTokens.length; i++) {
            IERC20(bptTokens[i]).approve(address(fund), orderedAmounts[i]);
        }
        uint256 minted = fund.mint(bptTokens, orderedAmounts, _minAmountOut);
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

        (address[] memory poolAddresses, uint256[] memory orderedAmounts) =
            sortBPTokenstoPools(bptTokens, amounts);

        return fund.estimateMint(poolAddresses, orderedAmounts);
    }

    function getSupportedTokens() external view returns (address[] memory) {
        return fund.getUnderlyingTokenAddresses();
    }

    function sortBPTokenstoPools(address[] memory _BPTokensIn, uint256[] memory amounts)
        public
        view
        returns (address[] memory, uint256[] memory)
    {
        address[] memory poolAddresses = fund.poolAddresses();
        uint256[] memory orderedAmounts = new uint256[](poolAddresses.length);

        for (uint256 i = 0; i< _BPTokensIn.length; i++ ) {
            console.log("BP Tokens in 1", _BPTokensIn[i]);
        }

        for (uint256 i = 0; i< poolAddresses.length; i++ ) {
            console.log("Pool properties 2", poolAddresses[i]);
        }

        for (uint256 i = 0; i < _BPTokensIn.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < poolAddresses.length; j++) {
                if (poolAddresses[j] == _BPTokensIn[i]) {
                    orderedAmounts[j] += amounts[i];
                    found = true;
                    break;
                }
            }
            require(found, "could not find valid pool");
        }

        return (poolAddresses, orderedAmounts);

    }


}
