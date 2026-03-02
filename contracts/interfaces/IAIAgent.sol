// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAIConstraint} from "./IAIConstraint.sol";

/**
 * @title IAIAgent
 * @author WorldBound Team
 * @notice Interface for AI agent contracts that are subject to constraint enforcement
 * @dev AI agents implementing this interface can be registered with the constraint system
 * and their actions can be validated against active constraints.
 */
interface IAIAgent {
    /**
     * @notice Enum representing the current operational status of an AI agent
     * @param ACTIVE Agent is fully operational and can execute actions
     * @param RESTRICTED Agent can execute only whitelisted actions
     * @param SUSPENDED Agent is temporarily halted due to violations
     * @param TERMINATED Agent is permanently shut down
     */
    enum AgentStatus {
        ACTIVE,
        RESTRICTED,
        SUSPENDED,
        TERMINATED
    }

    /**
     * @notice Struct containing comprehensive information about an AI agent
     * @param agentAddress The blockchain address of the AI agent
     * @param owner The address that owns and controls this AI agent
     * @param status Current operational status of the agent
     * @param registrationTime Timestamp when the agent was registered
     * @param lastActivityTime Timestamp of the most recent activity
     * @param version Semantic version of the agent's software
     * @param metadataURI URI pointing to off-chain agent metadata (JSON)
     */
    struct AgentInfo {
        address agentAddress;
        address owner;
        AgentStatus status;
        uint256 registrationTime;
        uint256 lastActivityTime;
        string version;
        string metadataURI;
    }

    /**
     * @notice Emitted when an AI agent is registered with the constraint system
     * @param agentAddress The address of the registered agent
     * @param owner The owner of the agent
     * @param version The initial version of the agent
     */
    event AgentRegistered(
        address indexed agentAddress,
        address indexed owner,
        string version
    );

    /**
     * @notice Emitted when an AI agent's status changes
     * @param agentAddress The address of the agent
     * @param oldStatus The previous status
     * @param newStatus The new status
     * @param reason Human-readable reason for the status change
     */
    event AgentStatusChanged(
        address indexed agentAddress,
        AgentStatus oldStatus,
        AgentStatus newStatus,
        string reason
    );

    /**
     * @notice Emitted when an AI agent proposes an action
     * @param agentAddress The address of the agent
     * @param actionId Unique identifier for the proposed action
     * @param actionData Encoded data describing the action
     */
    event ActionProposed(
        address indexed agentAddress,
        bytes32 indexed actionId,
        bytes actionData
    );

    /**
     * @notice Emitted when an AI agent's action is executed
     * @param agentAddress The address of the agent
     * @param actionId The identifier of the executed action
     * @param success Whether the execution was successful
     */
    event ActionExecuted(
        address indexed agentAddress,
        bytes32 indexed actionId,
        bool success
    );

    /**
     * @notice Registers the AI agent with the constraint system
     * @param owner The address that will own this agent
     * @param version The software version of the agent
     * @param metadataURI URI to off-chain metadata
     */
    function register(
        address owner,
        string calldata version,
        string calldata metadataURI
    ) external;

    /**
     * @notice Proposes an action to be validated against constraints before execution
     * @param actionData Encoded description of the action
     * @return actionId Unique identifier assigned to this proposed action
     */
    function proposeAction(
        bytes calldata actionData
    ) external returns (bytes32 actionId);

    /**
     * @notice Executes an action that has passed constraint validation
     * @param actionId The identifier of the pre-approved action
     * @return success Whether the execution completed successfully
     */
    function executeAction(bytes32 actionId) external returns (bool success);

    /**
     * @notice Updates the agent's status (callable by registry or governance)
     * @param newStatus The new status to assign
     * @param reason Reason for the status change
     */
    function updateStatus(
        AgentStatus newStatus,
        string calldata reason
    ) external;

    /**
     * @notice Records a constraint violation against this agent
     * @param constraintId The identifier of the violated constraint
     * @param severity The severity level of the violation
     */
    function recordViolation(
        bytes32 constraintId,
        IAIConstraint.SeverityLevel severity
    ) external;

    /**
     * @notice Retrieves complete information about this agent
     * @return info The agent's information struct
     */
    function getAgentInfo() external view returns (AgentInfo memory info);

    /**
     * @notice Returns the number of recorded violations for this agent
     * @return count Total violation count
     */
    function getViolationCount() external view returns (uint256 count);

    /**
     * @notice Checks if a specific action is permitted under current constraints
     * @param actionData The action to check
     * @return permitted True if the action is allowed
     */
    function isActionPermitted(
        bytes calldata actionData
    ) external view returns (bool permitted);
}
