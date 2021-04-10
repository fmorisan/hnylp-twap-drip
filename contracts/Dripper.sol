pragma solidity ^0.6.0;

import "./interfaces/IOracle.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 as OZIERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeMath as OZSafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "@uniswap/v2-periphery/contracts/examples/ExampleSlidingWindowOracle.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";


contract Dripper is Ownable {
    using OZSafeMath for uint256;

    struct DripConfig {
        uint startTime;
        uint transitionTime;
        uint dripInterval;
        uint maxTWAPDifferencePct;
        uint maxSlippageTolerancePct;
    }

    DripConfig public dripConfig;
    uint256 public latestDripTime;

    string public constant ERROR_FAR_FROM_TWAP = "Dripper: Converter LP price is too far from TWAP.";
    string public constant ERROR_DRIP_INTERVAL = "Dripper: Drip interval has not passed.";
    string public constant ERROR_ALREADY_CONFIGURED = "Dripper: Already configured.";
    string public constant ERROR_INTOLERABLE_SLIPPAGE = "Dripper: Slippage exceeds configured limit.";

    uint256 private constant ONE = 10**18;

    IUniswapV2Pair public startLP; // WETH- AGVE
    IUniswapV2Pair public endLP; // HNY-AGVE
    IUniswapV2Pair public conversionLP; // HNY-WETH
    
    IUniswapV2Router02 public router;
    
    bool private startTokenIsFirstConversionLPToken;

    OZIERC20 public startToken; // WETH
    OZIERC20 public endToken; // HNY
    OZIERC20 public baseToken; // AGVE

    IOracle public twapOracle;

    uint256 public initialStartLPBalance;

    event Drip(uint256 price, uint256 baseTokenAdded, uint256 endTokenAdded);
    event c(uint256 a);

    constructor(
        address _startToken,
        address _endToken,
        address _baseToken,
        address payable _router,
        address _twapOracle
    ) public Ownable() {
        router = IUniswapV2Router02(_router);
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());
        //address factory = address(0);

        startToken = OZIERC20(_startToken);
        endToken = OZIERC20(_endToken);
        baseToken = OZIERC20(_baseToken);

        startLP = IUniswapV2Pair(factory.getPair(_startToken, _baseToken));
        endLP = IUniswapV2Pair(factory.getPair(_endToken, _baseToken));
        conversionLP = IUniswapV2Pair(factory.getPair(_startToken, _endToken));

        twapOracle = IOracle(_twapOracle);

    }

    function startDrip(
        uint256 amount,
        uint256 _transitionTime,
        uint256 _dripSpacing,
        uint256 _twapDeviationTolerance,
        uint256 _slippageTolerance
    ) public onlyOwner
    {
        require(dripConfig.startTime == 0, ERROR_ALREADY_CONFIGURED);

        require(startLP.transferFrom(msg.sender, address(this), amount));
        dripConfig = DripConfig(
            now,
            _transitionTime,
            _dripSpacing,
            _twapDeviationTolerance,
            _slippageTolerance
        );

        initialStartLPBalance = amount;
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
            uint256 timeSinceLastDrip = now - (
                latestDripTime < dripConfig.startTime ?
                    dripConfig.startTime : latestDripTime
            );
            uint256 startLPToWithdraw = initialStartLPBalance.mul(
                    timeSinceLastDrip.mul(ONE).div(dripConfig.transitionTime)
                ).div(ONE);


            uint b = startLP.balanceOf((address(this)));

            // if we don't have enough to cover this drip, then we are at the end of the drip time.
            if (b < startLPToWithdraw) {
                startLPToWithdraw = b;
            }

            startLP.approve(address(router), startLPToWithdraw);
            // withdraw it
            (
                startTokenFromStartLP, baseTokenFromStartLP
            ) = router.removeLiquidity(
                address(startToken),
                address(baseToken),
                startLPToWithdraw,
                1, 1,
                address(this),
                now + 1
            );
        }

        // swap fromToken to endToken
        address[] memory path = new address[](2);
        path[0] = address(startToken);
        path[1] = address(endToken);
        // ([address(startToken), address(endToken)]);
        uint256 expectedOutput = _getQuote(address(startToken), address(endToken)).mul(startTokenFromStartLP).div(ONE);
        startToken.approve(address(router), startTokenFromStartLP);
        uint[] memory amounts = router.swapExactTokensForTokens(
            startTokenFromStartLP,
            1, //price.mul(startTokenFromStartLP).div(ONE),
            path,
            address(this),
            now + 1
        );
        uint256 endTokenToAddAsLiquidity = amounts[amounts.length - 1];
        {
            uint256 slippage = expectedOutput.sub(endTokenToAddAsLiquidity).mul(ONE).div(expectedOutput);
            require(
                slippage < dripConfig.maxSlippageTolerancePct, ERROR_INTOLERABLE_SLIPPAGE
            );
        }

        // add fromToken and necessary amount of baseToken to endLP
        endToken.approve(address(router), endTokenToAddAsLiquidity);
        baseToken.approve(address(router), baseTokenFromStartLP);
        {
            // optimize base token amount to add as liquidity
            // based on the amount of end tokens we got
            uint256 quote = _getQuote(address(endToken), address(baseToken));
            uint256 NbaseTokenFromStartLP = quote.mul(endTokenToAddAsLiquidity).div(ONE);

            baseTokenFromStartLP = NbaseTokenFromStartLP;
        }
        router.addLiquidity(
            address(endToken),
            address(baseToken),
            endTokenToAddAsLiquidity,
            baseTokenFromStartLP,
            1,
            baseTokenFromStartLP,
            address(this),
            now + 1
        );

        latestDripTime = now;

        emit Drip(price, baseTokenFromStartLP, endTokenToAddAsLiquidity);
    }

    function retrieve(address tokenToRetrieve) public onlyOwner {
        OZIERC20 token = OZIERC20(tokenToRetrieve);
        uint256 myBalance = token.balanceOf(address(this));
        require(token.transfer(owner(), myBalance));
    }

    function _getConversionTWAP() internal view returns (uint256) {
        return twapOracle.consult(address(startToken), ONE, address(endToken));
    }

    function _getConversionPrice() internal view returns (uint256) {
        return _getQuote(address(startToken), address(endToken));
        // (uint112 balance0, uint112 balance1, ) = conversionLP.getReserves();
        // if (address(startToken) == conversionLP.token0()) {
        //     return UniswapV2Library.quote(ONE, balance0, balance1);
        // } else {
        //     return UniswapV2Library.quote(ONE, balance1, balance0);
        // }
    }

    function _getQuote(address tokenA, address tokenB) internal view returns (uint256) {
        IUniswapV2Pair pair = IUniswapV2Pair(
            IUniswapV2Factory(router.factory()).getPair(tokenA, tokenB)
        );

        (uint112 balance0, uint112 balance1, ) = pair.getReserves();
        if (address(tokenA) == pair.token0()) {
            return UniswapV2Library.quote(ONE, balance0, balance1);
        } else {
            return UniswapV2Library.quote(ONE, balance1, balance0);
        }
    }
}
