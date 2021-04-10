const Big = require("bignumber.js")
const truffleAssert = require("truffle-assertions")

const IUniswapV2Factory = artifacts.require('IUniswapV2Factory')
const IUniswapV2Router02 = artifacts.require('IUniswapV2Router02')
const IUniswapV2Pair = artifacts.require('IUniswapV2Pair')

const MockSlidingWindowOracle = artifacts.require("MockSlidingWindowOracle")
const ERC20 = artifacts.require("MyERC20")

const Dripper = artifacts.require("Dripper")

const ONE = new Big(10).pow(18)

function now() {
  return Math.floor(new Date() / 1000);
}

contract("Dripper", ([owner, alice, ...others]) => {
  beforeEach(async () => {
    this.router = await IUniswapV2Router02.at("0x1C232F01118CB8B424793ae03F870aa7D0ac7f77")
    this.factory = await IUniswapV2Factory.at(
      await this.router.factory()
    )

    this.agve = await ERC20.new("Agave", "AGVE")
    this.hny = await ERC20.new("Honey", "HNY")
    this.weth = await ERC20.new("Wrapped Ether", "WETH")

    await this.agve.mint(owner, ONE.times(100000))
    await this.weth.mint(owner, ONE.times(100000))
    await this.hny.mint(owner, ONE.times(100000))

    await this.agve.approve(
      this.router.address,
      ONE.times(100000)
    )
    await this.weth.approve(
      this.router.address,
      ONE.times(100000)
    )
    await this.hny.approve(
      this.router.address,
      ONE.times(100000)
    )

    await this.router.addLiquidity(
      this.agve.address,
      this.weth.address,
      ONE.times(3000),
      ONE.times(1000),
      ONE.times(3000),
      ONE.times(1000),
      owner,
      now() + 10,
      {from: owner},
    )

    await this.router.addLiquidity(
      this.weth.address,
      this.hny.address,
      ONE.times(3000),
      ONE.times(1000),
      ONE.times(3000),
      ONE.times(1000),
      owner,
      now() + 10,
      {from: owner},
    )

    await this.router.addLiquidity(
      this.agve.address,
      this.hny.address,
      ONE.times(3000),
      ONE.times(3000),
      ONE.times(3000),
      ONE.times(3000),
      owner,
      now() + 10,
      {from: owner},
    )

    this.startLP = await IUniswapV2Pair.at(
      await this.factory.getPair(this.agve.address, this.weth.address)
    )
    this.conversionLP = await IUniswapV2Pair.at(
      await this.factory.getPair(this.hny.address, this.weth.address)
    )
    this.endLP = await IUniswapV2Pair.at(
      await this.factory.getPair(this.agve.address, this.weth.address)
    )

    this.twapOracle = await MockSlidingWindowOracle.new()

    // Set twap oracle to be the actual price, for now.
    const startLPReserves = await this.startLP.getReserves()
    var start_reserve_weth, start_reserve_agve;
    if (this.startLP.token0() == this.agve.address) {
      start_reserve_agve = startLPReserves.reserve0
      start_reserve_weth = startLPReserves.reserve1
    } else {
      start_reserve_agve = startLPReserves.reserve1
      start_reserve_weth = startLPReserves.reserve0
    }
    const startPriceAGVE = await this.router.quote(ONE, start_reserve_agve, start_reserve_weth)
    await this.twapOracle.setPrice(
      this.agve.address, this.weth.address, startPriceAGVE
    )

    const conversionLPReserves = await this.conversionLP.getReserves()
    var conversion_reserve_weth, conversion_reserve_hny
    if (this.conversionLP.token0() == this.weth.address) {
      conversion_reserve_weth = conversionLPReserves.reserve0
      conversion_reserve_hny = conversionLPReserves.reserve1
    } else {
      conversion_reserve_weth = conversionLPReserves.reserve1
      conversion_reserve_hny = conversionLPReserves.reserve0
    }
    const conversionPriceWETH = await this.router.quote(ONE, conversion_reserve_weth, conversion_reserve_hny)
    await this.twapOracle.setPrice(
      this.weth.address, this.hny.address, conversionPriceWETH
    )

    const endLPReserves = await this.endLP.getReserves()
    var end_reserve_hny, end_reserve_agve;
    if (this.endLP.token0() == this.agve.address) {
      end_reserve_agve = endLPReserves.reserve0
      end_reserve_hny = endLPReserves.reserve1
    } else {
      end_reserve_agve = endLPReserves.reserve1
      end_reserve_hny = endLPReserves.reserve0
    }
    const endPriceHNY = await this.router.quote(ONE, end_reserve_hny, end_reserve_agve)
    await this.twapOracle.setPrice(
      this.hny.address, this.agve.address, endPriceHNY
    )

    /*
     * Dripper params:
     * - startToken:    WETH
     * - endToken:      HNY
     * - baseToken:     AGVE
     * - router:        Router
     * - twapOracle:    MockSlidingWindowOracle
     */
    this.dripper = await Dripper.new(
      this.weth.address,
      this.hny.address,
      this.agve.address,
      this.router.address,
      this.twapOracle.address
    )

  })

  it("should be initially configured on deployment", async () => {
    assert(
      (await this.dripper.startToken()) == this.weth.address, "Start token not set correctly"
    )
    assert(
      (await this.dripper.endToken()) == this.hny.address, "End token not set correctly"
    )
    assert(
      (await this.dripper.baseToken()) == this.agve.address, "Base token not set correctly"
    )
    assert(
      (await this.dripper.router()) == this.router.address, "Router not set correctly"
    )
    assert(
      (await this.dripper.twapOracle()) == this.twapOracle.address, "TWAP Oracle not set correctly"
    )
  })

  it("should be able to be configured to drip once", async () => {
    const startLPBalance = await this.startLP.balanceOf(owner)
    await this.startLP.approve(
      this.dripper.address,
      startLPBalance
    )
    await truffleAssert.passes(
      this.dripper.startDrip(
        startLPBalance,
        new Big(1),
        new Big(60),
        ONE.div(100).times(2),
        ONE.div(100).times(2)
      )
    )

    await truffleAssert.reverts(
      this.dripper.startDrip(
        startLPBalance,
        new Big(1),
        new Big(60),
        ONE.div(100).times(2),
        ONE.div(100).times(2)
      )
    )
  })

  it("should drip whenever the price doesn't deviate too far from the TWAP", async () => {
    const startLPBalance = await this.startLP.balanceOf(owner)
    await this.startLP.approve(
      this.dripper.address,
      startLPBalance
    )
    await truffleAssert.passes(
      this.dripper.startDrip(
        startLPBalance,
        new Big(3600),
        new Big(60),
        ONE.div(100).times(2),
        ONE.div(100).times(2)
      )
    )

    // Drip test steps
    // Set up fake twap oracle
    const initialAGVEBalance = await this.agve.balanceOf(this.dripper.address)
    const initialWETHBalance = await this.weth.balanceOf(this.dripper.address)
    const initialHNYBalance = await this.hny.balanceOf(this.dripper.address)
    await truffleAssert.passes(
      this.dripper.drip()
    )
    const postDripAGVEBalance = await this.agve.balanceOf(this.dripper.address)
    const postDripWETHBalance = await this.weth.balanceOf(this.dripper.address)
    const postDripHNYBalance = await this.hny.balanceOf(this.dripper.address)

    assert(
      initialAGVEBalance.lte(postDripAGVEBalance), "AGVE Balance should remain equal or increase"
    )

    assert(
      initialWETHBalance.eq(postDripWETHBalance), "WETH Balance should not change overall"
    )

    assert(
      initialHNYBalance.eq(postDripHNYBalance), "HNY Balance should not change overall"
    )
  })

  it("should not drip if the current price has deviated too far from the reported TWAP", async () => {
    const startLPBalance = await this.startLP.balanceOf(owner)
    await this.startLP.approve(
      this.dripper.address,
      startLPBalance
    )
    await truffleAssert.passes(
      this.dripper.startDrip(
        startLPBalance,
        new Big(3600),
        new Big(60),
        ONE.div(100).times(2),
        ONE.div(100).times(2)
      )
    )

    this.twapOracle.setPrice(
      this.weth.address, this.hny.address, ONE
    )

    await truffleAssert.fails(
      this.dripper.drip()
    )
  })

  it("should not drip if the conversion pool has low liquidity => high slippage", async () => {
    const startLPBalance = await this.startLP.balanceOf(owner)
    await this.startLP.approve(
      this.dripper.address,
      startLPBalance
    )
    await truffleAssert.passes(
      this.dripper.startDrip(
        startLPBalance,
        new Big(3600),
        new Big(60),
        ONE.div(100).times(2),
        ONE.div(100).times(2)
      )
    )

    // remove 99% of the WETH/HNY liquidity to force a high slippage
    const conversionLPBalance = new Big(await this.conversionLP.balanceOf(owner))
    const clp = conversionLPBalance.div(new Big(100)).times(new Big(99))
    await this.conversionLP.approve(this.router.address, conversionLPBalance)
    await this.router.removeLiquidity(
      this.weth.address,
      this.hny.address,
      clp.toFixed(0),
      ONE,
      ONE,
      owner,
      now() + 10
    )

    await truffleAssert.fails(
      this.dripper.drip()
    )
  })

  it("should send back tokens to the owner if retrieve function is called", async () => {
    await this.hny.transfer(this.dripper.address, ONE)
    const hnybalanceBefore = await this.hny.balanceOf(this.dripper.address)

    await truffleAssert.passes(
      this.dripper.retrieve(this.hny.address)
    )
    const hnybalance = await this.hny.balanceOf(this.dripper.address)
    assert(new Big(hnybalance).eq(new Big(0)), `Balance should be zero, but is ${hnybalance.toString()}`)
  })
})
