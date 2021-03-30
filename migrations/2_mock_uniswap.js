const UniswapV2Factory = artifacts.require('UniswapV2Factory')
const UniswapV2Router02 = artifacts.require('UniswapV2Router02')
const WETH = artifacts.require("WETH")

module.exports = function(deployer, accounts) {
    deployer.deploy(WETH)
    deployer.deploy(UniswapV2Factory, accounts[0])
    deployer.deploy(UniswapV2Router02, UniswapV2Factory.address, WETH.address)
}