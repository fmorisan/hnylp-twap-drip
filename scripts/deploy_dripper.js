const BigNumber = require("bignumber.js")
const { artifacts, deployer } = require("hardhat")
const hre = require("hardhat")
const ethers = hre.ethers

const ONE = new BigNumber(10).pow(18)

const AGVE = "0x3a97704a1b25F08aa230ae53B352e2e72ef52843"
const HNY = "0x71850b7E9Ee3f13Ab46d67167341E4bDc905Eef9"
const WETH = "0x6A023CCd1ff6F2045C3309768eAd9E68F978f6e1"
const ROUTER = "0x1C232F01118CB8B424793ae03F870aa7D0ac7f77"
const ORACLE = "0x34C3BB1C12401fFdbC9dcb17fd302A363458a07e"

const IUniswapV2Router02 = artifacts.require("IUniswapV2Router02")
const OracleSimple = artifacts.require("OracleSimple")
const Dripper = artifacts.require("Dripper")

async function main() {
    // Get the Uniswap Factory
    const router = await IUniswapV2Router02.at(ROUTER)
    const factory = await router.factory()

    console.log(`Factory at ${factory}`)

    // Get the sliding window oracle set up
    const twapOracle = await OracleSimple.at(
      ORACLE
    )

    console.log(`Using TWAP oracle at ${twapOracle.address}`)

    await twapOracle.consult(
      HNY,
      ONE
    )

    // We get the contract to deploy
    const dripper = await Dripper.new(
        WETH,
        HNY,
        AGVE,
        ROUTER,
        twapOracle.address,
        {
            transitionTime: new BigNumber(30).times(24 * 60 * 60).toString(),  // 30 days
            dripInterval: new BigNumber(15).times(60).toString(),  // 15 minutes
            maxTWAPDifferencePct: ONE.div(100).times(5).toString(),  // 5%
            maxSlippageTolerancePct: ONE.div(100).times(5).toString(),  // 5%
        }
    );
  
    console.log("Dripper deployed to:", dripper.address);
  }
  
  main()
    .then(() => process.exit(0))
    .catch(error => {
      console.error(error);
      process.exit(1);
    });