pragma solidity ^0.6.0;

contract MockSlidingWindowOracle {
    mapping(address => mapping(address => uint256)) public twaps;

    function setPrice(address tokenA, address tokenB, uint256 twap) public {
        twaps[tokenA][tokenB] = twap;
    }

    function consult(address tokenA, address tokenB) public view returns (uint256) {
        return twaps[tokenA][tokenB];
    }
}