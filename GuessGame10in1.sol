// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./GuessGameBase.sol";

/**
 * @title GuessGame10in1
 * @dev Ten-in-one guessing game contract
 */
contract GuessGame10in1 is GuessGameBase {
    
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
    ) GuessGameBase(10, _vrfCoordinator, _subscriptionId, _keyHash, _inviteManager) {
        // Game for 10 players
    }
    
    /**
     * @dev Get game type
     */
    function getGameType() external pure override returns (string memory) {
        return "10in1";
    }
    
    /**
     * @dev Get game description
     */
    function getGameDescription() external pure returns (string memory) {
        return "Ten players, one winner - Maximum excitement, maximum rewards";
    }
} 
