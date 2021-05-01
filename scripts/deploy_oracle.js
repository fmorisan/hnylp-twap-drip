const BigNumber = require("bignumber.js")
const { artifacts } = require("hardhat")
const hre = require("hardhat")
const ethers = hre.ethers

const ONE = new BigNumber(10).pow(18)

const ROUTER = "0x1C232F01118CB8B424793ae03F870aa7D0ac7f77"
const HNY = "0x71850b7E9Ee3f13Ab46d67167341E4bDc905Eef9"
const WETH = "0x6A023CCd1ff6F2045C3309768eAd9E68F978f6e1"

const IUniswapV2Router02 = artifacts.require("IUniswapV2Router02")
const OracleSimple = artifacts.require("OracleSimple")

async function main() {
    // Get the Uniswap Factory
    const router = await IUniswapV2Router02.at(ROUTER)
    const factory = await router.factory()

    console.log(`Factory at ${factory}`)

    // Get the sliding window oracle set up
    const twapOracle = await OracleSimple.new(
      factory,
      HNY,
      WETH
    )

    console.log(`Deployed TWAP oracle at ${twapOracle.address}`)
  }
  
  main()
    .then(() => process.exit(0))
    .catch(error => {
      console.error(error);
      process.exit(1);
    });