# Guess Game Smart Contracts

A decentralized lottery-style guessing game platform built on Binance Smart Chain (BSC), featuring multiple game variants, referral system, and provably fair randomness using Chainlink VRF V2.5.

## 🎮 Overview

The Guess Game platform consists of multiple smart contracts working together to provide a fair, transparent, and engaging lottery experience:

- **Multiple Game Variants**: 2-in-1, 5-in-1, and 10-in-1 games with different risk/reward profiles
- **Provably Fair Randomness**: Uses Chainlink VRF V2.5 for transparent winner selection
- **Referral System**: Built-in invitation system with automatic reward distribution
- **Automatic Game Management**: Continuous game flow with automatic winner selection and payouts

## 📁 Contract Architecture

### Core Contracts

#### 1. GuessGameBase.sol (635 lines)
The foundational abstract contract implementing core game logic:

**Key Parameters:**
- Entry Fee: 0.01 BNB per player
- Platform Fee: 6% of total prize pool
- Referral Rewards: 2% of entry fees distributed to inviters
- Refund Protection: 24-hour timeout mechanism
- VRF Integration: Chainlink VRF V2.5 for secure randomness

**Core Features:**
- Automatic game progression with unique game IDs
- Winner selection using verifiable randomness
- Secure fund distribution and balance management
- Emergency controls and pausing mechanism
- Comprehensive game history and statistics

#### 2. Game Variants

**GuessGame2in1.sol**
- 2 players per game
- Winner takes ~94% of total pool (0.0188 BNB)
- Win probability: 50%
- Low risk, frequent games

**GuessGame5in1.sol**
- 5 players per game
- Winner takes ~94% of total pool (0.047 BNB)
- Win probability: 20%
- Medium risk, balanced gameplay

**GuessGame10in1.sol**
- 10 players per game
- Winner takes ~94% of total pool (0.094 BNB)
- Win probability: 10%
- High risk, maximum rewards

#### 3. InviteManager.sol (324 lines)
Comprehensive referral system management:

**Core Functionality:**
- Invite code generation (8-character unique codes)
- Referral tracking and relationship management
- Reward accumulation (2% commission calculation)
- Secure reward claiming system
- Platform fee management

#### 4. MockVRFCoordinatorV2Plus.sol
Testing utility for local development:
- Simulates Chainlink VRF functionality
- Provides deterministic randomness for testing
- Manual callback triggering for test scenarios

## 🔧 Technical Specifications

### Security Features

**Multi-Layer Protection:**
- **ReentrancyGuard**: Protection against reentrancy attacks
- **Pausable**: Emergency stop functionality
- **Access Control**: Multi-level permissions (Owner, Authorized Contracts)
- **Balance Validation**: Continuous fund tracking and validation
- **Timeout Protection**: 24-hour refund mechanism
- **VRF Security**: Chainlink's proven randomness solution

### Gas Optimization

**Deployment Costs:**
- GuessGameBase: ~2,500,000 gas
- Game variants: ~2,600,000 gas each
- InviteManager: ~1,800,000 gas

**Transaction Costs:**
- Participate: ~150,000 gas
- Winner selection: ~200,000 gas
- Claim rewards: ~50,000 gas

### Integration Standards

- **OpenZeppelin**: Uses battle-tested security libraries
- **Chainlink VRF V2.5**: Latest VRF standard for enhanced security
- **Solidity ^0.8.19**: Latest language features and optimizations

## 🎯 Game Flow

### 1. Game Initialization
- Contract automatically starts the first game upon deployment
- Each game has a unique ID and timestamp

### 2. Player Participation
```solidity
// Players can participate by sending exactly 0.01 BNB
contract.participate{value: 0.01 ether}();

// Or directly via ETH transfer to contract address
```

### 3. Winner Selection
- When game reaches maximum capacity, VRF randomness is requested
- Winner is selected using verifiable random number
- Funds are automatically distributed

### 4. Reward Distribution
- **Winner**: Receives ~94% of total prize pool
- **Platform**: Receives 6% platform fee
- **Referrers**: Receive 2% of referred players' entry fees

## 💰 Economics Model

### Fee Structure
- **Entry Fee**: 0.01 BNB (fixed)
- **Platform Fee**: 6% of total pool
- **Referral Rewards**: 2% of entry fees
- **Winner Payout**: ~94% of total pool

### Example Calculation (5-in-1 Game)
```
Total Pool: 5 × 0.01 BNB = 0.05 BNB
Platform Fee: 0.05 × 6% = 0.003 BNB
Referral Rewards: 0.05 × 2% = 0.001 BNB
Winner Receives: 0.05 - 0.003 = 0.047 BNB
```

### Expected Value Analysis

| Game Type | Entry Fee | Win Probability | Expected Reward | Expected Value | House Edge |
|-----------|-----------|-----------------|-----------------|----------------|------------|
| 2-in-1    | 0.01 BNB  | 50%            | 0.0188 BNB     | 0.0094 BNB    | 6%         |
| 5-in-1    | 0.01 BNB  | 20%            | 0.047 BNB      | 0.0094 BNB    | 6%         |
| 10-in-1   | 0.01 BNB  | 10%            | 0.094 BNB      | 0.0094 BNB    | 6%         |

## 🔍 Verification and Transparency

### Game Result Verification
```solidity
function verifyGameResult(uint256 gameId) external view returns (
    bool isValid,
    uint256 randomSeed,
    address winner,
    uint256 winnerIndex,
    string memory message
);
```

### Transparency Features
- All game results are verifiable on-chain
- Random seeds are publicly accessible
- Complete game history is maintained
- Real-time statistics available

## 📊 Query Functions

### Game Information
```solidity
// Get current active game
function getCurrentGame() external view returns (
    address[] memory players,
    uint256 startTime,
    bool isFinished,
    uint256 timeLeft,
    uint256 totalInviteRewards
);

// Get specific game details
function getGame(uint256 gameId) external view returns (
    address[] memory players,
    uint256 startTime,
    uint256 randomSeed,
    address winner,
    bool isFinished,
    bool isRefunded,
    uint256 totalInviteRewards
);

// Get recent winners
function getRecentFinishedGames(uint256 count) external view returns (
    uint256[] memory gameIds,
    address[][] memory playersArray,
    uint256[] memory startTimes,
    address[] memory winners,
    uint256[] memory winnerRewards
);
```

### Statistics
```solidity
// Get platform statistics
function getGameStats() external view returns (
    uint256 totalGames,
    uint256 finishedGames,
    uint256 totalPrizeDistributed,
    uint256 totalPlayersCount
);
```

## 🛡️ Security Considerations

### Best Practices Implemented
- Fail-safe mechanisms with automatic refunds
- Multi-level permission system
- Emergency procedures (pause and withdrawal)
- Comprehensive event logging

### Risk Mitigation
- 24-hour timeout protection
- Continuous balance verification
- Chainlink's proven randomness solution
- OpenZeppelin's ReentrancyGuard

## 📋 License

This project is licensed under the MIT License - see the [LICENSE](../LICENSE) file for details.

## ⚠️ Disclaimer

**Important Notice:**
- This software is provided "as is" without warranty of any kind
- Users should conduct their own security audits before mainnet deployment
- Gambling regulations vary by jurisdiction - ensure compliance with local laws
- Smart contracts are immutable once deployed - thorough testing is essential

**Risk Factors:**
- Smart contract vulnerabilities
- Blockchain network risks
- Regulatory compliance requirements
- Market volatility of cryptocurrencies

---

*For additional resources, deployment guides, and frontend integration examples, refer to the main project repository.*
