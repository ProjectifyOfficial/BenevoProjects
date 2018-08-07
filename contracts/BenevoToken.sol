pragma solidity ^0.4.19;

import "node_modules/openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

// Inspired by 0xBitcoin Token and EIP 918 Mineable Token Standard

contract ERC20Interface {
    function totalSupply() public view returns (uint);
    function balanceOf(address tokenOwner) public view returns (uint balance);
    function allowance(address tokenOwner, address spender) public view returns (uint remaining);
    function transfer(address to, uint tokens) public returns (bool success);
    function approve(address spender, uint tokens) public returns (bool success);
    function transferFrom(address from, address to, uint tokens) public returns (bool success);
    event Transfer(address indexed from, address indexed to, uint tokens);
    event Approval(address indexed tokenOwner, address indexed spender, uint tokens);
}

library ExtendedMath {
    //return the smaller of the two inputs (a or b)
    function limitLessThan(uint a, uint b) internal pure returns (uint c) {
        if(a > b) return b;
        return a;
    }
}

contract ApproveAndCallFallBack {
    function receiveApproval(address from, uint256 tokens, address token, bytes data) public;
}
/*
//already included in Owned OpenZeppelin
contract Owned {
    address public owner;
    address public newOwner;
    event OwnershipTransferred(address indexed _from, address indexed _to);

    constructor() public {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function transferOwnership(address _newOwner) public onlyOwner {
        newOwner = _newOwner;
    }

    function acceptOwnership() public {
        require(msg.sender == newOwner);
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
        newOwner = address(0);
    }
}
*/

