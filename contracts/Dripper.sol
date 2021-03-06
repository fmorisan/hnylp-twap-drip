pragma experimental ABIEncoderV2;
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 as OZIERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeMath as OZSafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";

import "./OracleSimple.sol";


contract Dripper is Ownable {
    using OZSafeMath for uint256;

    struct DripParams {
        uint transitionTime;
        uint dripInterval;
        uint maxTWAPDifferencePct;
        uint maxSlippageTolerancePct;
    }

    enum DripStatus {
        SET,
        RUNNING,
        DONE
    }

    DripStatus public dripStatus;

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
        uint amountDripped;
    }

    DripConfig public dripConfig;
    uint256 public latestDripTime;

    string public constant ERROR_FAR_FROM_TWAP = "Dripper: Converter LP price is too far from TWAP.";
    string public constant ERROR_DRIP_INTERVAL = "Dripper: Drip interval has not passed.";
    string public constant ERROR_ALREADY_CONFIGURED = "Dripper: Already configured.";
    string public constant ERROR_INTOLERABLE_SLIPPAGE = "Dripper: Slippage exceeds configured limit.";
    string public constant ERROR_DRIP_NOT_RUNNING = "Dripper: Drip process is not currently runnning.";
    string public constant ERROR_DRIP_NOT_DONE = "Dripper: Drip process has not ended.";
    

    uint256 private constant ONE = 10**18;

    IUniswapV2Pair public startLP; // WETH-AGVE
    IUniswapV2Pair public endLP; // HNY-AGVE
    IUniswapV2Pair public conversionLP; // HNY-WETH
    
    IUniswapV2Router02 public router;
    
    OZIERC20 public startToken; // WETH
    OZIERC20 public endToken; // HNY
    OZIERC20 public baseToken; // AGVE

    OracleSimple public twapOracle;

    address public holder;

    event Drip(uint256 price, uint256 baseTokenAdded, uint256 endTokenAdded);
    event DripEnded();

    event TokenRetrieved(address token, uint256 balance);

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
     * @param _dripConfig the configuration parameters for the drippping process
     */
    constructor(
        address _startToken,
        address _endToken,
        address _baseToken,
        address payable _router,
        address _twapOracle,
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

        twapOracle = OracleSimple(_twapOracle);

        dripConfig = DripConfig(
            block.timestamp,
            _dripConfig.transitionTime,
            _dripConfig.dripInterval,
            _dripConfig.maxTWAPDifferencePct,
            _dripConfig.maxSlippageTolerancePct,
            0, // will be set up when startDripping is called
            0
        );

        dripStatus = DripStatus.SET;
    }

    /**
     * @notice start the dripping process. This function is separate since it might take 
     * a long while to set any token approval after contract deplyment.
     * @param _tokenHolder the address that holds the LP tokens we will interact with
     * @param _amountToDrip the amount of start LP tokens whose value we will drip
     */
    function startDripping(address _tokenHolder, uint256 _amountToDrip) public onlyOwner {
        require(dripStatus == DripStatus.SET, "Cannot start twice.");
        holder = _tokenHolder;
        dripConfig.amountToDrip = _amountToDrip;
        dripConfig.startTime = block.timestamp;
        dripStatus = DripStatus.RUNNING;
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
        require(dripStatus == DripStatus.RUNNING, ERROR_DRIP_NOT_RUNNING);
        require(now >= latestDripTime.add(dripConfig.dripInterval), ERROR_DRIP_INTERVAL);

        // check current fromToken -> endToken price doesn't deviate too much from TWAP
        uint256 price = _checkPrice();

        uint256 lpTokensToWithdraw = _calculateDrip();

        // Ingest tokens on drip() call
        require(
            startLP.transferFrom(holder, address(this), lpTokensToWithdraw)
        );

        (uint256 startTokenAmt, uint256 baseTokenAmt) = _withdraw(lpTokensToWithdraw);


        dripConfig.amountDripped = dripConfig.amountDripped.add(lpTokensToWithdraw);

        uint256 endTokenAmt = _swapTokens(startTokenAmt);

        (endTokenAmt, baseTokenAmt) = _optimizeAmounts(
            endTokenAmt, baseTokenAmt
        );

        _addLiquidity(endTokenAmt, baseTokenAmt);

        latestDripTime = now;

        emit Drip(price, baseTokenAmt, endTokenAmt);

        if (dripConfig.amountDripped >= dripConfig.amountToDrip) {
            _endDrip();
        }
    }

    /**
     * @notice Retrieve this contract's balance of tokenToRetrieve
     * @dev Helper method to retrieve stuck tokens. Should only be called once the drip is over.
     * @param tokenToRetrieve The address for the token whose balance you want to retrieve.
     */
    function retrieve(address tokenToRetrieve) public onlyOwner {
        require(dripStatus == DripStatus.DONE, ERROR_DRIP_NOT_DONE);
        OZIERC20 token = OZIERC20(tokenToRetrieve);
        uint256 myBalance = token.balanceOf(address(this));
        if (myBalance > 0) {
            require(token.transfer(
                    holder==address(0)?
                        owner() : holder,
                    myBalance
                )
            );
            emit TokenRetrieved(address(token), myBalance);
        }
    }

    /**
     * @notice End the drip process and retrieve all known tokens.
     */
    function abort() public onlyOwner {
        _endDrip();
        retrieve(address(startLP));
        retrieve(address(endLP));
        retrieve(address(startToken));
        retrieve(address(endToken));
        retrieve(address(baseToken));
    }

    /**
     * @dev Helper method to consult the current TWAP.
     */
    function _getConversionTWAP() internal view returns (uint256 twap) {
        return twapOracle.consult(address(startToken), ONE);
    }

    /**
     * @dev Helper method to get the price between startToken and endToken.
     */
    function _getConversionPrice() internal view returns (uint256 quote) {
        return _getQuote(address(startToken), address(endToken));
    }

    /**
     * @notice Gets a quote for the price of tokenB in terms of tokenA.
     * i.e. if 1 TKA = 3 TKB then getQuote(TKA, TKB) = 0.3333...
     * Results expressed with 1e18 being 1.
     */
    function _getQuote(address tokenA, address tokenB) internal view returns (uint256 quote) {
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

    function _endDrip() internal {
        dripStatus = DripStatus.DONE;
        emit DripEnded();
    }

    /**
     * @notice Checks that the current pool price is not too far from TWAP
     */
    function _checkPrice() internal view returns (uint256 curPrice) {
        uint256 price = _getConversionPrice();
        uint256 twap = _getConversionTWAP();
        require(
            twap.mul(ONE).div(price) < ONE.add(dripConfig.maxTWAPDifferencePct)
            && price.mul(ONE).div(twap) < ONE.add(dripConfig.maxTWAPDifferencePct),
            ERROR_FAR_FROM_TWAP
        );
        return price;
    }

    /**
     * @notice Calculates how much startLP tokens we have to drip right now
     * Clamps the returned value to the remaining drip amount.
     */
    function _calculateDrip() internal view returns (uint256 dripAmt) {
        // calculate how much should be withdrawn
        uint256 timeSinceLastDrip = block.timestamp.sub(
            latestDripTime < dripConfig.startTime ?
                dripConfig.startTime : latestDripTime
        );
        uint256 startLPToWithdraw = dripConfig.amountToDrip.mul(
                timeSinceLastDrip.mul(ONE).div(dripConfig.transitionTime)
            ).div(ONE);

        uint256 remainingDrip = dripConfig.amountToDrip.sub(dripConfig.amountDripped);
        
        if (remainingDrip < startLPToWithdraw) {
            return remainingDrip;
        }

        return startLPToWithdraw;
    }

    /**
     * @notice Swaps `amountIn` start tokens for end tokens
     * @param amountIn the amount of startTokens to swap
     * @return amountOut the output of the swap in endTokens
     */
    function _swapTokens(uint256 amountIn) internal returns (uint256 amountOut) {
        // swap fromToken to endToken
        address[] memory path = new address[](2);
        path[0] = address(startToken);
        path[1] = address(endToken);

        // Calculate minimum expected output, taking slippage into account
        uint256 expectedOutput = _getQuote(address(startToken), address(endToken)).mul(amountIn).div(ONE);
        expectedOutput = expectedOutput.mul(ONE.sub(dripConfig.maxSlippageTolerancePct)).div(ONE);

        startToken.approve(address(router), amountIn);

        uint[] memory amounts = router.swapExactTokensForTokens(
            amountIn,
            1,
            path,
            address(this),
            now + 1
        );

        return amounts[amounts.length.sub(1)];
    }

    /**
     * @notice Optimize token amounts for addition into a liquidity pool
     * @param endAmount initial guess on how much endTokens to add
     * @param baseAmount initial guess on how much baseTokens to add
     * @return optimized endTokenAmount and baseTokenAmount
     */
    function _optimizeAmounts(uint256 endAmount, uint256 baseAmount) internal view returns (uint256, uint256) {
        // optimize token amounts to add as liquidity
        // based on the amount tokens we've got
        uint256 quote = _getQuote(address(endToken), address(baseToken));
        uint256 optimizedBaseTokenAmount = quote.mul(endAmount).div(ONE);
        uint256 optimizedEndTokenAmount = ONE.div(quote).mul(baseAmount);

        // optimize one side, if not, optimize the other.
        if (optimizedBaseTokenAmount <= baseAmount){
            return (endAmount, optimizedBaseTokenAmount);
        } else {
            return (optimizedEndTokenAmount, baseAmount);
        }
    }

    /**
     * @notice Adds liquidity to the endToken/baseToken liquidity pool
     * @param endAmount the amount of endTokens to add
     * @param baseAmount the amount of baseTokens to add
     */
    function _addLiquidity(uint256 endAmount, uint256 baseAmount) internal {
        // add fromToken and necessary amount of baseToken to endLP
        endToken.approve(address(router), endAmount);
        baseToken.approve(address(router), baseAmount);

        // actually add the liquidity
        router.addLiquidity(
            address(endToken),
            address(baseToken),
            endAmount,
            baseAmount,
            1,
            baseAmount,
            holder,
            now + 1
        );
    }

    /**
     * @notice Withdraws some startLP tokens for their locked collateral
     * @param startLPAmount the amount of LP tokens to burn
     * @return (startAmt, baseAmt) the amount of startToken and baseToken retrieved from the LP token burn
     */
    function _withdraw(uint256 startLPAmount) internal returns (uint256, uint256) {
        startLP.approve(address(router), startLPAmount);
        // withdraw it
        return router.removeLiquidity(
            address(startToken),
            address(baseToken),
            startLPAmount,
            1, 1,
            address(this),
            now + 1
        );
    }
}
