# autocompounderstrategy
The contract labeled 'Autocompounder.sol' is an autocompounding strategy vault. It is a proof-of-concept, and it is set up to be used in the following way:
 Deposit LP tokens into the contract; the contract will deposit into the chosen staking contract. For this example, that will be MasterChefJoeV3.
 The specified staking contract produces an ERC20 reward (JOE) that is collected by the vault and divided in half to be swapped for 
 the two tokens that back the LP token, WETH.e and USDC. From there, the two tokens are used to produce more LP tokens and the process starts over again. 
 The contract is currently set up to be used with the traderjoexyz farm found at this url: 
 https://traderjoexyz.com/farm/0x9A166ae3d4C3C2a7fEbfAe86D16896933f4e10a9-0x188bED1968b795d5c9022F6a0bb5931Ac4c18F00
 This contract is forked from IceQueenStrategy.sol, found here: 
 https://github.com/LucasLeandro1204/smart-contracts-1/blob/master/contracts/IceQueenStrategy.sol
 NOTE: This contract has not been tested in production and there may be errors. Use at your own risk.
