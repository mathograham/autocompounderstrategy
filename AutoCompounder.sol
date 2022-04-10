// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;


/* 
The following contract is an autocompounding strategy vault. It is a proof-of-concept, and it is set up to be used in the following way:
 Deposit LP tokens into contract, then contract deposits into chosen staking contract. The specified staking contract 
 produces an ERC20 reward that is collected by the vault and divided in half to be swapped for the two tokens that back the LP token.
 From there, the two tokens are used to produce more LP tokens and the process starts over again. The contract is currently set up to be used with the
 traderjoexyz farm found at this url: https://traderjoexyz.com/farm/0x9A166ae3d4C3C2a7fEbfAe86D16896933f4e10a9-0x188bED1968b795d5c9022F6a0bb5931Ac4c18F00
 This contract is forked from IceQueenStrategy.sol, found here: https://github.com/LucasLeandro1204/smart-contracts-1/blob/master/contracts/IceQueenStrategy.sol
 NOTE: This contract has not been tested in production and there may be errors. Use at your own risk.
*/

/*
Update: pair should be changed. WETH.e - USDC pool closed: no longer producing JOE
*/

import "./SafeMath.sol";
import "./IPair.sol";
import "./IRouter.sol";
import "./IMasterChefJoe.sol";

contract AutoCompoundStrategy {
    using SafeMath for uint;

    //keeps track of the total amount of LP tokens deposited in vault
    uint public totalDeposits;
    //PID is pool ID for WETH.e-USDC in MasterChefJoeV3.
    uint public PID = 61;
    IUniswapV2Router01 public router;
    IUniswapV2Pair public lpTkn;
    IERC20 private token0;
    IERC20 private token1;
    IERC20 public reward;
    IMasterChefJoe public stakingContract;


    //LP token is WETH.e-USDC on TraderJoe
    address public constant _lpTkn = 0x9A166ae3d4C3C2a7fEbfAe86D16896933f4e10a9;
    //token0 is WETH.e on Avalanche
    address public constant _token0 = 0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB;
    //token1 is USDC on Avalanche
    address public constant _token1 = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
    //reward is JOE
    address public constant _reward = 0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd;
    //router is JoeRouter
    address public constant _router = 0x60aE616a2155Ee3d9A68541Ba4544862310933d4;
    //staking in MasterChefJoeV3
    address public constant _stakingContract = 0x188bED1968b795d5c9022F6a0bb5931Ac4c18F00;

    //Owner of Strategy Vault
    address public owner;

    event Deposit(address account, uint amount);
    event Withdraw(address account, uint amount);
    event Recovered(address token, uint amount);
    event Reinvest(uint newTotalDeposits);


    constructor() public {
        owner = msg.sender;
        lpTkn = IUniswapV2Pair(_lpTkn);
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        reward = IERC20(_reward);
        stakingContract = IMasterChefJoe(_stakingContract);
        router = IUniswapV2Router01(_router);
        // setting up approvals so router and staking contract can move tokens from within vault contract
        token0.approve(_router, uint(-1));
        token1.approve(_router, uint(-1));
        reward.approve(_router, uint(-1));
        lpTkn.approve(_stakingContract, uint(-1));

        
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    //name of strategy
    function getName() external pure returns (string memory) {
        return "WormHole";
    }

    //deposit lptokens into contract
    function deposit(uint amount) external onlyOwner {
        _deposit(amount);
    }

    function _deposit(uint amount) internal {
        //approval for this 'transferFrom' comes externally from user
        require(lpTkn.transferFrom(msg.sender, address(this), amount), "transferFrom failed");
        _stakeLp(amount);
        totalDeposits = totalDeposits.add(amount);
        emit Deposit(msg.sender, amount);
    }

    //withdraw amount is lptoken amount
    function withdraw(uint amount) external onlyOwner {
        _withdraw(amount);
    }

    function _withdraw(uint amount) internal {
        require(amount > 0, "amount too low");
        //withdraw from stakingContract does not require approval, vault is user of the stakingContract
        stakingContract.withdraw(PID, amount);
        //transfer does not require approval
        require(lpTkn.transfer(msg.sender, amount), "transfer failed");
        totalDeposits = totalDeposits.sub(amount);
        emit Withdraw(msg.sender, amount);
    }


    function pendingRewardAmt() public view returns (uint) {
        //references the staking Contract and finds the pending rewards for the caller. Returns amount.
        //function name in stakingContract will depend on contract code.
        (uint pendingReward,,,)= stakingContract.pendingTokens(PID, address(this));
        uint contractBalance = reward.balanceOf(address(this));
        return pendingReward.add(contractBalance);
    }

    function _convertRewardToLp(uint rewardAmt) internal returns (uint) {
        uint swapAmt = rewardAmt.div(2);
        //make path (named path0) from Joe to WETH.e
        address[] memory path0 = new address[](2);  
        path0[0] = _reward;
        path0[1] = _token0;
        uint[] memory expectedTkn0Amts = router.getAmountsOut(swapAmt, path0);
        uint expectedTkn0Amt = expectedTkn0Amts[expectedTkn0Amts.length-1];
        uint amountTkn0OutMin = expectedTkn0Amt.mul(95).div(100);
        //swap function: swap 1/2 of Joe for WETH.e
        //approval given to router for reward in constructor
        router.swapExactTokensForTokens(swapAmt, amountTkn0OutMin, path0, address(this), block.timestamp);

        //make path (named path1) from Joe to USDC
        address[] memory path1 = new address[](2);  
        path1[0] = _reward;
        path1[1] = _token1;
        uint[] memory expectedTkn1Amts = router.getAmountsOut(swapAmt, path1);
        uint expectedTkn1Amt = expectedTkn1Amts[expectedTkn1Amts.length-1];
        uint amountTkn1OutMin = expectedTkn1Amt.mul(95).div(100);
        //swap function: swap 1/2 of Joe for USDC
        //approval given to router for reward in constructor
        router.swapExactTokensForTokens(swapAmt, amountTkn1OutMin, path1, address(this), block.timestamp);


        //approval given to router for token0 and token1 in constructor
        (,,uint liquidity) = router.addLiquidity(
        _token0, _token1,
        amountTkn0OutMin, amountTkn1OutMin,
        0, 0,
        address(this),
        block.timestamp
        );

        return liquidity;

    }

    function _stakeLp(uint amount) internal {
        require(amount > 0, "amount too low");
        //vault contract gives approval to stakingContract for deposit in constructor
        stakingContract.deposit(PID, amount);
    }

    function reinvest() external onlyOwner {
        uint unclaimedRewards = pendingRewardAmt();
        //can eventually put a require in that makes sure unclaimed rewards are certain amount before reinvested
        uint lpTokenAmt = _convertRewardToLp(unclaimedRewards);
        _stakeLp(lpTokenAmt);
        totalDeposits = totalDeposits.add(lpTokenAmt);
        emit Reinvest(totalDeposits);
    }

    function emergencyWithdraw() external onlyOwner {
        stakingContract.emergencyWithdraw();
        totalDeposits = 0;
    }

    function recoverERC20(address tokenAddress, uint tokenAmount) external onlyOwner {
        require(tokenAmount > 0, "amount too low");
        IERC20(tokenAddress).transfer(msg.sender, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

}
