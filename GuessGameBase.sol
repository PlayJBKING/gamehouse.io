// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

// Invite manager interface
interface IInviteManager {
    function getInviter(address user) external view returns (address);
    function addPendingReward(address inviter, uint256 amount) external;
    function processGameRewards(
        uint256 gameId,
        uint256 platformFee,
        address[] calldata inviters,
        uint256[] calldata inviteAmounts
    ) external payable;
}

/**
 * @title GuessGameBase
 * @dev Base guessing game contract, integrating Chainlink VRF V2.5 random number generation and invite reward system
 */
abstract contract GuessGameBase is VRFConsumerBaseV2Plus, ReentrancyGuard, Pausable {
    
    // Game structure
    struct Game {
        address[] players;          // list of participating players
        uint256 startTime;         // game start time
        uint256 randomSeed;        // random seed
        address winner;            // winner
        bool isFinished;           // whether finished
        bool isRefunded;           // whether refunded
        uint256 vrfRequestId;      // VRF request ID
        uint256 totalInviteRewards; // total invite rewards for this game
        bool rewardsReleased;      // whether invite rewards are released
    }
    
    // State variables
    mapping(uint256 => Game) public games;                    // game mapping
    mapping(uint256 => uint256) public vrfRequestToGameId;    // VRF request ID to game ID mapping
    mapping(uint256 => mapping(address => uint256)) public gameInviteRewards; // game ID -> inviter -> reward amount
    mapping(uint256 => address[]) public gameInviters;        // game ID -> inviter list
    
    uint256 public currentGameId;                             // current game ID
    uint256 public constant ENTRY_FEE = 0.01 ether;         // entry fee
    uint256 public constant BASE_PLATFORM_FEE_PERCENT = 6;   // base platform fee percentage
    uint256 public constant INVITE_REWARD_PERCENT = 2;       // invite reward percentage
    uint256 public constant REFUND_TIMEOUT = 24 hours;      // refund timeout
    
    // Abstract variables, implemented by child contracts
    uint256 public immutable MAX_PLAYERS;                    // maximum number of players
    
    // Invite manager
    IInviteManager public inviteManager;
    
    // Platform fee receiver address
    address public platformFeeReceiver;
    
    // Chainlink VRF V2.5 configuration
    uint256 private s_subscriptionId;                        // support larger subscription ID
    bytes32 private keyHash;
    uint32 private callbackGasLimit = 1000000;
    uint16 private requestConfirmations = 3;
    uint32 private numWords = 1;
    
    // Events
    event GameStarted(uint256 indexed gameId, uint256 startTime);
    event PlayerJoined(uint256 indexed gameId, address indexed player, uint256 playerCount);
    event RandomnessRequested(uint256 indexed gameId, uint256 indexed requestId);
    event WinnerSelected(uint256 indexed gameId, address indexed winner, uint256 reward);
    event GameRefunded(uint256 indexed gameId, uint256 playerCount);
    event InviteRewardAccumulated(uint256 indexed gameId, address indexed inviter, address indexed invitee, uint256 reward);
    event InviteRewardsReleased(uint256 indexed gameId, uint256 totalRewards);
    event PlatformFeesWithdrawn(address indexed receiver, uint256 amount);
    event VRFRequestRetried(uint256 indexed gameId);
    
    /**
     * @dev Constructor
     * @param _maxPlayers Maximum number of players
     * @param _vrfCoordinator VRF coordinator address
     * @param _subscriptionId Subscription ID (supports uint256)
     * @param _keyHash VRF key hash
     * @param _inviteManager Invite manager address
     */
    constructor(
        uint256 _maxPlayers,
        address _vrfCoordinator,
        uint256 _subscriptionId,
        bytes32 _keyHash,
        address _inviteManager
    ) VRFConsumerBaseV2Plus(_vrfCoordinator) {
        MAX_PLAYERS = _maxPlayers;
        s_subscriptionId = _subscriptionId;
        keyHash = _keyHash;
        inviteManager = IInviteManager(_inviteManager);
        platformFeeReceiver = msg.sender; // Default: set deployer as fee receiver
        
        // Initialize currentGameId to 0, game will start when first user participates
        currentGameId = 0;
    }
    
    /**
     * @dev Receive ETH transfer and automatically participate in game
     */
    receive() external payable nonReentrant whenNotPaused {
        require(msg.value == ENTRY_FEE, "Invalid entry fee. Please send exactly 0.01 ETH to participate.");
        _participate();
    }
    
    /**
     * @dev Participate in game
     */
    function participate() external payable nonReentrant whenNotPaused {
        require(msg.value == ENTRY_FEE, "Invalid entry fee");
        _participate();
    }
    
    /**
     * @dev Internal game participation logic
     */
    function _participate() internal {
        // If no game exists (currentGameId = 0) or current game is finished/refunded, start a new game
        if (currentGameId == 0 || games[currentGameId].isFinished || games[currentGameId].isRefunded) {
            _startNewGame();
        }
        
        Game storage game = games[currentGameId];
        require(game.players.length < MAX_PLAYERS, "Game is full");
        require(!game.isFinished, "Game is finished");
        require(block.timestamp - game.startTime < REFUND_TIMEOUT, "Game timeout");
        
        // Check if user has already participated
        for (uint256 i = 0; i < game.players.length; i++) {
            require(game.players[i] != msg.sender, "Already participated");
        }
        
        // Add player
        game.players.push(msg.sender);
        
        // 🎁 Record invite reward (distributed after game ends)
        _recordInviteReward(currentGameId, msg.sender);
        
        emit PlayerJoined(currentGameId, msg.sender, game.players.length);
        
        // If maximum players reached, request randomness for draw
        if (game.players.length == MAX_PLAYERS) {
            _requestRandomness(currentGameId);
        }
    }
    
    /**
     * @dev Record invite reward (distributed after game ends)
     */
    function _recordInviteReward(uint256 gameId, address player) internal {
        if (address(inviteManager) != address(0)) {
            try inviteManager.getInviter(player) returns (address inviterAddr) {
                if (inviterAddr != address(0)) {
                    uint256 inviteReward = (ENTRY_FEE * INVITE_REWARD_PERCENT) / 100;
                    
                    // If this is the first reward for this inviter in this game, add to inviter list
                    if (gameInviteRewards[gameId][inviterAddr] == 0) {
                        gameInviters[gameId].push(inviterAddr);
                    }
                    
                    // Record invite reward, but don't distribute immediately
                    gameInviteRewards[gameId][inviterAddr] += inviteReward;
                    games[gameId].totalInviteRewards += inviteReward;
                    
                    emit InviteRewardAccumulated(gameId, inviterAddr, player, inviteReward);
                }
            } catch {
                // If call fails, continue game flow
            }
        }
    }
    
    /**
     * @dev Request randomness (using VRF V2.5)
     */
    function _requestRandomness(uint256 gameId) internal {
        VRFV2PlusClient.RandomWordsRequest memory req = VRFV2PlusClient.RandomWordsRequest({
            keyHash: keyHash,
            subId: s_subscriptionId,
            requestConfirmations: requestConfirmations,
            callbackGasLimit: callbackGasLimit,
            numWords: numWords,
            extraArgs: VRFV2PlusClient._argsToBytes(
                VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
            )
        });
        
        uint256 requestId = s_vrfCoordinator.requestRandomWords(req);
        
        vrfRequestToGameId[requestId] = gameId;
        games[gameId].vrfRequestId = requestId;
        
        emit RandomnessRequested(gameId, requestId);
    }
    
    /**
     * @dev Chainlink VRF V2.5 callback function
     */
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        uint256 gameId = vrfRequestToGameId[requestId];
        require(gameId > 0, "Invalid request ID");
        
        Game storage game = games[gameId];
        require(!game.isFinished, "Game already finished");
        require(game.players.length == MAX_PLAYERS, "Game not full");
        
        uint256 randomness = randomWords[0];
        
        // Generate winner index
        uint256 winnerIndex = randomness % game.players.length;
        address winner = game.players[winnerIndex];
        
        // 🎯 Correct fund flow logic
        uint256 totalPrize = ENTRY_FEE * game.players.length;                    // total participation amount
        uint256 totalInviteRewards = game.totalInviteRewards;                    // total invite rewards = participation amount × 2%
        uint256 platformFee = (totalPrize * BASE_PLATFORM_FEE_PERCENT) / 100;   // platform fee amount = total participation amount × 6%
        uint256 winnerReward = totalPrize - platformFee;                         // winner amount = total participation amount - platform fee amount
        uint256 actualPlatformFee = platformFee - totalInviteRewards;            // actual platform fee = platform fee amount - total invite rewards
        
        // Update game state
        game.randomSeed = randomness;
        game.winner = winner;
        game.isFinished = true;
        
        // 🎉 1. Transfer to winner (winner amount)
        if (winnerReward > 0) {
            payable(winner).transfer(winnerReward);
        }
        
        // 💰 2. Handle platform fees and invite rewards
        uint256 totalToInviteManager = actualPlatformFee + totalInviteRewards;
        if (totalToInviteManager > 0 && address(inviteManager) != address(0)) {
            // Collect invite reward distribution information
            address[] memory inviters;
            uint256[] memory inviteAmounts;
            (inviters, inviteAmounts) = _getInviteRewardDistribution(gameId);
            
            try inviteManager.processGameRewards{value: totalToInviteManager}(
                gameId,
                actualPlatformFee,
                inviters,
                inviteAmounts
            ) {
                game.rewardsReleased = true;
                emit InviteRewardsReleased(gameId, totalInviteRewards);
            } catch {
                // If transfer fails, funds remain in contract for later withdrawal
            }
        }
        
        emit WinnerSelected(gameId, winner, winnerReward);
        
        // Game completed, wait for next user to start new game
    }
    
    /**
     * @dev Get invite reward distribution information for a game
     */
    function _getInviteRewardDistribution(uint256 gameId) internal view returns (
        address[] memory inviters,
        uint256[] memory amounts
    ) {
        // Get inviter list directly from gameInviters
        address[] memory gameInvitersList = gameInviters[gameId];
        uint256 inviterCount = gameInvitersList.length;
        
        // Create return arrays
        inviters = new address[](inviterCount);
        amounts = new uint256[](inviterCount);
        
        // Fill data
        for (uint256 i = 0; i < inviterCount; i++) {
            address inviterAddr = gameInvitersList[i];
            inviters[i] = inviterAddr;
            amounts[i] = gameInviteRewards[gameId][inviterAddr];
        }
        
        return (inviters, amounts);
    }
    
    /**
     * @dev Start new game
     */
    function _startNewGame() internal {
        currentGameId++;
        games[currentGameId].startTime = block.timestamp;
        emit GameStarted(currentGameId, block.timestamp);
    }
    
    /**
     * @dev Retry VRF request for a game if previous request failed
     * Only owner can call this function
     */
    function retryVRFRequest(uint256 gameId) external onlyOwner nonReentrant {
        Game storage game = games[gameId];
        require(!game.isFinished, "Game already finished");
        require(!game.isRefunded, "Game already refunded");
        require(game.players.length == MAX_PLAYERS, "Game not full");
        
        // Request new randomness
        _requestRandomness(gameId);
        
        emit VRFRequestRetried(gameId);
    }
    
    /**
     * @dev Refund timeout game
     */
    function refundGame(uint256 gameId) external nonReentrant {
        Game storage game = games[gameId];
        require(!game.isFinished, "Game already finished");
        require(!game.isRefunded, "Game already refunded");
        require(block.timestamp - game.startTime >= REFUND_TIMEOUT, "Refund timeout not reached");
        require(game.players.length > 0, "No players to refund");
        
        // Mark as refunded
        game.isRefunded = true;
        
        // Refund to all players
        uint256 playerCount = game.players.length;
        for (uint256 i = 0; i < playerCount; i++) {
            payable(game.players[i]).transfer(ENTRY_FEE);
        }
        
        emit GameRefunded(gameId, playerCount);
        
        // Game refunded, wait for next user to start new game
    }
    
    /**
     * @dev Set platform fee receiver address
     */
    function setPlatformFeeReceiver(address _receiver) external onlyOwner {
        require(_receiver != address(0), "Invalid receiver address");
        platformFeeReceiver = _receiver;
    }
    
    /**
     * @dev Emergency withdraw contract balance
     */
    function emergencyWithdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");
        
        payable(platformFeeReceiver).transfer(balance);
        emit PlatformFeesWithdrawn(platformFeeReceiver, balance);
    }
    
    /**
     * @dev Set invite manager address (owner only)
     */
    function setInviteManager(address _inviteManager) external onlyOwner {
        inviteManager = IInviteManager(_inviteManager);
    }
    
    /**
     * @dev Emergency pause
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpause
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Update VRF configuration (owner only)
     */
    function updateVRFConfig(
        uint256 _subscriptionId,
        bytes32 _keyHash,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations
    ) external onlyOwner {
        s_subscriptionId = _subscriptionId;
        keyHash = _keyHash;
        callbackGasLimit = _callbackGasLimit;
        requestConfirmations = _requestConfirmations;
    }
    
    // Query functions
    function getCurrentGame() external view returns (
        address[] memory players,
        uint256 startTime,
        bool isFinished,
        uint256 timeLeft,
        uint256 totalInviteRewards
    ) {
        // If no game started yet, return empty state
        if (currentGameId == 0) {
            address[] memory emptyPlayers = new address[](0);
            return (emptyPlayers, 0, false, 0, 0);
        }
        
        Game storage game = games[currentGameId];
        uint256 timeLeft_ = 0;
        
        if (!game.isFinished && block.timestamp < game.startTime + REFUND_TIMEOUT) {
            timeLeft_ = (game.startTime + REFUND_TIMEOUT) - block.timestamp;
        }
        
        return (game.players, game.startTime, game.isFinished, timeLeft_, game.totalInviteRewards);
    }
    
    function getGame(uint256 gameId) external view returns (
        address[] memory players,
        uint256 startTime,
        uint256 randomSeed,
        address winner,
        bool isFinished,
        bool isRefunded,
        uint256 totalInviteRewards
    ) {
        Game storage game = games[gameId];
        return (
            game.players,
            game.startTime,
            game.randomSeed,
            game.winner,
            game.isFinished,
            game.isRefunded,
            game.totalInviteRewards
        );
    }
    
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    /**
     * @dev Calculate expected fee distribution for a game
     */
    function calculateGameRewards(uint256 gameId) external view returns (
        uint256 totalPrize,
        uint256 totalInviteRewards,
        uint256 platformFee,
        uint256 winnerReward
    ) {
        Game storage game = games[gameId];
        totalPrize = ENTRY_FEE * game.players.length;
        totalInviteRewards = game.totalInviteRewards;
        
        platformFee = (totalPrize * BASE_PLATFORM_FEE_PERCENT) / 100;
        winnerReward = totalPrize - platformFee; // Correction: winner amount = total participation amount - platform fee
        
        return (totalPrize, totalInviteRewards, platformFee, winnerReward);
    }
    
    /**
     * @dev Get base expected reward
     */
    function getBaseExpectedReward() external pure returns (uint256) {
        return ENTRY_FEE;
    }
    
    /**
     * @dev Get game type
     */
    function getGameType() external view virtual returns (string memory);
    
    /**
     * @dev Get game history
     */
    function getGameHistory(uint256 startId, uint256 count) external view returns (
        uint256[] memory gameIds,
        address[][] memory playersArray,
        uint256[] memory startTimes,
        address[] memory winners,
        bool[] memory isFinishedArray,
        bool[] memory isRefundedArray
    ) {
        require(count > 0 && count <= 50, "Invalid count range");
        
        uint256 actualCount = 0;
        uint256 endId = startId + count;
        if (endId > currentGameId) {
            endId = currentGameId + 1;
        }
        
        // Calculate actual return count
        for (uint256 i = startId; i < endId; i++) {
            if (games[i].startTime > 0) {
                actualCount++;
            }
        }
        
        gameIds = new uint256[](actualCount);
        playersArray = new address[][](actualCount);
        startTimes = new uint256[](actualCount);
        winners = new address[](actualCount);
        isFinishedArray = new bool[](actualCount);
        isRefundedArray = new bool[](actualCount);
        
        uint256 index = 0;
        for (uint256 i = startId; i < endId; i++) {
            if (games[i].startTime > 0) {
                gameIds[index] = i;
                playersArray[index] = games[i].players;
                startTimes[index] = games[i].startTime;
                winners[index] = games[i].winner;
                isFinishedArray[index] = games[i].isFinished;
                isRefundedArray[index] = games[i].isRefunded;
                index++;
            }
        }
    }
    
    /**
     * @dev Get recent finished games
     */
    function getRecentFinishedGames(uint256 count) external view returns (
        uint256[] memory gameIds,
        address[][] memory playersArray,
        uint256[] memory startTimes,
        address[] memory winners,
        uint256[] memory winnerRewards
    ) {
        require(count > 0 && count <= 20, "Invalid count range");
        
        uint256[] memory tempGameIds = new uint256[](count);
        uint256 actualCount = 0;
        
        // Start from latest game and search backwards for finished games
        for (uint256 i = currentGameId; i > 0 && actualCount < count; i--) {
            if (games[i].isFinished && !games[i].isRefunded) {
                tempGameIds[actualCount] = i;
                actualCount++;
            }
        }
        
        gameIds = new uint256[](actualCount);
        playersArray = new address[][](actualCount);
        startTimes = new uint256[](actualCount);
        winners = new address[](actualCount);
        winnerRewards = new uint256[](actualCount);
        
        for (uint256 i = 0; i < actualCount; i++) {
            uint256 gameId = tempGameIds[i];
            gameIds[i] = gameId;
            playersArray[i] = games[gameId].players;
            startTimes[i] = games[gameId].startTime;
            winners[i] = games[gameId].winner;
            
            // Calculate winner reward
            uint256 totalPrize = ENTRY_FEE * games[gameId].players.length;
            uint256 platformFee = (totalPrize * BASE_PLATFORM_FEE_PERCENT) / 100;
            winnerRewards[i] = totalPrize - platformFee; // Correction: winner amount = total participation amount - platform fee
        }
    }
    
    /**
     * @dev Verify game result
     */
    function verifyGameResult(uint256 gameId) external view returns (
        bool isValid,
        uint256 randomSeed,
        address winner,
        uint256 winnerIndex,
        string memory message
    ) {
        Game storage game = games[gameId];
        
        if (game.startTime == 0) {
            return (false, 0, address(0), 0, "Game does not exist");
        }
        
        if (!game.isFinished) {
            return (false, 0, address(0), 0, "Game not finished");
        }
        
        if (game.isRefunded) {
            return (false, 0, address(0), 0, "Game was refunded");
        }
        
        if (game.players.length == 0) {
            return (false, 0, address(0), 0, "No players in game");
        }
        
        uint256 calculatedWinnerIndex = game.randomSeed % game.players.length;
        address calculatedWinner = game.players[calculatedWinnerIndex];
        
        bool valid = (calculatedWinner == game.winner);
        
        return (
            valid,
            game.randomSeed,
            game.winner,
            calculatedWinnerIndex,
            valid ? "Game result is valid" : "Game result verification failed"
        );
    }
    
    /**
     * @dev Get game statistics
     */
    function getGameStats() external view returns (
        uint256 totalGames,
        uint256 finishedGames,
        uint256 totalPrizeDistributed,
        uint256 totalPlayersCount
    ) {
        totalGames = currentGameId;
        
        for (uint256 i = 1; i <= currentGameId; i++) {
            if (games[i].startTime > 0) {
                totalPlayersCount += games[i].players.length;
                
                if (games[i].isFinished && !games[i].isRefunded) {
                    finishedGames++;
                    uint256 totalPrize = ENTRY_FEE * games[i].players.length;
                    uint256 platformFee = (totalPrize * BASE_PLATFORM_FEE_PERCENT) / 100;
                    totalPrizeDistributed += totalPrize - platformFee; // Correction: winner amount = total participation amount - platform fee
                }
            }
        }
    }
} 
