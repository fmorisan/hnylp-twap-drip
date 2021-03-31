pragma solidity ^0.6.0;

interface IOracle {
    function consult(address tokenA, uint256 amount, address tokenB) external view returns (uint256);
}