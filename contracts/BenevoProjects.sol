pragma solidity ^0.4.24;

import "node_modules/openzeppelin-solidity/contracts/lifecycle/Pausable.sol";
import "node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";
import "contracts/BenevoToken.sol";

/**
 * @title BenevoProjects - Crowd-donation platform with high transparency and low participation barrier

 * @notice
   BenevoProjects use Web Mineable ERC20 BenevoToken for donations.
   Check design_pattern_desicions.md for design pattern details,
   deployed_addresses.txt to access the contract on Rinkby Testnet,
   user_stories.md for user stories.

 * @dev Contract pausable in case of any attacks. please refer to avoiding_common_attacks.md for more security features
*/

/** @dev pausable enables emergency stop */
contract BenevoProjects is Pausable {
    
    /** @dev BenevoProjects uses BenevoToken for donations */
    BenevoToken bnv;

    /** @dev all arithmetic operation in this contract uses Openzeppelin's SafeMath library */
    using SafeMath for uint;
    
    /*** EVENTS ***/
    event NewProject(uint indexed projectId, string indexed name, uint goalAmount, address owner);
    event Donated(address indexed donor, uint projectId, uint amount);
    event Withdraw(address indexed from, address indexed to, uint tokens); 

    /** @notice currentAmount is total amount of token donated. 
                currentBalnace is currentAmount minus tokens the owner already withdrew */
    struct Project {
        uint id;
        string name;
        uint goalAmount;
        uint currentAmount;
        uint currentBalance;
        address ownerAddress;
        address projectAddress;
        bool canWithdraw;
    }
   
    /** @dev Project can be accessed either through the project ID or owner's address */
    mapping (uint => Project) projects;
    mapping (address => Project) owners;

    /** @dev An internal document counter for retrieving the Project with project ID */
    uint public projectsCount = 0;

    constructor () public{
        BenevoToken bnv = new BenevoToken();
    }

    /** @dev Project getter
        @param _id Project id
        @return project's name, goalAmount, currentAmount, currentBalance, ownerAddress, projectAddress, and canWithdraw
    */
    function getProject(uint _id) public view returns (string, uint, uint, uint, address, address, bool){
        Project memory project = projects[_id];
        return (project.name, project.goalAmount, project.currentAmount, project.currentBalance, 
        project.ownerAddress, project.projectAddress, project.canWithdraw);
    }

    /** @dev Create a new project with a BenevoToken contractAccount
        @param _name The name of the project
        @param _goalAmount Goal amount of BenevoToken to be donated
        @return every attribute of the project
    */
    function _createProject(string _name, uint _goalAmount) 
    public whenNotPaused returns(uint, string, uint, uint, uint, address, address){
        projectsCount ++;
        projects[projectsCount] = Project(projectsCount, _name, _goalAmount, 0, 0, msg.sender, address(ripemd160(abi.encodePacked(msg.sender))), false);
        owners[msg.sender] = projects[projectsCount];
        emit NewProject(projectsCount, _name, _goalAmount, msg.sender);
        return (projectsCount, _name, _goalAmount, 0, 0, msg.sender, address(ripemd160(abi.encodePacked(msg.sender))));
    }

    /** @dev Donate BenevoToken to the project
        @param _id The id of the project
        @param amountToDonate Amount of BenevoToken to donate to the project
        @return new currentAmount after donation
    */
    function donate(uint _id, uint amountToDonate) public whenNotPaused returns (uint newBalance){
        // require(_id > 0 && _id <= projectsCount, "not a valid project address");
        BenevoToken bnv = new BenevoToken();
        //prevent Integer Overflow
        require(projects[_id].currentAmount + amountToDonate >= projects[_id].currentAmount, "Project currentAmount IntegerOverflow");
        require(projects[_id].currentBalance + amountToDonate >= projects[_id].currentBalance, "Project amountToDonate IntegerOverflow");
        bnv.transfer(projects[_id].projectAddress, amountToDonate);
        newBalance = projects[_id].currentAmount += amountToDonate;
        projects[_id].currentBalance += amountToDonate; 
        emit Donated(msg.sender, _id, amountToDonate);
        return newBalance;
    }

    /** @dev Release the escrowed donation to the project owner 
        @param _projectId Project ID
        @return whether the function succeeded
    */
    function releaseDonation(uint _projectId) public whenNotPaused returns (bool success){
        Project memory project = projects[_projectId];
        //require(msg.sender != project.ownerAddress, "only non-project owner can call release Donation");
        project.canWithdraw = true;
        return true;
    }

    /** @dev project owner can withdraw all the tokens that were released
        @return updated currentBalance
     */
    function withdrawToken() external returns (uint _currentBalance){
        // require(msg.sender == project.ownerAddress, "only project creator can call withdraw");
        Project memory project = owners[msg.sender];
        //require(project.canWithdraw == true, "donation not released for withdrawal");
        uint withdrawAmount = project.currentBalance;
        //Subtract withdraw amount before releasing token to for best practice
        _currentBalance = project.currentBalance = 0;
        //project.transfer(project.ownerAddress, withdrawAmount);
        return _currentBalance;
    }

    /** @dev Eth payable fallback. When Ethereum is accidentally sent to the contract it is immediately returned.
    */
    function () public payable {
        revert("Don't accept ETH");
    }

    /** @dev kill the contract
    */
    function kill() public onlyOwner {
        selfdestruct(owner);
    }
}
