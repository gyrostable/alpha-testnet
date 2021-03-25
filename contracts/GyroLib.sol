// SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "./BalancerGyroRouter.sol";
import "./GyroFund.sol";
import "./Ownable.sol";

/**
 * @notice GyroLib is a contract used to add functionality around the GyroFund
 * to allow users to exchange assets for Gyro rather than having
 * to use already minted Balancer Pool Tokens
 */
contract GyroLib is Ownable {
    event Mint(address indexed minter, uint256 indexed amount);
    event Redeem(address indexed redeemer, uint256 indexed amount);

    GyroFundV1 public fund;
    BalancerExternalTokenRouter public externalTokensRouter;

    constructor(address gyroFundAddress, address externalTokensRouterAddress) {
        fund = GyroFundV1(gyroFundAddress);
        externalTokensRouter = BalancerExternalTokenRouter(externalTokensRouterAddress);
    }

    function setFundAddress(address _fundAddress) external onlyOwner {
        fund = GyroFundV1(_fundAddress);
    }

    function setRouterAddress(address _routerAddress) external onlyOwner {
        externalTokensRouter = BalancerExternalTokenRouter(_routerAddress);
    }

    /**
     * @notice Mints at least `_minAmountOut` Gyro dollars by using the tokens and amounts
     * passed in `_tokensIn` and `_amountsIn`. `_tokensIn` and `_amountsIn` must
     * be the same length and `_amountsIn[i]` is the amount of `_tokensIn[i]` to
     * use to mint Gyro dollars.
     * This contract should be approved to spend at least the amount given
     * for each token of `_tokensIn`
     *
     * @param _tokensIn a list of tokens to use to mint Gyro dollars
     * @param _amountsIn the amount of each token to use
     * @param _minAmountOut the minimum number of Gyro dollars wanted, used to prevent against slippage
     * @return the amount of Gyro dollars minted
     */
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
        emit Mint(msg.sender, minted);
        return minted;
    }

    /**
     * @notice Redeems at most `_maxRedeemed` to receive exactly `_amountsOut[i]`
     * of each `_tokensOut[i]`.
     * `_tokensOut[i]` and  `_amountsOut[i]` must be the same length and `_amountsOut[i]`
     * is the amount desired of `_tokensOut[i]`
     * This contract should be allowed to spend the amount of Gyro dollars redeemed
     * which is at most `_maxRedeemed`
     *
     * @param _tokensOut the tokens to receive in exchange for redeeming Gyro dollars
     * @param _amountsOut the amount of each token to receive
     * @param _maxRedeemed the maximum number of Gyro dollars to redeem
     * @return the amount of Gyro dollar redeemed
     */
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

        emit Redeem(msg.sender, _amountRedeemed);
        return _amountRedeemed;
    }

    /**
     * @notice This functions approximates how many Gyro dollars would be minted given
     * `_tokensIn` and `_amountsIn`. See the documentation of `mintFromUnderlyingTokens`
     * for more details about these parameters
     * @param _tokensIn the tokens to use for minting
     * @param _amountsIn the amount of each token to use
     * @return the estimated amount of Gyro dolars minted
     */
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

    /**
     * @notice This functions approximates how many Gyro dollars would be redeemed given
     * `_tokensOut` and `_amountsOut`. See the documentation of `redeemToUnderlyingTokens`
     * for more details about these parameters
     * @param _tokensOut the tokens receive back
     * @param _amountsOut the amount of each token to receive
     * @return the estimated amount of Gyro dolars redeemed
     */
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

    /**
     * @notice Checks if a call to `mintFromUnderlyingTokens` with the given
     * `_tokensIn`, `_amountsIn and `_minGyroMinted` would succeed or not,
     * and returns the potential error code
     * @param _tokensIn a list of tokens to use to mint Gyro dollars
     * @param _amountsIn the amount of each token to use
     * @param _minGyroMinted the minimum number of Gyro dollars wanted
     * @return an error code if the call would fail, otherwise 0
     * See GyroFundV1 for the meaning of each error code
     */
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

    /**
     * @notice Checks if a call to `redeemToUnderlyingTokens` with the given
     * `_tokensOut`, `_amountsOut and `_maxGyroRedeemed` would succeed or not,
     * and returns the potential error code
     * @param _tokensOut the tokens to receive in exchange for redeeming Gyro dollars
     * @param _amountsOut the amount of each token to receive
     * @param _maxGyroRedeemed the maximum number of Gyro dollars to redeem
     * @return an error code if the call would fail, otherwise 0
     */
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

    /**
     * @return the list of tokens supported by the Gyro fund
     */
    function getSupportedTokens() external view returns (address[] memory) {
        return fund.getUnderlyingTokenAddresses();
    }

    /**
     * @return the list of Balance pools supported by the Gyro fund
     */
    function getSupportedPools() external view returns (address[] memory) {
        return fund.poolAddresses();
    }

    /**
     * @return the current values of the Gyro fund's reserve
     */
    function getReserveValues()
        external
        view
        returns (
            uint256,
            address[] memory,
            uint256[] memory
        )
    {
        return fund.getReserveValues();
    }

    function sortBPTokenstoPools(address[] memory _BPTokensIn, uint256[] memory amounts)
        internal
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
