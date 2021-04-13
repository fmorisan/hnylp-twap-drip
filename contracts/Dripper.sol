pragma experimental ABIEncoderV2;
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

import "hardhat/console.sol";


contract Dripper is Ownable {
    using OZSafeMath for uint256;

    struct DripParams {
        uint transitionTime;
        uint dripInterval;
        uint maxTWAPDifferencePct;
        uint maxSlippageTolerancePct;
        uint amountToDrip;
    }

    /**
     * startTime: the starting timestamp of the drip process
     * transitionTime: the total time the drip process will run for
     * dripInterval: the minimum time between drip calls which will be enforced by the contract
     * maxTWAPDifferencePct: the maximum twap difference tolerance, expressed as a percentage where 1e18 represents 100%
     * maxSlippageTolerancePct the maximum slippage tolerance, expressed as a percentage where 1e18 represents 100%
     * amountToDrip: the total amount of starting LP tokens that the drip function will consume
     */
    struct DripConfig {
        uint startTime;
        uint transitionTime;
        uint dripInterval;
        uint maxTWAPDifferencePct;
        uint maxSlippageTolerancePct;
        uint amountToDrip;
    }

    DripConfig public dripConfig;
    uint256 public latestDripTime;

    string public constant ERROR_FAR_FROM_TWAP = "Dripper: Converter LP price is too far from TWAP.";
    string public constant ERROR_DRIP_INTERVAL = "Dripper: Drip interval has not passed.";
    string public constant ERROR_ALREADY_CONFIGURED = "Dripper: Already configured.";
    string public constant ERROR_INTOLERABLE_SLIPPAGE = "Dripper: Slippage exceeds configured limit.";

    uint256 private constant ONE = 10**18;

    IUniswapV2Pair public startLP; // WETH-AGVE
    IUniswapV2Pair public endLP; // HNY-AGVE
    IUniswapV2Pair public conversionLP; // HNY-WETH
    
    IUniswapV2Router02 public router;
    
    OZIERC20 public startToken; // WETH
    OZIERC20 public endToken; // HNY
    OZIERC20 public baseToken; // AGVE

    IOracle public twapOracle;

    address public holder;

    event Drip(uint256 price, uint256 baseTokenAdded, uint256 endTokenAdded);

    /**
     * @notice Configure essential drip parameters, and start the timer.
     * @dev Sets up the drip parameters, and starts the drip counter.
     * This function is in charge of setting up who the holder of
     * the tokens is. In case the LP token holder is whoever deployed
     * the contract, you should set the deployer's address as the holder.
     * @param _baseToken the token that is shared between thet starting LP and the end LP
     * @param _startToken the starting LP specific token
     * @param _endToken the ending LP specific token
     * @param _router the address of the Uniswap Router that knows the pools we're going to interact with
     * @param _twapOracle the TWAP oracle that keeps track of LP states
     * @param _tokenHolder the address that holds the LP tokens we will interact with
     * @param _dripConfig the configuration parameters for the drippping process
     */
    constructor(
        address _startToken,
        address _endToken,
        address _baseToken,
        address payable _router,
        address _twapOracle,
        address _tokenHolder,
        DripParams memory _dripConfig
    ) public Ownable() {
        router = IUniswapV2Router02(_router);
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());

        startToken = OZIERC20(_startToken);
        endToken = OZIERC20(_endToken);
        baseToken = OZIERC20(_baseToken);

        startLP = IUniswapV2Pair(factory.getPair(_startToken, _baseToken));
        endLP = IUniswapV2Pair(factory.getPair(_endToken, _baseToken));
        conversionLP = IUniswapV2Pair(factory.getPair(_startToken, _endToken));

        twapOracle = IOracle(_twapOracle);

        dripConfig = DripConfig(
            now,
            _dripConfig.transitionTime,
            _dripConfig.dripInterval,
            _dripConfig.maxTWAPDifferencePct,
            _dripConfig.maxSlippageTolerancePct,
            _dripConfig.amountToDrip
        );

        holder = _tokenHolder;
    }

    /**
     * @notice Execute a drip.
     * @dev This function does the dripping of value from a LP into another LP
     * It should check that the price has not deviated too much from TWAP
     * and that the swap slippage in the conversion LP is acceptable.
     * Note that it is public since it doesn't use msg.sender - and it also
     * is time-capped so that it can't be successfully called before the 
     * dripInterval passes.
     */
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
            uint256 timeSinceLastDrip = block.timestamp.sub(
                latestDripTime < dripConfig.startTime ?
                    dripConfig.startTime : latestDripTime
            );
            uint256 startLPToWithdraw = dripConfig.amountToDrip.mul(
                    timeSinceLastDrip.mul(ONE).div(dripConfig.transitionTime)
                ).div(ONE);

            // Ingest tokens on drip() call
            require(
                startLP.transferFrom(holder, address(this), startLPToWithdraw)
            );

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

        {
            // optimize token amounts to add as liquidity
            // based on the amount tokens we've got
            uint256 quote = _getQuote(address(endToken), address(baseToken));
            uint256 optimizedBaseTokenAmount = quote.mul(endTokenToAddAsLiquidity).div(ONE);
            uint256 optimizedEndTokenAmount = ONE.div(quote).mul(baseTokenFromStartLP);

            // optimize one side, if not, optimize the other.
            if (optimizedBaseTokenAmount <= baseTokenFromStartLP){
                baseTokenFromStartLP = optimizedBaseTokenAmount;
            } else if (optimizedEndTokenAmount <= endTokenToAddAsLiquidity){
                endTokenToAddAsLiquidity = optimizedEndTokenAmount;
            }
        }

        // add fromToken and necessary amount of baseToken to endLP
        endToken.approve(address(router), endTokenToAddAsLiquidity);
        baseToken.approve(address(router), baseTokenFromStartLP);

        // actually add the liquidity
        router.addLiquidity(
            address(endToken),
            address(baseToken),
            endTokenToAddAsLiquidity,
            baseTokenFromStartLP,
            1,
            baseTokenFromStartLP,
            holder,
            now + 1
        );

        latestDripTime = now;

        emit Drip(price, baseTokenFromStartLP, endTokenToAddAsLiquidity);
    }

    /**
     * @notice Retrieve this contract's balance of tokenToRetrieve
     * @dev Helper method to retrieve stuck tokens. Should only be called once the drip is over.
     * @param tokenToRetrieve The address for the token whose balance you want to retrieve.
     */
    function retrieve(address tokenToRetrieve) public onlyOwner {
        OZIERC20 token = OZIERC20(tokenToRetrieve);
        uint256 myBalance = token.balanceOf(address(this));
        require(token.transfer(
                holder==address(0)?
                    owner() : holder,
                myBalance
            )
        );
    }

    /**
     * @dev Helper method to consult the current TWAP.
     */
    function _getConversionTWAP() internal view returns (uint256) {
        return twapOracle.consult(address(startToken), ONE, address(endToken));
    }

    /**
     * @dev Helper method to get the price between startToken and endToken.
     */
    function _getConversionPrice() internal view returns (uint256) {
        return _getQuote(address(startToken), address(endToken));
    }

    /**
     * @notice Gets a quote for the price of tokenB in terms of tokenA.
     * i.e. if 1 TKA = 3 TKB then getQuote(TKA, TKB) = 0.3333...
     * Results expressed with 1e18 being 1.
     */
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
