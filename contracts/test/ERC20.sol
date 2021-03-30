pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract MyERC20 is ERC20 {
    function mint(address who, uint256 amt) public {
        _mint(who, amt);
    }
}