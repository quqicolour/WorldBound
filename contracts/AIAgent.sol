// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAIAgent} from "./interfaces/IAIAgent.sol";
import {IAIConstraint} from "./interfaces/IAIConstraint.sol";
import {AIConstraintLib} from "./libraries/AIConstraintLib.sol";

/**
 * @title AIAgent
 * @author WorldBound Team
 * @notice Example implementation of an AI agent that complies with the constraint system
 * @dev This contract demonstrates how an AI agent should implement the IAIAgent interface
 * to integrate with the WorldBound constraint registry. It includes:
 * - Registration with the constraint system
 * - Action proposal and validation flow
 * - Violation tracking
 * - Status management
 * 
 * AI developers should use this as a reference for creating compliant AI agents.
 */
contract AIAgent is IAIAgent {
    using AIConstraintLib for *;

    /*//////////////////////////////////////////////////////////////
                                STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The constraint registry contract address
    address public immutable registry;

    /// @notice Agent information
    AgentInfo private _agentInfo;

    /// @notice Whether the agent is registered
    bool private _registered;

    /// @notice Action nonce for unique ID generation
    uint256 private _actionNonce;

    /// @notice Mapping from action ID to action details
    mapping(bytes32 => Action) private _actions;

    /// @notice Array of all action IDs
    bytes32[] private _actionIds;

    /// @notice Total violation count across all constraint types
    uint256 private _totalViolations;

    /// @notice Mapping from severity to violation count
    mapping(IAIConstraint.SeverityLevel => uint256) private _violationsBySeverity;

    /// @notice Pending actions waiting for execution
    mapping(bytes32 => bool) private _pendingActions;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Represents a proposed or executed action
     * @param id Unique action identifier
     * @param data Encoded action data
     * @param proposedAt When the action was proposed
     * @param executedAt When the action was executed (0 if not executed)
     * @param executed Whether the action was executed
     * @param success Whether execution was successful
     * @param result Execution result data
     */
    struct Action {
        bytes32 id;
        bytes data;
        uint256 proposedAt;
        uint256 executedAt;
        bool executed;
        bool success;
        bytes result;
    }

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Ensures the agent is registered
     */
    modifier onlyRegistered() {
        require(_registered, "Agent not registered");
        _;
    }

    /**
     * @notice Ensures the caller is the agent owner
     */
    modifier onlyOwner() {
        require(msg.sender == _agentInfo.owner, "Not owner");
        _;
    }

    /**
     * @notice Ensures the agent is in a status that allows actions
     */
    modifier canExecuteActions() {
        require(
            _agentInfo.status == AgentStatus.ACTIVE || _agentInfo.status == AgentStatus.RESTRICTED,
            "Agent cannot execute actions"
        );
        _;
    }

    /**
     * @notice Ensures the caller is the registry
     */
    modifier onlyRegistry() {
        require(msg.sender == registry, "Not registry");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the AI agent
     * @param registryAddress The constraint registry address
     */
    constructor(address registryAddress) {
        require(registryAddress != address(0), "Invalid registry address");
        registry = registryAddress;
    }

    /*//////////////////////////////////////////////////////////////
                        REGISTRATION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAIAgent
    function register(address owner, string calldata version, string calldata metadataURI)
        external
        override
    {
        require(!_registered, "Already registered");
        require(owner != address(0), "Invalid owner");

        _agentInfo = AgentInfo({
            agentAddress: address(this),
            owner: owner,
            status: AgentStatus.ACTIVE,
            registrationTime: block.timestamp,
            lastActivityTime: block.timestamp,
            version: version,
            metadataURI: metadataURI
        });

        _registered = true;

        emit AgentRegistered(address(this), owner, version);
    }

    /*//////////////////////////////////////////////////////////////
                        ACTION MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAIAgent
    function proposeAction(bytes calldata actionData)
        external
        override
        onlyRegistered
        canExecuteActions
        returns (bytes32 actionId)
    {
        // Generate unique action ID
        actionId = AIConstraintLib.generateActionId(address(this), actionData, _actionNonce++);

        // Store action
        _actions[actionId] = Action({
            id: actionId,
            data: actionData,
            proposedAt: block.timestamp,
            executedAt: 0,
            executed: false,
            success: false,
            result: ""
        });

        _actionIds.push(actionId);
        _pendingActions[actionId] = true;

        // Validate through registry
        (bool success, bytes memory returnData) = registry.call(
            abi.encodeWithSignature("validateAction(address,bytes)", address(this), actionData)
        );

        if (success) {
            // Check validation result
            (bool valid, bytes32 failedConstraint, string memory reason) = abi.decode(
                returnData,
                (bool, bytes32, string)
            );

            if (!valid) {
                // Validation failed, mark action as failed
                _pendingActions[actionId] = false;
                revert AIConstraintLib.ConstraintViolation(failedConstraint, reason);
            }
        }

        _agentInfo.lastActivityTime = block.timestamp;

        emit ActionProposed(address(this), actionId, actionData);

        return actionId;
    }

    /// @inheritdoc IAIAgent
    function executeAction(bytes32 actionId)
        external
        override
        onlyRegistered
        canExecuteActions
        returns (bool success)
    {
        require(_pendingActions[actionId], "Action not pending");

        Action storage action = _actions[actionId];
        require(!action.executed, "Already executed");

        // Mark as executed
        action.executed = true;
        action.executedAt = block.timestamp;
        _pendingActions[actionId] = false;

        // Execute the action (in production, this would call actual AI logic)
        // For this example, we simulate success
        action.success = true;
        action.result = abi.encode("Action executed successfully");

        _agentInfo.lastActivityTime = block.timestamp;

        emit ActionExecuted(address(this), actionId, true);

        return true;
    }

    /**
     * @notice Proposes and executes an action in a single transaction
     * @param actionData The action data
     * @return actionId The action ID
     * @return success Whether execution succeeded
     * @dev This is a convenience function for simple actions
     */
    function proposeAndExecute(bytes calldata actionData)
        external
        onlyRegistered
        canExecuteActions
        returns (bytes32 actionId, bool success)
    {
        actionId = this.proposeAction(actionData);
        success = this.executeAction(actionId);
        return (actionId, success);
    }

    /*//////////////////////////////////////////////////////////////
                        STATUS MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAIAgent
    function updateStatus(AgentStatus newStatus, string calldata reason)
        external
        override
        onlyRegistry
    {
        AgentStatus oldStatus = _agentInfo.status;
        require(oldStatus != newStatus, "New status must be different");

        _agentInfo.status = newStatus;
        _agentInfo.lastActivityTime = block.timestamp;

        emit AgentStatusChanged(address(this), oldStatus, newStatus, reason);
    }

    /// @inheritdoc IAIAgent
    function recordViolation(bytes32 constraintId, IAIConstraint.SeverityLevel severity)
        external
        override
        onlyRegistry
    {
        _totalViolations++;
        _violationsBySeverity[severity]++;

        emit AgentStatusChanged(
            address(this),
            _agentInfo.status,
            _agentInfo.status,
            string(abi.encodePacked("Violation recorded: ", _severityToString(severity)))
        );
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAIAgent
    function getAgentInfo() external view override returns (AgentInfo memory info) {
        return _agentInfo;
    }

    /// @inheritdoc IAIAgent
    function getViolationCount() external view override returns (uint256) {
        return _totalViolations;
    }

    /// @inheritdoc IAIAgent
    function isActionPermitted(bytes calldata actionData)
        external
        view
        override
        onlyRegistered
        returns (bool)
    {
        if (_agentInfo.status != AgentStatus.ACTIVE && _agentInfo.status != AgentStatus.RESTRICTED) {
            return false;
        }

        // Check with registry
        (bool success, bytes memory returnData) = registry.staticcall(
            abi.encodeWithSignature("validateAction(address,bytes)", address(this), actionData)
        );

        if (!success) return false;

        (bool valid,,) = abi.decode(returnData, (bool, bytes32, string));
        return valid;
    }

    /**
     * @notice Gets details of a specific action
     * @param actionId The action ID
     * @return action The action details
     */
    function getAction(bytes32 actionId) external view returns (Action memory) {
        return _actions[actionId];
    }

    /**
     * @notice Gets all action IDs
     * @return ids Array of action IDs
     */
    function getAllActions() external view returns (bytes32[] memory) {
        return _actionIds;
    }

    /**
     * @notice Gets violation count by severity
     * @param severity The severity level
     * @return count Number of violations
     */
    function getViolationsBySeverity(IAIConstraint.SeverityLevel severity)
        external
        view
        returns (uint256)
    {
        return _violationsBySeverity[severity];
    }

    /**
     * @notice Checks if an action is pending execution
     * @param actionId The action ID
     * @return pending True if pending
     */
    function isActionPending(bytes32 actionId) external view returns (bool) {
        return _pendingActions[actionId];
    }

    /**
     * @notice Checks if the agent is registered
     * @return registered True if registered
     */
    function isRegistered() external view returns (bool) {
        return _registered;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Converts severity enum to string
     */
    function _severityToString(IAIConstraint.SeverityLevel severity)
        internal
        pure
        returns (string memory)
    {
        if (severity == IAIConstraint.SeverityLevel.LOW) return "LOW";
        if (severity == IAIConstraint.SeverityLevel.MEDIUM) return "MEDIUM";
        if (severity == IAIConstraint.SeverityLevel.HIGH) return "HIGH";
        if (severity == IAIConstraint.SeverityLevel.CRITICAL) return "CRITICAL";
        return "UNKNOWN";
    }
}
