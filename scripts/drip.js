const Big = require("bignumber.js")

const Dripper = artifacts.require("Dripper")

async function main() {
    const dripper = await Dripper.at("0x1dB09364bbf90F98152Ac65c67Fe8E2DB48ad416")
    await dripper.drip()
}
  main()
    .then(() => process.exit(0))
    .catch(error => {
      console.error(error);
      process.exit(1);
    });