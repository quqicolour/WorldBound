// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAIConstraint} from "./IAIConstraint.sol";

/**
 * @title IAIAgent
 * @notice Gas-optimized interface for AI agent contracts
 * @dev Uses uint8 for status enum
 */
interface IAIAgent {
    /*//////////////////////////////////////////////////////////////
                                ENUMS
    //////////////////////////////////////////////////////////////*/

    enum AgentStatus { ACTIVE, RESTRICTED, SUSPENDED, TERMINATED }

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct AgentInfo {
        address agentAddress;
        address owner;
        AgentStatus status;
        uint64 registrationTime;
        uint64 lastActivityTime;
        string version;
        string metadataURI;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event AgentRegistered(address indexed agent, address indexed owner, string version);
    event StatusChanged(address indexed agent, uint8 oldStatus, uint8 newStatus, string reason);
    event ActionProposed(address indexed agent, bytes32 indexed actionId, bytes data);
    event ActionExecuted(address indexed agent, bytes32 indexed actionId, bool success);

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function register(address owner, string calldata version, string calldata metadataURI) external;
    function proposeAction(bytes calldata actionData) external returns (bytes32 actionId);
    function executeAction(bytes32 actionId) external returns (bool success);
    function updateStatus(AgentStatus newStatus, string calldata reason) external;
    function recordViolation(bytes32 constraintId, IAIConstraint.SeverityLevel severity) external;
    function getAgentInfo() external view returns (AgentInfo memory info);
    function getViolationCount() external view returns (uint256 count);
    function isActionPermitted(bytes calldata actionData) external view returns (bool permitted);
}
