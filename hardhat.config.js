/**
 * @type import('hardhat/config').HardhatUserConfig
 */
require('@nomiclabs/hardhat-truffle5')
require('@nomiclabs/hardhat-ethers')
require("hardhat-gas-reporter")
require("hardhat-contract-sizer")
require('dotenv').config()

module.exports = {
  defaultNetwork: "hardhat",
  solidity: {
    version: "0.6.6",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    hardhat: {
      forking: {
        url: 'https://rpc.xdaichain.com',
      }
    },
    xdai: {
      url: 'https://xdai.1hive.org',
      accounts: {
        mnemonic: process.env.MNEMONIC
      }
    },
  },
  paths: {
    sources: './contracts',
    tests: './test',
    cache: './cache',
  },
  contractSizer: {
    runOnCompile: true
  },
  mocha: {
    timeout: 100000
  }
};