contract _BenevoToken is ERC20Interface, Ownable {
    using SafeMath for uint;
    using ExtendedMath for uint;
    string public symbol;
    string public  name;
    uint8 public decimals;
    uint public _totalSupply;
    uint public latestDifficultyPeriodStarted;
    uint public epochCount;//number of 'blocks' mined
    uint public _BLOCKS_PER_READJUSTMENT = 1024;
    //Larger the target, easier to solve the block
    uint public _MINIMUM_TARGET = 2**16;
    uint public _MAXIMUM_TARGET = 2**224;
    uint public miningTarget;
    bytes32 public challengeNumber;   //generate a new one when a new reward is minted
    uint public rewardEra;
    uint public maxSupplyForEra;
    address public lastRewardTo;
    uint public lastRewardAmount;
    uint public lastRewardEthBlockNumber;
    bool locked = false;
    mapping(bytes32 => bytes32) solutionForChallenge;
    uint public tokensMinted;
    mapping(address => uint) balances;
    mapping(address => mapping(address => uint)) allowed;
    event Mint(address indexed from, uint reward_amount, uint epochCount, bytes32 newChallengeNumber);

    
    constructor() public onlyOwner {
        symbol = "BNV";
        name = "BenevoToken";
        decimals = 8;
        //population of the world on Aug 2018 (7.2 billion) divided by 1000
        _totalSupply = 7200000 * 10**uint(decimals);
        if(locked) revert("must not be locked");
        locked = true;
        //All BenevoToken must be mined publicly. No ICO or pre-mine
        tokensMinted = 0;
        rewardEra = 0;
        maxSupplyForEra = _totalSupply.div(2);
        miningTarget = _MAXIMUM_TARGET;
        latestDifficultyPeriodStarted = block.number;
        //_startNewMiningEpoch();
    }

    function mint(uint256 nonce, bytes32 challenge_digest) public returns (bool success) {
        //the PoW must contain work that includes a recent ethereum block hash (challenge number) 
        //and the msg.sender's address to prevent MITM attacks
        bytes32 digest = keccak256(challengeNumber, msg.sender, nonce);
        if (digest != challenge_digest) revert("challenge digest must match the expected");
        if(uint256(digest) > miningTarget) revert("digest must be smaller than target");
        //only allow one reward for each challenge
        bytes32 solution = solutionForChallenge[challengeNumber];
        solutionForChallenge[challengeNumber] = digest;
        if(solution != 0x0) revert("Prevent awarding same answer twice");
        uint reward_amount = getMiningReward();
        balances[msg.sender] = balances[msg.sender].add(reward_amount);
        tokensMinted = tokensMinted.add(reward_amount);
        //Cannot mint more tokens than there are
        assert(tokensMinted <= maxSupplyForEra);

        //set readonly diagnostics data
        lastRewardTo = msg.sender;
        lastRewardAmount = reward_amount;
        lastRewardEthBlockNumber = block.number;
        _startNewMiningEpoch();
        emit Mint(msg.sender, reward_amount, epochCount, challengeNumber);
        return true;
    }

    function _startNewMiningEpoch() internal {
      //if max supply for the era will be exceeded next reward round then enter the new era before that happens
      //40 is the final reward era, almost all tokens minted
      //once the final era is reached, more tokens will not be given out because the assert function
        if( tokensMinted.add(getMiningReward()) > maxSupplyForEra && rewardEra < 39) {
            rewardEra = rewardEra + 1;
        }
      //set the next minted supply at which the era will change
      // total supply is 720000000000000  because of 8 decimal places
        maxSupplyForEra = _totalSupply - _totalSupply.div(2**(rewardEra + 1));
        epochCount = epochCount.add(1);
        //every so often, readjust difficulty. Dont readjust when deploying
        if(epochCount % _BLOCKS_PER_READJUSTMENT == 0) {
            _reAdjustDifficulty();
        }
      //make the latest ethereum block hash a part of the next challenge for PoW to prevent pre-mining future blocks
      //do this last since this is a protection mechanism in the mint() function
        challengeNumber = block.blockhash(block.number - 1);
    }

    //https://en.bitcoin.it/wiki/Difficulty#What_is_the_formula_for_difficulty.3F
    //as of 2017 the bitcoin difficulty was up to 17 zeroes, it was only 8 in the early days

    //readjust the target by 5 percent
    function _reAdjustDifficulty() internal {
        uint ethBlocksSinceLastDifficultyPeriod = block.number - latestDifficultyPeriodStarted;
        //assume 360 ethereum blocks per hour
        //we want miners to spend 10 minutes to mine each 'block', about 60 ethereum blocks = one 0xbitcoin epoch
        uint epochsMined = _BLOCKS_PER_READJUSTMENT; //256
        uint targetEthBlocksPerDiffPeriod = epochsMined * 60; //should be 60 times slower than ethereum

        //if there were less eth blocks passed in time than expected
        if( ethBlocksSinceLastDifficultyPeriod < targetEthBlocksPerDiffPeriod )
        {
            uint excess_block_pct = (targetEthBlocksPerDiffPeriod.mul(100)).div( ethBlocksSinceLastDifficultyPeriod );
            uint excess_block_pct_extra = excess_block_pct.sub(100).limitLessThan(1000);
            // If there were 5% more blocks mined than expected then this is 5.  If there were 100% more blocks mined than expected then this is 100.
            //make it harder
            miningTarget = miningTarget.sub(miningTarget.div(2000).mul(excess_block_pct_extra));   //by up to 50 %
        }else{
            uint shortage_block_pct = (ethBlocksSinceLastDifficultyPeriod.mul(100)).div( targetEthBlocksPerDiffPeriod );
            uint shortage_block_pct_extra = shortage_block_pct.sub(100).limitLessThan(1000); //always between 0 and 1000
            //make it easier
            miningTarget = miningTarget.add(miningTarget.div(2000).mul(shortage_block_pct_extra));   //by up to 50 %
        }

        latestDifficultyPeriodStarted = block.number;
        if(miningTarget < _MINIMUM_TARGET) {
            miningTarget = _MINIMUM_TARGET;
        }
        if(miningTarget > _MAXIMUM_TARGET) {
            miningTarget = _MAXIMUM_TARGET;
        }
    }


    //this is a recent ethereum block hash, used to prevent pre-mining future blocks
    function getChallengeNumber() public view returns (bytes32) {
        return challengeNumber;
    }

    //the number of zeroes the digest of the PoW solution requires.  Auto adjusts
    function getMiningDifficulty() public view returns (uint) {
        return _MAXIMUM_TARGET.div(miningTarget);
    }

    function getMiningTarget() public view returns (uint) {
        return miningTarget;
    }

    //7.2m coins total
    //reward begins at 50 and is cut in half every reward era (as tokens are mined)
    function getMiningReward() public view returns (uint) {
        //once we get half way thru the coins, only get 25 per block
         //every reward era, the reward amount halves.
        return (50 * 10**uint(decimals) ).div( 2**rewardEra ) ;
    }

    //help debug mining software
    function getMintDigest(uint256 nonce, bytes32 challenge_digest, bytes32 challenge_number) 
    public view returns (bytes32 digesttest) {
        bytes32 digest = keccak256(challenge_number,msg.sender,nonce);
        return digest;
    }

    //help debug mining software
    function checkMintSolution(uint256 nonce, bytes32 challenge_digest, bytes32 challenge_number, uint testTarget) 
    public view returns (bool success) {
        bytes32 digest = keccak256(challenge_number,msg.sender,nonce);
        if(uint256(digest) > testTarget) revert("digest must not be higher than test Target");
        return (digest == challenge_digest);
    }

    function totalSupply() public view returns (uint) {
        return _totalSupply - balances[address(0)];
    }

    // Get the token balance for account `tokenOwner`
    function balanceOf(address tokenOwner) public view returns (uint balance) {
        return balances[tokenOwner];
    }

    // Transfer the balance from token owner's account to `to` account
    // - Owner's account must have sufficient balance to transfer
    // - 0 value transfers are allowed

    function transfer(address to, uint tokens) public returns (bool success) {
        balances[msg.sender] = balances[msg.sender].sub(tokens);
        balances[to] = balances[to].add(tokens);
        emit Transfer(msg.sender, to, tokens);
        return true;
    }

    // Token owner can approve for `spender` to transferFrom(...) `tokens`
    // from the token owner's account
    // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20-token-standard.md
    // recommends that there are no checks for the approval double-spend attack
    // as this should be implemented in user interfaces

    function approve(address spender, uint tokens) public returns (bool success) {
        allowed[msg.sender][spender] = tokens;
        emit Approval(msg.sender, spender, tokens);
        return true;
    }

    // Transfer `tokens` from the `from` account to the `to` account
    // The calling account must already have sufficient tokens approve(...)-d
    // for spending from the `from` account and
    // - From account must have sufficient balance to transfer
    // - Spender must have sufficient allowance to transfer
    // - 0 value transfers are allowed

    function transferFrom(address from, address to, uint tokens) public returns (bool success) {
        balances[from] = balances[from].sub(tokens);
        allowed[from][msg.sender] = allowed[from][msg.sender].sub(tokens);
        balances[to] = balances[to].add(tokens);
        emit Transfer(from, to, tokens);
        return true;
    }

    // Returns the amount of tokens approved by the owner that can be transferred to the spender's account
    function allowance(address tokenOwner, address spender) public view returns (uint remaining) {
        return allowed[tokenOwner][spender];
    }

    // Token owner can approve for `spender` to transferFrom(...) `tokens`
    // from the token owner's account. The `spender` contract function
    // `receiveApproval(...)` is then executed
    function approveAndCall(address spender, uint tokens, bytes data) public returns (bool success) {
        allowed[msg.sender][spender] = tokens;
        emit Approval(msg.sender, spender, tokens);
        ApproveAndCallFallBack(spender).receiveApproval(msg.sender, tokens, this, data);
        return true;
    }

    function () public payable {
        revert("Don't accept ETH");
    }

    // Owner can transfer out any accidentally sent ERC20 tokens
    function transferAnyERC20Token(address tokenAddress, uint tokens) public onlyOwner returns (bool success) {
        return ERC20Interface(tokenAddress).transfer(owner, tokens);
    }
}