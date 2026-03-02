// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAIConstraint} from "./interfaces/IAIConstraint.sol";
import {IAIAgent} from "./interfaces/IAIAgent.sol";
import {AIConstraintLib} from "./libraries/AIConstraintLib.sol";

/**
 * @title AIConstraintRegistry
 * @author WorldBound Team
 * @notice Central registry for AI agents and their associated constraints
 * @dev This contract serves as the main coordination point for the AI constraint system.
 * It maintains a registry of all AI agents, tracks which constraints apply to each agent,
 * validates actions against all applicable constraints, and manages agent status based on
 * violation history.
 * 
 * The registry acts as a middleware between AI agents and constraint contracts,
 * ensuring that all actions are validated before execution and violations are properly
 * tracked and penalized.
 */
contract AIConstraintRegistry {
    using AIConstraintLib for *;

    /*//////////////////////////////////////////////////////////////
                                STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Contract owner with administrative privileges
    address public immutable owner;

    /// @notice Governance contract address for protocol upgrades
    address public governance;

    /// @notice Mapping from AI agent address to agent information
    mapping(address => IAIAgent.AgentInfo) private _agents;

    /// @notice Array of all registered agent addresses
    address[] private _agentAddresses;

    /// @notice Mapping from agent address to its index in _agentAddresses
    mapping(address => uint256) private _agentIndex;

    /// @notice Mapping from agent to constraints that apply to it
    mapping(address => bytes32[]) private _agentConstraints;

    /// @notice Mapping from constraint ID to constraint contract address
    mapping(bytes32 => address) private _constraintContracts;

    /// @notice Array of all registered constraint contract addresses
    address[] private _constraintContractsList;

    /// @notice Mapping from agent to violation history
    mapping(address => ViolationRecord[]) private _violationHistory;

    /// @notice Total number of violations across all agents
    uint256 public totalViolations;

    /// @notice Whether the registry is paused
    bool public paused;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Record of a constraint violation
     * @param constraintId The ID of the violated constraint
     * @param severity The severity level of the violation
     * @param timestamp When the violation occurred
     * @param evidence Proof of the violation
     */
    struct ViolationRecord {
        bytes32 constraintId;
        IAIConstraint.SeverityLevel severity;
        uint256 timestamp;
        bytes evidence;
    }

    /**
     * @notice Result of an action validation
     * @param valid Whether all constraints were satisfied
     * @param failedConstraint The first constraint that failed (if any)
     * @param reason Human-readable explanation
     */
    struct ValidationResult {
        bool valid;
        bytes32 failedConstraint;
        string reason;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a new AI agent is registered
     * @param agentAddress The address of the registered agent
     * @param owner The owner of the agent
     * @param version The agent's software version
     */
    event AgentRegistered(address indexed agentAddress, address indexed owner, string version);

    /**
     * @notice Emitted when an agent's status is updated
     * @param agentAddress The address of the agent
     * @param oldStatus The previous status
     * @param newStatus The new status
     * @param reason Reason for the status change
     */
    event AgentStatusUpdated(
        address indexed agentAddress,
        IAIAgent.AgentStatus oldStatus,
        IAIAgent.AgentStatus newStatus,
        string reason
    );

    /**
     * @notice Emitted when a constraint contract is registered
     * @param constraintContract The address of the constraint contract
     * @param constraintCount Number of constraints in the contract
     */
    event ConstraintContractRegistered(address indexed constraintContract, uint256 constraintCount);

    /**
     * @notice Emitted when constraints are assigned to an agent
     * @param agentAddress The agent receiving the constraints
     * @param constraintIds Array of constraint IDs assigned
     */
    event ConstraintsAssigned(address indexed agentAddress, bytes32[] constraintIds);

    /**
     * @notice Emitted when an action is validated
     * @param agentAddress The agent performing the action
     * @param actionId Unique identifier for the action
     * @param valid Whether validation passed
     */
    event ActionValidated(address indexed agentAddress, bytes32 indexed actionId, bool valid);

    /**
     * @notice Emitted when a violation is recorded
     * @param agentAddress The agent that violated constraints
     * @param constraintId The violated constraint
     * @param severity The severity level
     */
    event ViolationRecorded(
        address indexed agentAddress,
        bytes32 indexed constraintId,
        IAIConstraint.SeverityLevel severity
    );

    /**
     * @notice Emitted when the registry is paused or unpaused
     * @param paused The new pause status
     * @param reason Reason for the status change
     */
    event RegistryPaused(bool paused, string reason);

    /**
     * @notice Emitted when governance address is updated
     * @param oldGovernance The previous governance address
     * @param newGovernance The new governance address
     */
    event GovernanceUpdated(address oldGovernance, address newGovernance);

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Ensures only the owner can call the function
     */
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert AIConstraintLib.Unauthorized(msg.sender, keccak256("OWNER"));
        }
        _;
    }

    /**
     * @notice Ensures only governance can call the function
     */
    modifier onlyGovernance() {
        if (msg.sender != governance && msg.sender != owner) {
            revert AIConstraintLib.Unauthorized(msg.sender, keccak256("GOVERNANCE"));
        }
        _;
    }

    /**
     * @notice Ensures the registry is not paused
     */
    modifier whenNotPaused() {
        require(!paused, "Registry is paused");
        _;
    }

    /**
     * @notice Ensures the agent is registered
     * @param agent The agent to check
     */
    modifier onlyRegisteredAgent(address agent) {
        if (_agents[agent].agentAddress == address(0)) {
            revert AIConstraintLib.AgentNotRegistered(agent);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the AIConstraintRegistry contract
     * @param governanceAddress The address of the governance contract
     */
    constructor(address governanceAddress) {
        owner = msg.sender;
        governance = governanceAddress;
    }

    /*//////////////////////////////////////////////////////////////
                        AGENT MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Registers a new AI agent with the constraint system
     * @param agentAddress The blockchain address of the AI agent
     * @param agentOwner The address that will own and control the agent
     * @param version The software version of the agent
     * @param metadataURI URI to off-chain agent metadata
     * @param constraintIds Array of constraint IDs to apply to this agent
     */
    function registerAgent(
        address agentAddress,
        address agentOwner,
        string calldata version,
        string calldata metadataURI,
        bytes32[] calldata constraintIds
    ) external whenNotPaused returns (bool) {
        require(agentAddress != address(0), "Invalid agent address");
        require(agentOwner != address(0), "Invalid owner address");
        require(_agents[agentAddress].agentAddress == address(0), "Agent already registered");

        // Validate and assign constraints
        if (constraintIds.length > AIConstraintLib.MAX_CONSTRAINTS_PER_AGENT) {
            revert AIConstraintLib.TooManyConstraints(constraintIds.length, AIConstraintLib.MAX_CONSTRAINTS_PER_AGENT);
        }

        // Store agent info
        _agents[agentAddress] = IAIAgent.AgentInfo({
            agentAddress: agentAddress,
            owner: agentOwner,
            status: IAIAgent.AgentStatus.ACTIVE,
            registrationTime: block.timestamp,
            lastActivityTime: block.timestamp,
            version: version,
            metadataURI: metadataURI
        });

        _agentIndex[agentAddress] = _agentAddresses.length;
        _agentAddresses.push(agentAddress);

        // Assign constraints
        _agentConstraints[agentAddress] = constraintIds;

        emit AgentRegistered(agentAddress, agentOwner, version);
        emit ConstraintsAssigned(agentAddress, constraintIds);

        return true;
    }

    /**
     * @notice Updates an agent's status
     * @param agentAddress The agent to update
     * @param newStatus The new status to assign
     * @param reason Reason for the status change
     */
    function updateAgentStatus(
        address agentAddress,
        IAIAgent.AgentStatus newStatus,
        string calldata reason
    ) external onlyGovernance onlyRegisteredAgent(agentAddress) {
        IAIAgent.AgentInfo storage agent = _agents[agentAddress];
        IAIAgent.AgentStatus oldStatus = agent.status;

        require(oldStatus != newStatus, "New status must be different");
        require(oldStatus != IAIAgent.AgentStatus.TERMINATED, "Cannot update terminated agent");

        agent.status = newStatus;
        agent.lastActivityTime = block.timestamp;

        emit AgentStatusUpdated(agentAddress, oldStatus, newStatus, reason);
    }

    /**
     * @notice Assigns constraints to an agent
     * @param agentAddress The agent to assign constraints to
     * @param constraintIds Array of constraint IDs
     */
    function assignConstraints(address agentAddress, bytes32[] calldata constraintIds)
        external
        onlyGovernance
        onlyRegisteredAgent(agentAddress)
    {
        uint256 currentCount = _agentConstraints[agentAddress].length;
        uint256 newCount = currentCount + constraintIds.length;

        if (newCount > AIConstraintLib.MAX_CONSTRAINTS_PER_AGENT) {
            revert AIConstraintLib.TooManyConstraints(newCount, AIConstraintLib.MAX_CONSTRAINTS_PER_AGENT);
        }

        for (uint256 i = 0; i < constraintIds.length; i++) {
            _agentConstraints[agentAddress].push(constraintIds[i]);
        }

        emit ConstraintsAssigned(agentAddress, constraintIds);
    }

    /*//////////////////////////////////////////////////////////////
                    CONSTRAINT CONTRACT MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Registers a constraint contract
     * @param constraintContract The address of the constraint contract
     */
    function registerConstraintContract(address constraintContract) external onlyOwner {
        require(constraintContract != address(0), "Invalid contract address");

        IAIConstraint constraint = IAIConstraint(constraintContract);
        uint256 count = constraint.getConstraintCount();

        // Store constraint contract reference
        _constraintContractsList.push(constraintContract);

        // Map individual constraints to their contract
        for (uint256 i = 0; i < count; i++) {
            // Note: This is a simplified approach. In production, you'd want to
            // get constraint IDs through a different mechanism.
            bytes32 constraintId = keccak256(abi.encodePacked(constraintContract, i));
            _constraintContracts[constraintId] = constraintContract;
        }

        emit ConstraintContractRegistered(constraintContract, count);
    }

    /*//////////////////////////////////////////////////////////////
                        ACTION VALIDATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validates an AI agent's proposed action against all assigned constraints
     * @param agentAddress The address of the AI agent
     * @param actionData Encoded description of the action
     * @return result Validation result with details
     */
    function validateAction(address agentAddress, bytes calldata actionData)
        external
        whenNotPaused
        onlyRegisteredAgent(agentAddress)
        returns (ValidationResult memory result)
    {
        IAIAgent.AgentInfo storage agent = _agents[agentAddress];

        // Check agent status allows actions
        if (agent.status == IAIAgent.AgentStatus.SUSPENDED ||
            agent.status == IAIAgent.AgentStatus.TERMINATED) {
            return ValidationResult({
                valid: false,
                failedConstraint: bytes32(0),
                reason: "Agent status prevents action execution"
            });
        }

        bytes32[] memory constraints = _agentConstraints[agentAddress];

        // Check each assigned constraint
        for (uint256 i = 0; i < constraints.length; i++) {
            bytes32 constraintId = constraints[i];
            address constraintContract = _constraintContracts[constraintId];

            if (constraintContract == address(0)) continue;

            IAIConstraint constraint = IAIConstraint(constraintContract);

            // Check if constraint is active
            if (!constraint.isActive(constraintId)) continue;

            // Validate against constraint
            (bool compliant, bytes memory evidence) = constraint.validateAction(agentAddress, actionData);

            if (!compliant) {
                // Record the violation
                IAIConstraint.Constraint memory constraintInfo = constraint.getConstraint(constraintId);
                _recordViolation(agentAddress, constraintId, constraintInfo.severity, evidence);

                return ValidationResult({
                    valid: false,
                    failedConstraint: constraintId,
                    reason: _decodeViolationReason(evidence)
                });
            }
        }

        // Update last activity
        agent.lastActivityTime = block.timestamp;

        bytes32 actionId = AIConstraintLib.generateActionId(agentAddress, actionData, block.timestamp);
        emit ActionValidated(agentAddress, actionId, true);

        return ValidationResult({
            valid: true,
            failedConstraint: bytes32(0),
            reason: ""
        });
    }

    /**
     * @notice Reports a violation detected by external monitoring
     * @param agentAddress The agent that violated constraints
     * @param constraintId The violated constraint
     * @param evidence Proof of violation
     */
    function reportViolation(
        address agentAddress,
        bytes32 constraintId,
        bytes calldata evidence
    ) external whenNotPaused onlyRegisteredAgent(agentAddress) {
        address constraintContract = _constraintContracts[constraintId];
        require(constraintContract != address(0), "Constraint not found");

        IAIConstraint constraint = IAIConstraint(constraintContract);
        IAIConstraint.Constraint memory constraintInfo = constraint.getConstraint(constraintId);

        _recordViolation(agentAddress, constraintId, constraintInfo.severity, evidence);

        // Forward to constraint contract
        constraint.reportViolation(agentAddress, evidence);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pauses the registry
     * @param reason Reason for pausing
     */
    function pause(string calldata reason) external onlyOwner {
        paused = true;
        emit RegistryPaused(true, reason);
    }

    /**
     * @notice Unpauses the registry
     * @param reason Reason for unpausing
     */
    function unpause(string calldata reason) external onlyOwner {
        paused = false;
        emit RegistryPaused(false, reason);
    }

    /**
     * @notice Updates the governance address
     * @param newGovernance The new governance address
     */
    function setGovernance(address newGovernance) external onlyOwner {
        require(newGovernance != address(0), "Invalid governance address");
        address oldGovernance = governance;
        governance = newGovernance;
        emit GovernanceUpdated(oldGovernance, newGovernance);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets information about a registered agent
     * @param agentAddress The agent to query
     * @return info The agent's information
     */
    function getAgentInfo(address agentAddress)
        external
        view
        onlyRegisteredAgent(agentAddress)
        returns (IAIAgent.AgentInfo memory info)
    {
        return _agents[agentAddress];
    }

    /**
     * @notice Gets all constraint IDs assigned to an agent
     * @param agentAddress The agent to query
     * @return constraintIds Array of constraint IDs
     */
    function getAgentConstraints(address agentAddress)
        external
        view
        onlyRegisteredAgent(agentAddress)
        returns (bytes32[] memory)
    {
        return _agentConstraints[agentAddress];
    }

    /**
     * @notice Gets the violation history for an agent
     * @param agentAddress The agent to query
     * @return violations Array of violation records
     */
    function getViolationHistory(address agentAddress)
        external
        view
        onlyRegisteredAgent(agentAddress)
        returns (ViolationRecord[] memory)
    {
        return _violationHistory[agentAddress];
    }

    /**
     * @notice Gets the total number of registered agents
     * @return count The number of agents
     */
    function getAgentCount() external view returns (uint256) {
        return _agentAddresses.length;
    }

    /**
     * @notice Checks if an address is a registered agent
     * @param agent The address to check
     * @return registered True if registered
     */
    function isRegistered(address agent) external view returns (bool) {
        return _agents[agent].agentAddress != address(0);
    }

    /**
     * @notice Gets all registered agent addresses
     * @return addresses Array of agent addresses
     */
    function getAllAgents() external view returns (address[] memory) {
        return _agentAddresses;
    }

    /**
     * @notice Gets the constraint contract address for a constraint ID
     * @param constraintId The constraint ID
     * @return contractAddress The constraint contract address
     */
    function getConstraintContract(bytes32 constraintId) external view returns (address) {
        return _constraintContracts[constraintId];
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Records a violation in the agent's history
     */
    function _recordViolation(
        address agentAddress,
        bytes32 constraintId,
        IAIConstraint.SeverityLevel severity,
        bytes memory evidence
    ) internal {
        _violationHistory[agentAddress].push(ViolationRecord({
            constraintId: constraintId,
            severity: severity,
            timestamp: block.timestamp,
            evidence: evidence
        }));

        totalViolations++;

        emit ViolationRecorded(agentAddress, constraintId, severity);

        // Check if agent status should be updated based on severity
        _evaluateAgentStatus(agentAddress, severity);
    }

    /**
     * @notice Evaluates and updates agent status based on violations
     */
    function _evaluateAgentStatus(address agentAddress, IAIConstraint.SeverityLevel severity) internal {
        IAIAgent.AgentInfo storage agent = _agents[agentAddress];

        if (severity == IAIConstraint.SeverityLevel.CRITICAL) {
            // Count critical violations
            uint256 criticalCount = 0;
            ViolationRecord[] memory violations = _violationHistory[agentAddress];
            for (uint256 i = 0; i < violations.length; i++) {
                if (violations[i].severity == IAIConstraint.SeverityLevel.CRITICAL) {
                    criticalCount++;
                }
            }

            if (criticalCount >= AIConstraintLib.MAX_VIOLATIONS_BEFORE_TERMINATION) {
                agent.status = IAIAgent.AgentStatus.TERMINATED;
                emit AgentStatusUpdated(
                    agentAddress,
                    IAIAgent.AgentStatus.ACTIVE,
                    IAIAgent.AgentStatus.TERMINATED,
                    "Exceeded critical violation threshold"
                );
            } else if (criticalCount >= AIConstraintLib.MAX_VIOLATIONS_BEFORE_SUSPENSION) {
                agent.status = IAIAgent.AgentStatus.SUSPENDED;
                emit AgentStatusUpdated(
                    agentAddress,
                    agent.status,
                    IAIAgent.AgentStatus.SUSPENDED,
                    "Critical violation detected"
                );
            }
        } else if (severity == IAIConstraint.SeverityLevel.HIGH) {
            // Count high severity violations
            uint256 highCount = 0;
            ViolationRecord[] memory violations = _violationHistory[agentAddress];
            for (uint256 i = 0; i < violations.length; i++) {
                if (violations[i].severity == IAIConstraint.SeverityLevel.HIGH) {
                    highCount++;
                }
            }

            if (highCount >= AIConstraintLib.MAX_VIOLATIONS_BEFORE_SUSPENSION &&
                agent.status == IAIAgent.AgentStatus.ACTIVE) {
                agent.status = IAIAgent.AgentStatus.RESTRICTED;
                emit AgentStatusUpdated(
                    agentAddress,
                    IAIAgent.AgentStatus.ACTIVE,
                    IAIAgent.AgentStatus.RESTRICTED,
                    "Multiple high severity violations"
                );
            }
        }
    }

    /**
     * @notice Decodes violation reason from evidence bytes
     * @param evidence The encoded evidence bytes
     * @return reason Human-readable reason string
     */
    function _decodeViolationReason(bytes memory evidence) internal pure returns (string memory reason) {
        if (evidence.length < 64) {
            return "Constraint violation detected";
        }
        
        // For simplicity, return a generic message
        // In production, this would properly decode the evidence structure
        return "Constraint violation detected";
    }
}
