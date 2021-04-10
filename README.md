# TWAP conscious Dripper contract

This repository holds a Dripper contract that can be used to drip funds from one Uniswap-compatible Liquidity Pool into another Liquidity Pool which shares a token with the first one.  
One use case is for it to be used to correct situations in which a sizeable amount of tokens was pushed into a LP by mistake.

## Development setup
Just install the packages required by `package.json` by executing `yarn`.

## Testing
Running `yarn test` should run the test suite. Hardhat will fork the xDai chain to run the tests so be sure to have an active internet connection.

## Usage
This contract should be deployed by whoever controls the LP tokens of which value you want ot drip into the other LP.
Deploy the Dripper contract indicating to it the following addresses and configuration parameters:
```
// Supposing you want to drip from a LP which holds TKA/TKB into a LP that holds TKB/TKC
// your tokens would be:
// startToken: TKA
// baseToken: TKB
// endToken: TKC
// In this case, you want to convert TKA into TKC and use it to put the TKB you had into the other pool

constructor(
    address _startToken,        // TKA
    address _endToken,          // TKC
    address _baseToken,         // TKB
    address payable _router,    // The Uniswap router that knows the pools you want to interact with
    address _twapOracle         // A SlidingWindowTWAPOracle instance that keeps track of the token prices
) public Ownable() {
```

Then, call the `startDrip()` function which will take care of setting up the drip process.
```
function startDrip(
    uint256 amount,                     // The amount of TKA/TKB pool tokens that you want to consume
    uint256 _transitionTime,            // The time that this drip event has to take
    uint256 _dripSpacing,               // The minimum time between drip() calls
    uint256 _twapDeviationTolerance,    // The maximum price deviation percentage from TWAP
                                        // for the TKA/TKC pool (where 1e18 is 100%)
    uint256 _slippageTolerance          // The maximum tolerable slippage percentage (where 1e18 is 100%)
) public onlyOwner
```

After that, you should be able to start calling the `drip()` function every `_dripSpacing` seconds, and it should automatically drip the value from one LP into another one.
> Note that this call will consume some TKA/TKB pool tokens in order to actually execute the drip. Thus, it is required that an approval for the whole amount is set before starting the drip.
> Excess tokens resulting from price differences are kept in the contract. When required, the `retrieve(address token)` function can be used to retrieve the any token's balance from the contract.