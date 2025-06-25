// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title InviteManager
 * @dev Invite system management contract
 */
contract InviteManager is Ownable, ReentrancyGuard {
    
    // Invite relationship mappings
    mapping(address => address) public inviter;           // user => inviter
    mapping(address => address[]) public invitees;        // inviter => invitees list
    mapping(address => uint256) public pendingRewards;    // inviter => pending reward amount
    mapping(address => uint256) public totalInvited;      // inviter => total invited count
    mapping(address => uint256) public totalRewards;      // inviter => total reward amount (including claimed)
    mapping(address => uint256) public claimedRewards;    // inviter => claimed reward amount
    mapping(address => string) public inviteCodes;        // user => invite code
    mapping(string => address) public codeToAddress;      // invite code => user address
    mapping(address => bool) public authorizedContracts;  // authorized game contracts
    mapping(uint256 => bool) public gameRewardsReleased;  // game ID => whether rewards are released
    
    uint256 public constant INVITE_REWARD_PERCENT = 2;    // invite reward percentage 2%
    uint256 private nonce = 0;                            // nonce for generating invite codes
    
    // Platform fee related
    address public platformFeeReceiver;                   // platform fee receiver address
    uint256 public totalPlatformFees;                     // accumulated platform fees
    
    // Events
    event InviteCodeGenerated(address indexed user, string inviteCode);
    event InviteRelationEstablished(address indexed inviter, address indexed invitee);
    event InviteRewardAdded(address indexed inviter, address indexed invitee, uint256 amount);
    event InviteRewardClaimed(address indexed inviter, uint256 amount);
    event ContractAuthorized(address indexed contractAddr, bool authorized);
    event GameRewardsReleased(uint256 indexed gameId, uint256 totalRewards, uint256 platformFee);
    event PlatformFeesWithdrawn(address indexed receiver, uint256 amount);
    
    modifier onlyAuthorized() {
        require(authorizedContracts[msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }
    
    constructor() {
        platformFeeReceiver = msg.sender; // Default: set deployer as platform fee receiver
    }
    
    /**
     * @dev Authorize/deauthorize game contract
     */
    function setContractAuthorization(address contractAddr, bool authorized) external onlyOwner {
        authorizedContracts[contractAddr] = authorized;
        emit ContractAuthorized(contractAddr, authorized);
    }
    
    /**
     * @dev Set platform fee receiver address
     */
    function setPlatformFeeReceiver(address _receiver) external onlyOwner {
        require(_receiver != address(0), "Invalid receiver address");
        platformFeeReceiver = _receiver;
    }
    
    /**
     * @dev Generate invite code
     */
    function generateInviteCode() external returns (string memory) {
        require(bytes(inviteCodes[msg.sender]).length == 0, "Invite code already exists");
        
        // Generate unique invite code
        string memory code = _generateUniqueCode(msg.sender);
        
        inviteCodes[msg.sender] = code;
        codeToAddress[code] = msg.sender;
        
        emit InviteCodeGenerated(msg.sender, code);
        return code;
    }
    
    /**
     * @dev Establish invite relationship through invite code
     * @param inviteCode Invite code
     */
    function useInviteCode(string memory inviteCode) external {
        require(bytes(inviteCode).length > 0, "Invalid invite code");
        require(inviter[msg.sender] == address(0), "Already has inviter");
        
        address inviterAddress = codeToAddress[inviteCode];
        require(inviterAddress != address(0), "Invite code does not exist");
        require(inviterAddress != msg.sender, "Cannot invite yourself");
        
        // Establish invite relationship
        inviter[msg.sender] = inviterAddress;
        invitees[inviterAddress].push(msg.sender);
        totalInvited[inviterAddress]++;
        
        emit InviteRelationEstablished(inviterAddress, msg.sender);
    }
    
    /**
     * @dev Accumulate invite reward (called by authorized game contracts)
     * @param inviterAddr Inviter address
     * @param amount Reward amount
     */
    function addPendingReward(address inviterAddr, uint256 amount) external onlyAuthorized {
        require(inviterAddr != address(0), "Invalid inviter address");
        require(amount > 0, "Invalid amount");
        
        pendingRewards[inviterAddr] += amount;
        totalRewards[inviterAddr] += amount;
        
        emit InviteRewardAdded(inviterAddr, msg.sender, amount);
    }
    
    /**
     * @dev Process reward distribution after game ends (called by game contracts)
     * @param gameId Game ID
     * @param actualPlatformFee Actual platform fee (after deducting invite rewards)
     * @param inviters Array of inviter addresses
     * @param inviteAmounts Array of corresponding invite reward amounts
     */
    function processGameRewards(
        uint256 gameId,
        uint256 actualPlatformFee,
        address[] calldata inviters,
        uint256[] calldata inviteAmounts
    ) external payable onlyAuthorized {
        require(!gameRewardsReleased[gameId], "Game rewards already released");
        require(msg.value > 0, "No funds received");
        require(inviters.length == inviteAmounts.length, "Arrays length mismatch");
        
        gameRewardsReleased[gameId] = true;
        
        // Calculate total invite rewards
        uint256 totalInviteRewards = 0;
        for (uint256 i = 0; i < inviteAmounts.length; i++) {
            totalInviteRewards += inviteAmounts[i];
        }
        
        // Verify amount matches: actual platform fee + total invite rewards
        require(msg.value == actualPlatformFee + totalInviteRewards, "Amount mismatch");
        
        // 🎁 Update inviter's pending rewards
        for (uint256 i = 0; i < inviters.length; i++) {
            if (inviteAmounts[i] > 0) {
                pendingRewards[inviters[i]] += inviteAmounts[i];
                totalRewards[inviters[i]] += inviteAmounts[i];
                emit InviteRewardAdded(inviters[i], msg.sender, inviteAmounts[i]);
            }
        }
        
        // Accumulate actual platform fees
        totalPlatformFees += actualPlatformFee;
        
        emit GameRewardsReleased(gameId, totalInviteRewards, actualPlatformFee);
    }
    
    /**
     * @dev Claim invite rewards
     */
    function claimInviteRewards() external nonReentrant {
        uint256 amount = pendingRewards[msg.sender];
        require(amount > 0, "No rewards to claim");
        require(address(this).balance >= amount, "Insufficient contract balance");
        
        pendingRewards[msg.sender] = 0;
        claimedRewards[msg.sender] += amount;
        
        payable(msg.sender).transfer(amount);
        
        emit InviteRewardClaimed(msg.sender, amount);
    }
    
    /**
     * @dev Withdraw platform fees
     */
    function withdrawPlatformFees() external onlyOwner nonReentrant {
        uint256 amount = totalPlatformFees;
        require(amount > 0, "No platform fees to withdraw");
        require(address(this).balance >= amount, "Insufficient balance");
        
        totalPlatformFees = 0;
        payable(platformFeeReceiver).transfer(amount);
        
        emit PlatformFeesWithdrawn(platformFeeReceiver, amount);
    }
    
    /**
     * @dev Deposit funds to contract
     */
    function depositFunds() external payable onlyOwner {
        require(msg.value > 0, "Must send some ETH");
    }
    
    /**
     * @dev Generate unique invite code
     */
    function _generateUniqueCode(address user) internal returns (string memory) {
        nonce++;
        bytes32 hash = keccak256(abi.encodePacked(user, block.timestamp, nonce));
        
        // Convert to hex string and take first 8 characters
        string memory code = _toHexString(uint256(hash), 8);
        
        // If code already exists, recursively generate a new one
        if (codeToAddress[code] != address(0)) {
            return _generateUniqueCode(user);
        }
        
        return code;
    }
    
    /**
     * @dev Convert to hex string
     */
    function _toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length);
        for (uint256 i = 2 * length; i > 0; --i) {
            buffer[i - 1] = _HEX_SYMBOLS[value & 0xf];
            value >>= 4;
        }
        return string(buffer);
    }
    
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";
    
    // Query functions
    function getInviteCode(address user) external view returns (string memory) {
        return inviteCodes[user];
    }
    
    function getInviter(address user) external view returns (address) {
        return inviter[user];
    }
    
    function getInvitees(address user) external view returns (address[] memory) {
        return invitees[user];
    }
    
    /**
     * @dev Get pending rewards
     */
    function getInviteReward(address user) external view returns (uint256) {
        return pendingRewards[user];
    }
    
    function getTotalInvited(address user) external view returns (uint256) {
        return totalInvited[user];
    }
    
    /**
     * @dev Get total reward amount (including claimed)
     */
    function getTotalRewards(address user) external view returns (uint256) {
        return totalRewards[user];
    }
    
    /**
     * @dev Get claimed reward amount
     */
    function getClaimedRewards(address user) external view returns (uint256) {
        return claimedRewards[user];
    }
    
    function getAddressByCode(string memory code) external view returns (address) {
        return codeToAddress[code];
    }
    
    /**
     * @dev Get contract balance
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    /**
     * @dev Get platform fee balance
     */
    function getPlatformFeeBalance() external view returns (uint256) {
        return totalPlatformFees;
    }
    
    /**
     * @dev Check if contract is authorized
     */
    function isContractAuthorized(address contractAddr) external view returns (bool) {
        return authorizedContracts[contractAddr];
    }
    
    /**
     * @dev Get user invite statistics
     */
    function getInviteStats(address user) external view returns (
        uint256 totalInvitedCount,
        uint256 totalRewardsAmount,
        uint256 pendingRewardsAmount,
        uint256 claimedRewardsAmount
    ) {
        return (
            totalInvited[user],
            totalRewards[user],
            pendingRewards[user],
            claimedRewards[user]
        );
    }
    
    /**
     * @dev Emergency withdraw contract balance (owner only)
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");
        payable(owner()).transfer(balance);
    }
    
    /**
     * @dev Receive ETH
     */
    receive() external payable {
        // Allow receiving ETH for paying invite rewards
    }
} 
