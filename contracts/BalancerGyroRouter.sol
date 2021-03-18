// SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./GyroRouter.sol";
import "./balancer/BPool.sol";
import "./Ownable.sol";

/**
 * @notice This contracts is a very simple router to deposit supported assets and
 * receive Balancer Pool Tokens depositable directly in the Gyro reserve in return
 */
contract BalancerExternalTokenRouter is GyroRouter, Ownable {
    mapping(address => address[]) public pools;
    address[] public tokens;

    event UnderlyingTokensDeposited(address[] indexed bpAddresses, uint256[] indexed bpAmounts);

    /**
     * @notice Deposits `_amountsIn` amounts of `_tokensIn` and receives Balancer Pool tokens
     * in return. `_amountsIn[i]` is the amount of `_tokensIn[i]` token to deposit.
     * @param _tokensIn the tokens to deposit
     * @param _amountsIn the amount to deposit for each token
     * @return the addresses and amounts of the Balancer Pool tokens received
     * The length of the output tokens will be equal to the length of the output tokens
     * and may contain duplicates
     */
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
            require(success, "failed to transfer tokens from sender to GryoRouter");

            BPool pool = BPool(choosePoolToDeposit(token, amount));
            uint256 poolAmountOut = pool.joinswapExternAmountIn(token, amount, 0);
            success = pool.transfer(msg.sender, poolAmountOut);
            require(success, "failed to transfer BPT to sender");

            _bpAmounts[i] = poolAmountOut;
            _bpAddresses[i] = address(pool);
        }

        emit UnderlyingTokensDeposited(_bpAddresses, _bpAmounts);
        return (_bpAddresses, _bpAmounts);
    }

    /**
     * @notice Estimates how many Balancer Pool tokens would be received given
     * `_amountsIn` amounts of `_tokensIn`. See `deposit` for more information
     * @param _tokensIn the tokens to deposit
     * @param _amountsIn the amount to deposit for each token
     * @return the addresses and amounts of the Balancer Pool tokens that would be received
     */
    function estimateDeposit(address[] memory _tokensIn, uint256[] memory _amountsIn)
        external
        view
        returns (address[] memory, uint256[] memory)
    {
        address[] memory _bpAddresses = new address[](_tokensIn.length);
        uint256[] memory _bpAmounts = new uint256[](_amountsIn.length);

        for (uint256 i = 0; i < _tokensIn.length; i++) {
            address token = _tokensIn[i];
            uint256 amount = _amountsIn[i];

            BPool pool = BPool(choosePoolToDeposit(token, amount));
            uint256 poolAmountOut = calcPoolOutGivenSingleIn(pool, token, amount);
            _bpAddresses[i] = address(pool);
            _bpAmounts[i] = poolAmountOut;
        }
        return (_bpAddresses, _bpAmounts);
    }

    /**
     * @notice Withdraws the underlying tokens using `_amountsOut` amounts of `_tokensOut` of Balancer Pool tokens.
     * The given balancer pool tokens should be supported by this router
     * @param _tokensOut the Balancer Pool tokens to use
     * @param _amountsOut the amount to for each token
     * @return the addresses and amounts of the underlying tokens that would be received
     * The number of tokens returned will have the same length than the
     * number of pools given and may contain duplicates
     */
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
            require(success, "failed to transfer BPT from sender to GryoRouter");

            pool.exitswapExternAmountOut(token, amount, poolAmountIn);

            success = IERC20(token).transfer(msg.sender, amount);
            require(success, "failed to transfer token to sender");
        }
        return (_tokensOut, _amountsOut);
    }

    /**
     * @notice Estimates how many of the underlying tokens would be received given
     * `_amountsOut` amounts of `_tokensOut` of Balancer Pool tokens. See `withdraw` for more information
     * @param _tokensOut the Balancer Pool tokens to use
     * @param _amountsOut the amount to for each token
     * @return the addresses and amounts of the underlying tokens that would be received
     */
    function estimateWithdraw(address[] memory _tokensOut, uint256[] memory _amountsOut)
        external
        view
        returns (address[] memory, uint256[] memory)
    {
        address[] memory _bpAddresses = new address[](_tokensOut.length);
        uint256[] memory _bpAmounts = new uint256[](_amountsOut.length);

        for (uint256 i = 0; i < _tokensOut.length; i++) {
            address token = _tokensOut[i];
            uint256 amount = _amountsOut[i];

            BPool pool = BPool(choosePoolToDeposit(token, amount));
            uint256 poolAmountIn = calcPoolInGivenSingleOut(pool, token, amount);
            _bpAddresses[i] = address(pool);
            _bpAmounts[i] = poolAmountIn;
        }
        return (_bpAddresses, _bpAmounts);
    }

    function calcPoolOutGivenSingleIn(
        BPool pool,
        address _token,
        uint256 _amount
    ) internal view returns (uint256) {
        uint256 tokenBalanceIn = pool.getBalance(_token);
        uint256 tokenWeightIn = pool.getDenormalizedWeight(_token);
        uint256 poolSupply = pool.totalSupply();
        uint256 totalWeight = pool.getTotalDenormalizedWeight();
        uint256 swapFee = pool.getSwapFee();
        return
            pool.calcPoolOutGivenSingleIn(
                tokenBalanceIn,
                tokenWeightIn,
                poolSupply,
                totalWeight,
                _amount,
                swapFee
            );
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
            if (currentPools.length == 0) {
                tokens.push(tokenAddress);
            }
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

    function allTokens() external view returns (address[] memory) {
        address[] memory _tokens = new address[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            _tokens[i] = tokens[i];
        }
        return _tokens;
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
