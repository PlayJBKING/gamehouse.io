// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./GuessGameBase.sol";

/**
 * @title GuessGame2in1
 * @dev Two-in-one guessing game contract
 */
contract GuessGame2in1 is GuessGameBase {
    
    /**
     * @dev Constructor
     * @param _vrfCoordinator VRF coordinator address
     * @param _subscriptionId VRF subscription ID (supports uint256)
     * @param _keyHash VRF key hash
     * @param _inviteManager Invite manager address
     */
    constructor(
        address _vrfCoordinator,
        uint256 _subscriptionId,
        bytes32 _keyHash,
        address _inviteManager
    ) GuessGameBase(2, _vrfCoordinator, _subscriptionId, _keyHash, _inviteManager) {
        // Game for 2 players
    }
    
    /**
     * @dev Get game type
     */
    function getGameType() external pure override returns (string memory) {
        return "2in1";
    }
    
    /**
     * @dev Get game description
     */
    function getGameDescription() external pure returns (string memory) {
        return "Two players, one winner - Dynamic reward based on invite bonuses";
    }
} 
