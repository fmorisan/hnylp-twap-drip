const Big = require("bignumber.js")
const truffleAssert = require("truffle-assertions")

const IUniswapV2Factory = artifacts.require('IUniswapV2Factory')
const IUniswapV2Router02 = artifacts.require('IUniswapV2Router02')

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
        ).then(() => console.log("Added AGVE/WETH"))

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
        ).then(() => console.log("Added WETH/HNY"))

        await this.router.addLiquidity(
            this.agve.address,
            this.hny.address,
            ONE.times(3000),
            ONE.times(1000),
            ONE.times(3000),
            ONE.times(1000),
            owner,
            now() + 10,
            {from: owner},
        ).then(() => console.log("Added AGVE/HNY"))

        this.startLP = await ERC20.at(
            await this.factory.getPair(this.agve.address, this.weth.address)
        )
        this.endLP = await ERC20.at(
            await this.factory.getPair(this.agve.address, this.weth.address)
        )

        this.twapOracle = await MockSlidingWindowOracle.new()
    })

    it("should be initially configured on deployment", async () => {
        /*
         * Dripper params:
         * - startToken:    WETH
         * - endToken:      HNY
         * - baseToken:     AGVE
         * - router:        Router
         * - twapOracle:    MockSlidingWindowOracle
         */
        const dripper = await Dripper.new(
            this.weth.address,
            this.hny.address,
            this.agve.address,
            this.router.address,
            this.twapOracle.address
        )

        assert(
            (await dripper.startToken()) == this.weth.address, "Start token not set correctly"
        )
        assert(
            (await dripper.endtoken()) == this.hny.address, "End token not set correctly"
        )
        assert(
            (await dripper.baseToken()) == this.agve.address, "Base token not set correctly"
        )
        assert(
            (await dripper.router()) == this.router.address, "Router not set correctly"
        )
        assert(
            (await dripper.twapOracle()) == this.twapOracle.address, "TWAP Oracle not set correctly"
        )
    })

    it("should be able to be configured to drip once", async () => {
        const dripper = await Dripper.new(
            this.weth.address,
            this.hny.address,
            this.agve.address,
            this.router.address,
            this.twapOracle.address
        )
        const startLPBalance = await this.startLP.balanceOf(owner)
        await this.startLP.approve(
            dripper.address,
            startLPBalance
        )
        await truffleAssert.passes(
            dripper.setupDrip(
                new Big(1),
                new Big(60),
                new ONE.div(100).mul(2)
            )
        )

        await truffleAssert.reverts(
            dripper.setupDrip(
                new Big(1),
                new Big(60),
                new ONE.div(100).mul(2)
            )
        )
    })
})