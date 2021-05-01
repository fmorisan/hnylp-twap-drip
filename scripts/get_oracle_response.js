const Big = require("bignumber.js")

const AGVE = "0x3a97704a1b25F08aa230ae53B352e2e72ef52843"
const HNY = "0x71850b7E9Ee3f13Ab46d67167341E4bDc905Eef9"
const WETH = "0x6A023CCd1ff6F2045C3309768eAd9E68F978f6e1"
const ROUTER = "0x1C232F01118CB8B424793ae03F870aa7D0ac7f77"
const ORACLE = "0xE993b730154829799D6a4770C62429FdB590b51F"

const IUniswapV2Router02 = artifacts.require("IUniswapV2Router02")
const OracleSimple = artifacts.require("OracleSimple")
const Dripper = artifacts.require("Dripper")
async function main() {
    const oracle = await OracleSimple.at(ORACLE)
    console.log(
        (await oracle.consult(WETH, new Big(10).pow(18))).toString()
    )
    console.log(
        (await oracle.consult(HNY, new Big(10).pow(18))).toString()
    )
    console.log(
      await oracle.price0CumulativeLast()
    )
    console.log(
      await oracle.price1CumulativeLast()
    )
}
  main()
    .then(() => process.exit(0))
    .catch(error => {
      console.error(error);
      process.exit(1);
    });