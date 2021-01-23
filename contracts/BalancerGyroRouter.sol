// SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./GyroRouter.sol";
import "./balancer/BPool.sol";
import "./Ownable.sol";

contract BalancerExternalTokenRouter is GyroRouter, Ownable {
    mapping(address => address[]) public pools;

    event UnderlyingTokensDeposited(address[] indexed bpAddresses, uint256[] indexed bpAmounts);

    function deposit(address[] memory _tokensIn, uint256[] memory _amountsIn)
        external
        override
        returns (address[] memory, uint256[] memory)
    {
        address[] memory _bpAddresses = new address[](_tokensIn.length);
        uint256[] memory _bpAmounts = new uint256[](_amountsIn.length);

        for (uint256 i = 0; i < _tokensIn.length; i++) {
            address token = _tokensIn[i];
            uint256 amount = _amountsIn[i];
            bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
            require(success, "failed to transfer tokens from GyroFund to GryoRouter");

            BPool pool = BPool(choosePoolToDeposit(token, amount));
            uint256 poolAmountOut = pool.joinswapExternAmountIn(token, amount, 0);
            success = pool.transfer(msg.sender, poolAmountOut);
            require(success, "failed to transfer BPT to GyroFund");

            _bpAmounts[i] = poolAmountOut;
            _bpAddresses[i] = address(pool);
        }

        emit UnderlyingTokensDeposited(_bpAddresses, _bpAmounts);
        return (_bpAddresses, _bpAmounts);
    }

    function withdraw(address[] memory _tokensOut, uint256[] memory _amountsOut)
        external
        override
        returns (address[] memory, uint256[] memory)
    {
        for (uint256 i = 0; i < _tokensOut.length; i++) {
            address token = _tokensOut[i];
            uint256 amount = _amountsOut[i];
            BPool pool = BPool(choosePoolToWithdraw(token, amount));
            uint256 poolAmountIn = calcPoolInGivenSingleOut(pool, token, amount);

            bool success = pool.transferFrom(msg.sender, address(this), poolAmountIn);
            require(success, "failed to transfer BPT from GyroFund to GryoRouter");

            pool.exitswapExternAmountOut(token, amount, 0);

            success = IERC20(token).transfer(msg.sender, amount);
            require(success, "failed to transfer token to GyroFund");
        }
        return (_tokensOut, _amountsOut);
    }

    function calcPoolInGivenSingleOut(
        BPool pool,
        address _token,
        uint256 _amount
    ) internal view returns (uint256) {
        uint256 tokenBalanceOut = pool.getBalance(_token);
        uint256 tokenWeightOut = pool.getDenormalizedWeight(_token);
        uint256 poolSupply = pool.totalSupply();
        uint256 totalWeight = pool.getTotalDenormalizedWeight();
        uint256 swapFee = pool.getSwapFee();
        return
            pool.calcPoolInGivenSingleOut(
                tokenBalanceOut,
                tokenWeightOut,
                poolSupply,
                totalWeight,
                _amount,
                swapFee
            );
    }

    function choosePoolToDeposit(address _token, uint256 _amount) private view returns (address) {
        address[] storage candidates = pools[_token];
        require(candidates.length > 0, "token not supported");
        // TODO: choose better
        return candidates[_amount % candidates.length];
    }

    function choosePoolToWithdraw(address _token, uint256 _amount) private view returns (address) {
        address[] storage candidates = pools[_token];
        require(candidates.length > 0, "token not supported");
        // TODO: choose better
        return candidates[_amount % candidates.length];
    }

    function addPool(address _poolAddress) public onlyOwner {
        BPool pool = BPool(_poolAddress);
        require(pool.isFinalized(), "can only add finalized pools");
        address[] memory poolTokens = pool.getFinalTokens();
        for (uint256 i = 0; i < poolTokens.length; i++) {
            address tokenAddress = poolTokens[i];
            address[] storage currentPools = pools[tokenAddress];
            bool exists = false;
            for (uint256 j = 0; j < currentPools.length; j++) {
                if (currentPools[j] == _poolAddress) {
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                currentPools.push(_poolAddress);
                IERC20(tokenAddress).approve(_poolAddress, uint256(-1));
            }
        }
    }
}

contract BalancerTokenRouter is GyroRouter, Ownable {
    function deposit(address[] memory _tokensIn, uint256[] memory _amountsIn)
        external
        pure
        override
        returns (address[] memory, uint256[] memory)
    {
        return (_tokensIn, _amountsIn);
    }

    function withdraw(address[] memory _tokensOut, uint256[] memory _amountsOut)
        external
        pure
        override
        returns (address[] memory, uint256[] memory)
    {
        return (_tokensOut, _amountsOut);
    }
}
