/**
 * @type import('hardhat/config').HardhatUserConfig
 */
require('@nomiclabs/hardhat-truffle5')

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
        url: 'https://xdai.1hive.org',
      }
    }
  },
  paths: {
    sources: './contracts',
    tests: './test',
    cache: './cache',
  },
  mocha: {
    timeout: 20000
  }
};
