// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

// Test Token

import "./Ownable.sol";

contract TokenFaucet is Ownable {
    string public name;
    string public symbol;
    uint8 public decimals;

    address private _owner;

    uint256 internal _totalSupply;

    mapping(address => uint256) private _balance;
    mapping(address => mapping(address => uint256)) private _allowance;
    mapping(address => uint256) private lastAccessTime;

    uint256 private constant waitTime = 30 minutes;
    uint256 public mintAmt;

    event Approval(address indexed src, address indexed dst, uint256 amt);
    event Transfer(address indexed src, address indexed dst, uint256 amt);

    // Math
    function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require((c = a + b) >= a);
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require((c = a - b) <= a);
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _mintAmt
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        mintAmt = _mintAmt;
    }

    function setMintAmount(uint256 _mintAmount) external onlyOwner {
        mintAmt = _mintAmount;
    }

    function _move(
        address src,
        address dst,
        uint256 amt
    ) internal {
        require(_balance[src] >= amt, "ERR_INSUFFICIENT_BALANCE");
        _balance[src] = sub(_balance[src], amt);
        _balance[dst] = add(_balance[dst], amt);
        emit Transfer(src, dst, amt);
    }

    function _push(address to, uint256 amt) internal {
        _move(address(this), to, amt);
    }

    function _pull(address from, uint256 amt) internal {
        _move(from, address(this), amt);
    }

    function _mint(address dst, uint256 amt) internal {
        _balance[dst] = add(_balance[dst], amt);
        _totalSupply = add(_totalSupply, amt);
        emit Transfer(address(0), dst, amt);
    }

    function allowance(address src, address dst) external view returns (uint256) {
        return _allowance[src][dst];
    }

    function balanceOf(address whom) external view returns (uint256) {
        return _balance[whom];
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function approve(address dst, uint256 amt) external returns (bool) {
        _allowance[msg.sender][dst] = amt;
        emit Approval(msg.sender, dst, amt);
        return true;
    }

    function mintAsOwner(address dst, uint256 amt) public onlyOwner returns (bool) {
        _mint(dst, amt);
        return true;
    }

    function allowedToMint(address whom) internal view returns (bool) {
        if (lastAccessTime[whom] == 0) {
            return true;
        } else if (block.timestamp >= lastAccessTime[whom] + waitTime) {
            return true;
        }
        return false;
    }

    function mint() public returns (bool) {
        require(allowedToMint(msg.sender));
        lastAccessTime[msg.sender] = block.timestamp;
        _mint(msg.sender, mintAmt * 10**decimals);
        return true;
    }

    function burn(uint256 amt) public returns (bool) {
        require(_balance[address(this)] >= amt, "ERR_INSUFFICIENT_BAL");
        _balance[address(this)] = sub(_balance[address(this)], amt);
        _totalSupply = sub(_totalSupply, amt);
        emit Transfer(address(this), address(0), amt);
        return true;
    }

    function transfer(address dst, uint256 amt) external returns (bool) {
        _move(msg.sender, dst, amt);
        return true;
    }

    function transferFrom(
        address src,
        address dst,
        uint256 amt
    ) external returns (bool) {
        require(msg.sender == src || amt <= _allowance[src][msg.sender], "ERR_BTOKEN_BAD_CALLER");
        _move(src, dst, amt);
        if (msg.sender != src && _allowance[src][msg.sender] != uint256(-1)) {
            _allowance[src][msg.sender] = sub(_allowance[src][msg.sender], amt);
            emit Approval(msg.sender, dst, _allowance[src][msg.sender]);
        }
        return true;
    }
}

contract MetaFaucet is Ownable {
    event Mint(address indexed account, address indexed token, uint256 indexed amount);

    address[] public tokenFaucets;
    mapping(address => uint256) public mintAmounts;

    constructor(address[] memory _tokenFaucets, uint256[] memory _mintAmounts) {
        tokenFaucets = _tokenFaucets;
        for (uint256 i = 0; i < _tokenFaucets.length; i++) {
            mintAmounts[_tokenFaucets[i]] = _mintAmounts[i];
        }
    }

    function mintAllAsOwner(address dst) public onlyOwner returns (bool) {
        address[] memory _tokenFaucets = tokenFaucets;
        for (uint256 i = 0; i < _tokenFaucets.length; i++) {
            TokenFaucet faucet = TokenFaucet(_tokenFaucets[i]);
            uint256 amount = mintAmounts[address(faucet)] * 10**faucet.decimals();
            TokenFaucet(_tokenFaucets[i]).mintAsOwner(dst, amount);
            emit Mint(msg.sender, _tokenFaucets[i], amount);
        }
        return true;
    }

    function mintAsOwner(
        address token,
        address dst,
        uint256 amt
    ) public onlyOwner returns (bool) {
        return TokenFaucet(token).mintAsOwner(dst, amt);
    }

    function setMintAmount(address token, uint256 amt) external onlyOwner {
        mintAmounts[token] = amt;
    }

    function restoreFaucetOwnership(address token) public onlyOwner {
        TokenFaucet(token).transferOwnership(msg.sender);
    }

    function restoreAllFaucetsOwnership() external onlyOwner {
        address[] memory _tokenFaucets = tokenFaucets;
        for (uint256 i = 0; i < _tokenFaucets.length; i++) {
            TokenFaucet(_tokenFaucets[i]).transferOwnership(msg.sender);
        }
    }

    function getTokens() external view returns (address[] memory) {
        address[] memory _tokenFaucets = tokenFaucets;
        return _tokenFaucets;
    }
}
