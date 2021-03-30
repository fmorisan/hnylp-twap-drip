pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
// import { IERC20 as OZIERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeMath as OZSafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import "@uniswap/v2-periphery/contracts/examples/ExampleSlidingWindowOracle.sol";
import "@uniswap/v2-periphery/contracts/UniswapV2Router02.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";


contract Dripper is Ownable {
    using OZSafeMath for uint256;

    struct DripConfig {
        uint startTime;
        uint transitionTime;
        uint dripInterval;
        uint maxTWAPDifferencePct;
    }

    DripConfig public dripConfig;
    uint256 public latestDripTime;

    string public constant ERROR_BASETOKEN_UNDETERMINABLE = "Dripper: Base Token cannot be determined.";
    string public constant ERROR_CONVERSION_IMPOSSIBLE = "Dripper: Cannot find converter LP.";
    string public constant ERROR_FAR_FROM_TWAP = "Dripper: Converter LP price is too far from TWAP.";
    string public constant ERROR_DRIP_INTERVAL = "Dripper: Drip interval has not passed.";
    uint256 private constant ONE = 10**18;

    IUniswapV2Pair public startLP; // WETH- AGVE
    IUniswapV2Pair public endLP; // HNY-AGVE
    IUniswapV2Pair public conversionLP; // HNY-WETH
    
    UniswapV2Router02 public router;
    
    bool private startTokenIsFirstConversionLPToken;

    IERC20 public startToken; // WETH
    IERC20 public endToken; // HNY
    IERC20 public baseToken; // AGVE

    ExampleSlidingWindowOracle public twapOracle;

    uint256 public initialStartLPBalance;

    event Drip(uint256 price, uint256 baseTokenAdded, uint256 endTokenAdded);

    constructor(
        address _startToken,
        address _endToken,
        address _baseToken,
        address payable _router,
        address _twapOracle,
        uint256 _transitionTime,
        uint256 _dripSpacing
    ) public Ownable() {
        router = UniswapV2Router02(_router);
        address factory = router.factory();

        startLP = IUniswapV2Pair(UniswapV2Library.pairFor(factory, _startToken, _baseToken));
        endLP = IUniswapV2Pair(UniswapV2Library.pairFor(factory, _endToken, _baseToken));
        conversionLP = IUniswapV2Pair(UniswapV2Library.pairFor(factory, _startToken, _endToken));

        twapOracle = ExampleSlidingWindowOracle(_twapOracle);

        dripConfig = DripConfig({
            startTime: now,
            transitionTime: _transitionTime,
            dripInterval: _dripSpacing,
            maxTWAPDifferencePct: ONE.div(100).mul(5) // accept no more than 5% deviation from TWAP
        });

        initialStartLPBalance = startLP.balanceOf(address(this));
    }

    function drip() public {
        require(now >= latestDripTime.add(dripConfig.dripInterval), ERROR_DRIP_INTERVAL);
        // check current fromToken -> endToken price doesn't deviate too much from TWAP
        uint256 price = _getConversionPrice();
        {
            uint256 twap = _getConversionTWAP();
            require(
                twap.mul(ONE).div(price) < ONE.add(dripConfig.maxTWAPDifferencePct)
                && price.mul(ONE).div(twap) < ONE.add(dripConfig.maxTWAPDifferencePct),
                ERROR_FAR_FROM_TWAP
            );
        }
        // get start lp balance
        uint256 startTokenFromStartLP;
        uint256 baseTokenFromStartLP;
        {
            // calculate how much should be withdrawn
            uint256 timeSinceLastDrip = now - latestDripTime;
            uint256 startLPToWithdraw = initialStartLPBalance.mul(
                    timeSinceLastDrip.mul(ONE).div(dripConfig.transitionTime)
                ).div(ONE);

            uint b = startLP.balanceOf((address(this)));
            if (b < startLPToWithdraw) {
                startLPToWithdraw = b;
            }

            // withdraw it
            (
                startTokenFromStartLP, baseTokenFromStartLP
            ) = router.removeLiquidity(
                address(startToken),
                address(baseToken),
                startLPToWithdraw,
                0, 0,
                address(this),
                now
            );
        }

        // swap fromToken to endToken
        address[] memory path = address[]([address(startToken), address(endToken)]);
        uint[] memory amounts = router.swapExactTokensForTokens(
            startTokenFromStartLP,
            price.mul(startTokenFromStartLP).div(ONE),
            path,
            address(this),
            now
        );
        uint256 endTokenToAddAsLiquidity = amounts[amounts.length - 1];

        // add fromToken and necessary amount of baseToken to endLP
        router.addLiquidity(
            address(endToken),
            address(baseToken),
            endTokenToAddAsLiquidity,
            baseTokenFromStartLP,
            endTokenToAddAsLiquidity,
            baseTokenFromStartLP,
            address(this),
            now
        );

        latestDripTime = now;

        emit Drip(price, baseTokenFromStartLP, endTokenToAddAsLiquidity);
    }

    function _getConversionTWAP() internal view returns (uint256) {
        return twapOracle.consult(address(startToken), ONE, address(endToken));
    }

    function _getConversionPrice() internal view returns (uint256) {
        (uint112 balance0, uint112 balance1, uint32 blockTimestamp) = conversionLP.getReserves();
        if (address(startToken) == conversionLP.token0()) {
            return UniswapV2Library.quote(ONE, balance0, balance1);
        } else {
            return UniswapV2Library.quote(ONE, balance1, balance0);
        }
    }
}