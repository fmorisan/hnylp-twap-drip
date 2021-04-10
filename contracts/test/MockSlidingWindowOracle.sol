pragma solidity ^0.6.0;

import { SafeMath as OZSafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

contract MockSlidingWindowOracle {
    using OZSafeMath for uint256;

    uint256 public constant ONE = 10**18;

    mapping(address => mapping(address => uint256)) public twaps;

    function setPrice(address tokenA, address tokenB, uint256 twap) public {
        // TWAP is for 10**18 tokenA
        twaps[tokenA][tokenB] = twap;
    }

    function consult(address tokenA, uint256 tokenAAmount, address tokenB) public view returns (uint256) {
        uint256 price = twaps[tokenA][tokenB];

        if (price > 0) return price.mul(tokenAAmount).div(ONE);

        price = twaps[tokenB][tokenA];

        require(price > 0, "TWAP not present");

        return ONE.mul(tokenAAmount).div(price);
    }
}