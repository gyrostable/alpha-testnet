//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "./CTokenInterfaces.sol";

/**
 * @title Compound's CToken Contract
 * @notice Abstract base for CTokens
 * @author Compound
 */
abstract contract CToken is CTokenInterface, CErc20Interface {

}
