//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../Ownable.sol";

enum PriceSource {
    FIXED_ETH, /// implies the fixedPrice is a constant multiple of the ETH price (which varies)
    FIXED_USD, /// implies the fixedPrice is a constant multiple of the USD price (which is 1)
    REPORTER /// implies the price is set by the reporter
}

struct TokenConfig {
    address cToken;
    address underlying;
    bytes32 symbolHash;
    uint256 baseUnit;
    PriceSource priceSource;
    uint256 fixedPrice;
    address uniswapMarket;
    bool isUniswapReversed;
}

interface UniswapAnchoredView {
    function price(string calldata symbol) external view returns (uint256);

    function getTokenConfigBySymbol(string memory symbol)
        external
        view
        returns (TokenConfig memory);
}

contract DummyUniswapAnchoredView is Ownable, UniswapAnchoredView {
    mapping(string => uint256) private prices;
    mapping(string => TokenConfig) private tokenConfigs;
    mapping(string => bool) private tokenRegistered;

    function addToken(string memory symbol, TokenConfig memory config) public onlyOwner {
        tokenRegistered[symbol] = true;
        tokenConfigs[symbol] = config;
    }

    function setPrice(string memory symbol, uint256 _price) public onlyOwner {
        require(tokenRegistered[symbol], "symbol not registered");
        prices[symbol] = _price;
    }

    function price(string calldata symbol) external view override returns (uint256) {
        return prices[symbol];
    }

    function getTokenConfigBySymbol(string memory symbol)
        external
        view
        override
        returns (TokenConfig memory)
    {
        return tokenConfigs[symbol];
    }
}
