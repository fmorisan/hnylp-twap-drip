const Big = require("bignumber.js")

const IUniswapV2Factory = artifacts.require('IUniswapV2Factory')
const IUniswapV2Router02 = artifacts.require('IUniswapV2Router02')

const MockSlidingWindowOracle = artifacts.require("MockSlidingWindowOracle")
const ERC20 = artifacts.require("MyERC20")

const Dripper = artifacts.require("Dripper")

const ONE = new Big(10).pow(18)


function now() {
    return Math.floor(new Date() / 1000);
}


module.exports = function(deployer, network, [owner, alice, bob, ...other]) {
    return;
    // deployer.then(async () => {
    //     const router = await IUniswapV2Router02.at("0x1C232F01118CB8B424793ae03F870aa7D0ac7f77")
    //     const factory = await IUniswapV2Factory.at(
    //         await router.factory()
    //     )
    //     console.log(`Router: ${router.address}`)
    //     console.log(`Factory: ${factory.address}`)

    //     const agve = await ERC20.new("Agave", "AGVE")
    //     const hny = await ERC20.new("Honey", "HNY")
    //     const weth = await ERC20.new("Wrapped Ether", "WETH")

    //     console.log(agve.address)
    //     console.log(hny.address)
    //     console.log(weth.address)

    //     await agve.mint(owner, ONE.times(100))
    //     await hny.mint(owner, ONE.times(100))
    //     await weth.mint(owner, ONE.times(100))

    //     await agve.mint(alice, ONE.times(100))
    //     await hny.mint(alice, ONE.times(100))
    //     await weth.mint(alice, ONE.times(100))

    //     await agve.mint(bob, ONE.times(100))
    //     await hny.mint(bob, ONE.times(100))
    //     await weth.mint(bob, ONE.times(100))

    //     await agve.approve(router.address, ONE, {from: alice})
    //     await weth.approve(router.address, ONE, {from: alice})
    //     await router.addLiquidity(
    //         agve.address,
    //         weth.address,
    //         ONE,
    //         ONE,
    //         ONE,
    //         ONE,
    //         alice,
    //         now() + 10,
    //         {from: alice},
    //     ).then(() => console.log("Added AGVE/WETH"))

    //     await agve.approve(router.address, ONE, {from: bob})
    //     await hny.approve(router.address, ONE, {from: bob})
    //     await router.addLiquidity(
    //         agve.address,
    //         hny.address,
    //         ONE,
    //         ONE,
    //         ONE,
    //         ONE,
    //         bob,
    //         now() + 10,
    //         {from: bob}
    //     ).then(() => console.log("Added AGVE/HNY"))

    //     await weth.approve(router.address, ONE.times(4), {from: owner})
    //     await hny.approve(router.address, ONE, {from: owner})
    //     await router.addLiquidity(
    //         weth.address,
    //         hny.address,
    //         ONE.times(4),
    //         ONE,
    //         ONE.times(4),
    //         ONE,
    //         owner,
    //         now() + 10,
    //         {from: owner}
    //     ).then(() => console.log("Added WETH/HNY"))

    //     twapOracle = await deployer.deploy(MockSlidingWindowOracle)
    //     await deployer.deploy(Dripper,
    //         weth.address,
    //         hny.address,
    //         agve.address,
    //         router.address,
    //         twapOracle.address,
    //     )


    //     const dripper = await Dripper.deployed()
    //     const startLP = await ERC20.at(
    //         await factory.getPair(weth.address, agve.address)
    //     )
    //     const startLPBalance = await startLP.balanceOf(alice)
    //     await startLP.approve(dripper.address, startLPBalance, {from: alice})
    //     await dripper.startDrip(
    //         startLPBalance,
    //         3600,
    //         10,
    //         ONE.div(100).times(5), // no more than 5% TWAP difference
    //         {from: alice}
    //     )
    // })
}