//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.0;

import "hardhat/console.sol";

contract GyroCore {
    event AssetsUpdated(uint256 indexed newVersion);

    uint256 assetsVersion = 0;
    address[] public vaultAddresses;
    uint256[] public vaultWeights; // in token-proportions, not value-proportions

    constructor() public {}

    /**
     * [Check the inputted vault tokens are in the right proportions, if not, adjust, then mint.]
     *
     **/
    function mint(
        uint256[] memory _vaultTokens,
        uint256 _minGyroOutput,
        uint256 _assetsVersion
    ) public view {
        require(
            _vaultTokens.length == vaultAddresses.length,
            "incorrect number of tokens given"
        );
        require(
            _assetsVersion == assetsVersion,
            "given assetsVersion does not match current one"
        );
    }

    function redeem(
        uint256 _gyroAmount,
        uint256[] memory _minTokens,
        uint256 _assetsVersion
    ) public view {
        require(
            _assetsVersion == assetsVersion,
            "given assetsVersion does not match current one"
        );
    }

    /**
     * [Add permissioning functionality]
     * [Permissioned so admin controls weights but with a long veto period]
     **/
    function proposeRebalance(
        address[] memory _vaultAddresses,
        uint256[] memory _vaultWeights
    ) public {
        require(
            _vaultAddresses.length == _vaultWeights.length,
            "the same number of addresses and weights should be given"
        );
    }

    function executeRebalance() public {
        // do cool stuff
        assetsVersion += 1;
        emit AssetsUpdated(assetsVersion);
    }

    function countVetoVotes() public {}
}
