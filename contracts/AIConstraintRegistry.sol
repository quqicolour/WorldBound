// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAIConstraint} from "./interfaces/IAIConstraint.sol";
import {IAIAgent} from "./interfaces/IAIAgent.sol";

/**
 * @title AIConstraintRegistry
 * @author WorldBound Team
 * @notice Gas-optimized central registry for AI agents with integrated fee mechanism
 * @dev Optimizations applied:
 * - Custom errors instead of strings (saves ~50+ gas per revert)
 * - Packed variables (structs use uint128 where possible)
 * - Cached storage reads in loops
 * - Batch operations where applicable
 * - Optimized data structures
 */
contract AIConstraintRegistry {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum constraints per agent (255 fits in uint8)
    uint8 constant MAX_CONSTRAINTS_PER_AGENT = 100;

    /// @notice Maximum age for violation reports (7 days)
    uint32 constant MAX_VIOLATION_REPORT_AGE = 7 days;

    /// @notice Cooldown between status changes (1 hour)
    uint32 constant STATUS_CHANGE_COOLDOWN = 1 hours;

    /// @notice Max violations before suspension (HIGH/CRITICAL)
    uint8 constant MAX_VIOLATIONS_BEFORE_SUSPENSION = 3;

    /// @notice Max violations before termination (CRITICAL only)
    uint8 constant MAX_VIOLATIONS_BEFORE_TERMINATION = 2;

    /// @notice Role hash for owner authorization
    bytes32 constant OWNER_ROLE = keccak256("OWNER");

    /// @notice Role hash for governance authorization
    bytes32 constant GOVERNANCE_ROLE = keccak256("GOVERNANCE");

    /*//////////////////////////////////////////////////////////////
                                STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Contract owner (immutable saves gas)
    address public immutable owner;

    /// @notice Governance contract address
    address public governance;

    /// @notice Fee for constraint validation (packed with packerFee)
    /// @dev Default: 0.00001 ETH
    uint128 public constraintCheckFee;

    /// @notice Fee for packer bundling
    /// @dev Default: 0.00002 ETH
    uint128 public packerFee;

    /// @notice Total fee per validation (cached to avoid recalculation)
    uint256 public totalFeePerValidation;

    /// @notice Total fees collected by protocol
    uint256 public totalProtocolFees;

    /// @notice Total fees distributed to packers
    uint256 public totalPackerFeesDistributed;

    /// @notice Whether the registry is paused
    bool public paused;

    /// @notice Padding for alignment (gas optimization)
    uint8 private _padding;

    /*//////////////////////////////////////////////////////////////
                                MAPPINGS
    //////////////////////////////////////////////////////////////*/

    /// @notice AI agent information
    mapping(address => Agent) internal _agents;

    /// @notice AI creator deposited balances
    mapping(address => uint256) public aiCreatorBalances;

    /// @notice Packer claimable bounties
    mapping(address => uint256) public packerBounties;

    /// @notice Authorized packers
    mapping(address => bool) public authorizedPackers;

    /// @notice Constraint contract addresses by constraint ID
    mapping(bytes32 => address) internal _constraintContracts;

    /// @notice Agent constraint lists
    mapping(address => bytes32[]) internal _agentConstraints;

    /// @notice Violation history per agent
    mapping(address => Violation[]) internal _violations;

    /*//////////////////////////////////////////////////////////////
                                ARRAYS
    //////////////////////////////////////////////////////////////*/

    /// @notice All registered agent addresses
    address[] internal _agentList;

    /// @notice All registered constraint contracts
    address[] internal _constraintList;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS (OPTIMIZED)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Optimized agent information struct
     * @dev Packed to fit in fewer storage slots
     */
    struct Agent {
        address agentAddress;
        address owner;
        uint64 registrationTime;
        uint64 lastActivityTime;
        uint8 status; // 0=ACTIVE, 1=RESTRICTED, 2=SUSPENDED, 3=TERMINATED
        bool exists; // Replaces check against address(0)
    }

    /**
     * @notice Optimized violation record
     * @dev Uses uint32 for timestamp (sufficient until 2106)
     */
    struct Violation {
        bytes32 constraintId;
        uint8 severity; // 0=LOW, 1=MEDIUM, 2=HIGH, 3=CRITICAL
        uint32 timestamp;
        bytes evidence;
    }

    /**
     * @notice Validation result
     */
    struct ValidationResult {
        bool valid;
        bytes32 failedConstraint;
        string reason;
    }

    /**
     * @notice Fee breakdown
     */
    struct FeeBreakdown {
        uint128 constraintCheckFee;
        uint128 packerFee;
        uint256 protocolFee;
    }

    /*//////////////////////////////////////////////////////////////
                                CUSTOM ERRORS (GAS SAVINGS)
    //////////////////////////////////////////////////////////////*/

    error Unauthorized(address caller, bytes32 requiredRole);
    error AgentNotFound(address agent);
    error AgentAlreadyExists(address agent);
    error ConstraintNotFound(bytes32 constraintId);
    error TooManyConstraints(uint256 count, uint256 max);
    error InsufficientBalance(uint256 required, uint256 available);
    error InvalidAddress();
    error InvalidAmount();
    error NotAgentOwner();
    error AgentTerminated();
    error StatusUnchanged();
    error RegistryPaused();
    error PackerUnauthorized();
    error NoBountyToClaim();
    error TransferFailed();
    error StringTooLong();
    error ConstraintViolation(bytes32 constraintId, string reason);

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event AgentRegistered(
        address indexed agent,
        address indexed owner,
        string version
    );
    event AgentStatusUpdated(
        address indexed agent,
        uint8 oldStatus,
        uint8 newStatus,
        string reason
    );
    event ConstraintContractRegistered(
        address indexed contractAddress,
        uint256 count
    );
    event ConstraintsAssigned(address indexed agent, uint256 count);
    event ActionValidated(
        address indexed agent,
        bytes32 indexed actionId,
        address indexed packer,
        uint256 fee,
        bool success
    );
    event ViolationRecorded(
        address indexed agent,
        bytes32 indexed constraintId,
        uint8 severity
    );
    event FundsDeposited(
        address indexed agent,
        address indexed creator,
        uint256 amount,
        uint256 newBalance
    );
    event FundsWithdrawn(
        address indexed agent,
        address indexed creator,
        uint256 amount,
        uint256 newBalance
    );
    event BountyClaimed(address indexed packer, uint256 amount);
    event FeesUpdated(
        uint128 constraintCheckFee,
        uint128 packerFee,
        uint256 totalFee
    );
    event PackerAuthorized(address indexed packer, bool authorized);
    event RegistryPauseToggled(bool paused, string reason);
    event GovernanceUpdated(address oldGovernance, address newGovernance);

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized(msg.sender, OWNER_ROLE);
        _;
    }

    modifier onlyGovernance() {
        if (msg.sender != governance && msg.sender != owner) {
            revert Unauthorized(msg.sender, GOVERNANCE_ROLE);
        }
        _;
    }

    modifier onlyAuthorizedPacker() {
        if (!authorizedPackers[msg.sender]) revert PackerUnauthorized();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert RegistryPaused();
        _;
    }

    modifier agentExists(address agent) {
        if (!_agents[agent].exists) revert AgentNotFound(agent);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _governance) {
        owner = msg.sender;
        governance = _governance;

        // Set default fees
        constraintCheckFee = 0.00001 ether;
        packerFee = 0.00002 ether;
        totalFeePerValidation = 0.00003 ether;

        // Auto-authorize deployer as packer
        authorizedPackers[msg.sender] = true;
    }

    /*//////////////////////////////////////////////////////////////
                        FEE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function updateFees(
        uint128 _checkFee,
        uint128 _packerFee
    ) external onlyOwner {
        constraintCheckFee = _checkFee;
        packerFee = _packerFee;
        totalFeePerValidation = uint256(_checkFee) + uint256(_packerFee);
        emit FeesUpdated(_checkFee, _packerFee, totalFeePerValidation);
    }

    function getFeeBreakdown() external view returns (FeeBreakdown memory) {
        return FeeBreakdown(constraintCheckFee, packerFee, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        PACKER MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function authorizePacker(
        address packer,
        bool authorized
    ) external onlyOwner {
        if (packer == address(0)) revert InvalidAddress();
        authorizedPackers[packer] = authorized;
        emit PackerAuthorized(packer, authorized);
    }

    /*//////////////////////////////////////////////////////////////
                        FUND MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function depositFunds(
        address agent
    ) external payable whenNotPaused agentExists(agent) {
        if (msg.value == 0) revert InvalidAmount();
        if (_agents[agent].owner != msg.sender) revert NotAgentOwner();

        uint256 newBalance = aiCreatorBalances[agent] + msg.value;
        aiCreatorBalances[agent] = newBalance;

        emit FundsDeposited(agent, msg.sender, msg.value, newBalance);
    }

    function withdrawFunds(
        address agent,
        uint256 amount
    ) external whenNotPaused agentExists(agent) {
        if (amount == 0) revert InvalidAmount();

        Agent storage a = _agents[agent];
        if (a.owner != msg.sender) revert NotAgentOwner();

        uint256 balance = aiCreatorBalances[agent];
        if (balance < amount) revert InsufficientBalance(amount, balance);

        unchecked {
            aiCreatorBalances[agent] = balance - amount;
        }

        emit FundsWithdrawn(
            agent,
            msg.sender,
            amount,
            aiCreatorBalances[agent]
        );

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    function claimBounty() external whenNotPaused {
        uint256 amount = packerBounties[msg.sender];
        if (amount == 0) revert NoBountyToClaim();

        delete packerBounties[msg.sender];
        totalPackerFeesDistributed += amount;

        emit BountyClaimed(msg.sender, amount);

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    /*//////////////////////////////////////////////////////////////
                        AGENT REGISTRATION
    //////////////////////////////////////////////////////////////*/

    function registerAgent(
        address agent,
        address agentOwner,
        string calldata version,
        bytes32[] calldata constraintIds
    ) external whenNotPaused returns (bool) {
        // Cache length for gas savings
        uint256 idCount = constraintIds.length;

        // Validations
        if (agent == address(0) || agentOwner == address(0))
            revert InvalidAddress();
        if (_agents[agent].exists) revert AgentAlreadyExists(agent);
        if (idCount > MAX_CONSTRAINTS_PER_AGENT)
            revert TooManyConstraints(idCount, MAX_CONSTRAINTS_PER_AGENT);

        // Store agent info (optimized struct)
        _agents[agent] = Agent({
            agentAddress: agent,
            owner: agentOwner,
            registrationTime: uint64(block.timestamp),
            lastActivityTime: uint64(block.timestamp),
            status: 0, // ACTIVE
            exists: true
        });

        _agentList.push(agent);

        // Assign constraints
        if (idCount > 0) {
            bytes32[] storage agentConstraints = _agentConstraints[agent];
            for (uint256 i; i < idCount; ++i) {
                agentConstraints.push(constraintIds[i]);
            }
        }

        emit AgentRegistered(agent, agentOwner, version);
        emit ConstraintsAssigned(agent, idCount);

        return true;
    }

    function updateAgentStatus(
        address agent,
        uint8 newStatus,
        string calldata reason
    ) external onlyGovernance agentExists(agent) {
        Agent storage a = _agents[agent];
        uint8 oldStatus = a.status;

        if (oldStatus == newStatus) revert StatusUnchanged();
        if (oldStatus == 3) revert AgentTerminated(); // TERMINATED

        a.status = newStatus;
        a.lastActivityTime = uint64(block.timestamp);

        emit AgentStatusUpdated(agent, oldStatus, newStatus, reason);
    }

    function assignConstraints(
        address agent,
        bytes32[] calldata constraintIds
    ) external onlyGovernance agentExists(agent) {
        bytes32[] storage existing = _agentConstraints[agent];
        uint256 currentCount = existing.length;
        uint256 newCount = currentCount + constraintIds.length;

        if (newCount > MAX_CONSTRAINTS_PER_AGENT)
            revert TooManyConstraints(newCount, MAX_CONSTRAINTS_PER_AGENT);

        for (uint256 i; i < constraintIds.length; ++i) {
            existing.push(constraintIds[i]);
        }

        emit ConstraintsAssigned(agent, constraintIds.length);
    }

    /*//////////////////////////////////////////////////////////////
                    CONSTRAINT CONTRACT MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function registerConstraintContract(
        address contractAddress
    ) external onlyOwner {
        if (contractAddress == address(0)) revert InvalidAddress();

        IAIConstraint constraint = IAIConstraint(contractAddress);
        uint256 count = constraint.getConstraintCount();

        _constraintList.push(contractAddress);

        // Cache in local variable to reduce storage reads
        mapping(bytes32 => address) storage cc = _constraintContracts;

        for (uint256 i; i < count; ++i) {
            bytes32 id = keccak256(abi.encodePacked(contractAddress, i));
            cc[id] = contractAddress;
        }

        emit ConstraintContractRegistered(contractAddress, count);
    }

    /*//////////////////////////////////////////////////////////////
                        ACTION VALIDATION (OPTIMIZED)
    //////////////////////////////////////////////////////////////*/

    function validateAction(
        address agent,
        bytes calldata actionData
    )
        external
        whenNotPaused
        onlyAuthorizedPacker
        agentExists(agent)
        returns (ValidationResult memory result)
    {
        // Gas: Cache storage reads
        Agent storage a = _agents[agent];
        uint256 fee = totalFeePerValidation;

        // Check balance
        if (aiCreatorBalances[agent] < fee) {
            revert InsufficientBalance(fee, aiCreatorBalances[agent]);
        }

        // Check agent status
        uint8 status = a.status;
        if (status == 2 || status == 3) {
            // SUSPENDED or TERMINATED
            return
                ValidationResult(
                    false,
                    bytes32(0),
                    "Agent status prevents execution"
                );
        }

        // Deduct fee
        unchecked {
            aiCreatorBalances[agent] -= fee;
        }
        packerBounties[msg.sender] += packerFee;
        totalProtocolFees += constraintCheckFee;

        // Validate constraints
        bytes32[] storage constraints = _agentConstraints[agent];
        uint256 constraintCount = constraints.length;

        for (uint256 i; i < constraintCount; ++i) {
            bytes32 id = constraints[i];
            address cc = _constraintContracts[id];

            if (cc == address(0)) continue;

            IAIConstraint constraint = IAIConstraint(cc);
            if (!constraint.isActive(id)) continue;

            (bool compliant, bytes memory evidence) = constraint.validateAction(
                agent,
                actionData
            );

            if (!compliant) {
                _recordViolation(
                    agent,
                    id,
                    constraint.getConstraint(id).severity,
                    evidence
                );

                bytes32 failActionId = keccak256(
                    abi.encodePacked(agent, actionData, block.timestamp)
                );
                emit ActionValidated(
                    agent,
                    failActionId,
                    msg.sender,
                    fee,
                    false
                );

                return ValidationResult(false, id, _decodeReason(evidence));
            }
        }

        a.lastActivityTime = uint64(block.timestamp);

        bytes32 actionId = keccak256(
            abi.encodePacked(agent, actionData, block.timestamp)
        );
        emit ActionValidated(agent, actionId, msg.sender, fee, true);

        return ValidationResult(true, bytes32(0), "");
    }

    function simulateValidation(
        address agent,
        bytes calldata actionData
    ) external view agentExists(agent) returns (ValidationResult memory) {
        Agent storage a = _agents[agent];
        {
            uint8 status = a.status;
            if (status == 2 || status == 3) {
                return
                    ValidationResult(
                        false,
                        bytes32(0),
                        "Agent status prevents execution"
                    );
            }
        }

        bytes32[] storage constraints = _agentConstraints[agent];

        for (uint256 i; i < constraints.length; ++i) {
            bytes32 id = constraints[i];
            address cc = _constraintContracts[id];

            if (cc == address(0)) continue;

            IAIConstraint constraint = IAIConstraint(cc);
            if (!constraint.isActive(id)) continue;

            (bool compliant, bytes memory evidence) = constraint.validateAction(
                agent,
                actionData
            );
            if (!compliant) {
                return ValidationResult(false, id, _decodeReason(evidence));
            }
        }

        return ValidationResult(true, bytes32(0), "");
    }

    function reportViolation(
        address agent,
        bytes32 constraintId,
        bytes calldata evidence
    ) external whenNotPaused agentExists(agent) {
        address cc = _constraintContracts[constraintId];
        if (cc == address(0)) revert ConstraintNotFound(constraintId);

        IAIConstraint constraint = IAIConstraint(cc);
        IAIConstraint.Constraint memory info = constraint.getConstraint(
            constraintId
        );

        _recordViolation(agent, constraintId, info.severity, evidence);
        constraint.reportViolation(agent, evidence);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function togglePause(
        bool _paused,
        string calldata reason
    ) external onlyOwner {
        paused = _paused;
        emit RegistryPauseToggled(_paused, reason);
    }

    function setGovernance(address _governance) external onlyOwner {
        if (_governance == address(0)) revert InvalidAddress();
        address old = governance;
        governance = _governance;
        emit GovernanceUpdated(old, _governance);
    }

    function emergencyWithdraw(
        address recipient,
        uint256 amount
    ) external onlyGovernance {
        if (recipient == address(0)) revert InvalidAddress();
        (bool success, ) = payable(recipient).call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getAgent(
        address agent
    ) external view agentExists(agent) returns (Agent memory) {
        return _agents[agent];
    }

    function getAgentConstraints(
        address agent
    ) external view agentExists(agent) returns (bytes32[] memory) {
        return _agentConstraints[agent];
    }

    function getViolations(
        address agent
    ) external view agentExists(agent) returns (Violation[] memory) {
        return _violations[agent];
    }

    function getAgentCount() external view returns (uint256) {
        return _agentList.length;
    }

    function isRegistered(address agent) external view returns (bool) {
        return _agents[agent].exists;
    }

    function getAllAgents() external view returns (address[] memory) {
        return _agentList;
    }

    function getConstraintContract(bytes32 id) external view returns (address) {
        return _constraintContracts[id];
    }

    function getBalance(
        address agent
    ) external view agentExists(agent) returns (uint256) {
        return aiCreatorBalances[agent];
    }

    function hasSufficientBalance(
        address agent,
        uint256 validations
    ) external view agentExists(agent) returns (bool) {
        return aiCreatorBalances[agent] >= totalFeePerValidation * validations;
    }

    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _recordViolation(
        address agent,
        bytes32 constraintId,
        uint8 severity,
        bytes memory evidence
    ) internal {
        _violations[agent].push(
            Violation({
                constraintId: constraintId,
                severity: severity,
                timestamp: uint32(block.timestamp),
                evidence: evidence
            })
        );

        emit ViolationRecorded(agent, constraintId, severity);
        _evaluateStatus(agent, severity);
    }

    function _evaluateStatus(address agent, uint8 severity) internal {
        Agent storage a = _agents[agent];

        // CRITICAL violations
        if (severity == 3) {
            uint256 criticalCount;
            Violation[] storage v = _violations[agent];

            for (uint256 i; i < v.length; ++i) {
                if (v[i].severity == 3) ++criticalCount;
            }

            if (criticalCount >= MAX_VIOLATIONS_BEFORE_TERMINATION) {
                a.status = 3; // TERMINATED
                emit AgentStatusUpdated(
                    agent,
                    a.status,
                    3,
                    "Critical threshold exceeded"
                );
                return;
            } else if (
                criticalCount >= MAX_VIOLATIONS_BEFORE_SUSPENSION &&
                a.status == 0
            ) {
                a.status = 2; // SUSPENDED
                emit AgentStatusUpdated(
                    agent,
                    0,
                    2,
                    "Critical violation detected"
                );
                return;
            }
        }

        // HIGH violations
        if (severity == 2 && a.status == 0) {
            uint256 highCount;
            Violation[] storage v = _violations[agent];

            for (uint256 i; i < v.length; ++i) {
                if (v[i].severity == 2) ++highCount;
            }

            if (highCount >= MAX_VIOLATIONS_BEFORE_SUSPENSION) {
                a.status = 1; // RESTRICTED
                emit AgentStatusUpdated(
                    agent,
                    0,
                    1,
                    "High severity threshold exceeded"
                );
            }
        }
    }

    function _decodeReason(
        bytes memory evidence
    ) internal pure returns (string memory) {
        if (evidence.length < 64) return "Constraint violation";
        return "Constraint violation";
    }

    receive() external payable {}
}
