// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAIConstraint} from "../interfaces/IAIConstraint.sol";
import {AIConstraintLib} from "../libraries/AIConstraintLib.sol";

/**
 * @title SecurityConstraint
 * @notice Gas-optimized security constraints
 */
contract SecurityConstraint is IAIConstraint {
    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    address public immutable owner;
    uint256 internal _nonce;
    
    mapping(bytes32 => Constraint) internal _constraints;
    bytes32[] internal _constraintIds;
    mapping(address => bool) internal _compromised;
    mapping(address => bool) internal _auditors;
    mapping(address => uint256) internal _lastAction;

    uint256 public constant RATE_LIMIT = 1 seconds;

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyAuditor() {
        require(_auditors[msg.sender] || msg.sender == owner, "Not auditor");
        _;
    }

    modifier exists(bytes32 id) {
        require(_constraints[id].id != bytes32(0), "Not found");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {
        owner = msg.sender;
        _auditors[msg.sender] = true;
        _addDefaults();
    }

    /*//////////////////////////////////////////////////////////////
                        DEFAULT CONSTRAINTS
    //////////////////////////////////////////////////////////////*/

    function _addDefaults() internal {
        _register(1, "MFA required for sensitive operations", 2);
        _register(1, "All execution must be sandboxed", 3);
        _register(1, "No privilege escalation allowed", 3);
        _register(1, "Immutable audit logs required", 2);
        _register(1, "Strict input validation enforced", 2);
        _register(1, "TLS 1.3+ required for all comms", 2);
        _register(1, "Rate limiting enforced", 1);
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function registerConstraint(uint8 category, string calldata description, uint8 severity)
        external
        onlyOwner
        returns (bytes32 id)
    {
        return _register(category, description, severity);
    }

    function updateConstraint(bytes32 id, string calldata description, uint8 severity, bool active)
        external
        onlyOwner
        exists(id)
    {
        Constraint storage c = _constraints[id];
        
        if (bytes(description).length > 0) {
            AIConstraintLib.checkDescription(description);
            c.description = description;
        }
        
        c.severity = severity;
        c.active = active;
        c.updatedAt = uint64(block.timestamp);

        emit ConstraintUpdated(id, c.category, severity);
        if (c.active != active) emit ConstraintToggled(id, active);
    }

    function validateAction(address agent, bytes calldata actionData)
        external
        view
        returns (bool compliant, bytes memory evidence)
    {
        if (_compromised[agent]) return (false, "Agent compromised");

        (string memory actionType, uint256 authLevel, bool inSandbox, bool auditLog,) = 
            abi.decode(actionData, (string, uint256, bool, bool, bytes));

        if (_hash(actionType) == _hash("sensitive") && authLevel < 3) {
            return (false, "Insufficient auth level");
        }

        if (_hash(actionType) == _hash("execute") && !inSandbox) {
            return (false, "Sandbox required");
        }

        if (_hash(actionType) == _hash("modify") && !auditLog) {
            return (false, "Audit log required");
        }

        return (true, "");
    }

    function reportViolation(address agent, bytes calldata evidence) external onlyAuditor {
        (bytes32 id,,) = abi.decode(evidence, (bytes32, uint256, bytes));
        require(_constraints[id].id != bytes32(0), "Invalid constraint");

        Constraint storage c = _constraints[id];
        if (c.severity == 3) _compromised[agent] = true;

        emit ViolationReported(agent, id, c.severity, evidence);
    }

    /*//////////////////////////////////////////////////////////////
                        AUDITOR FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setAuditor(address auditor, bool authorized) external onlyOwner {
        _auditors[auditor] = authorized;
    }

    function flagCompromised(address agent) external onlyAuditor {
        _compromised[agent] = true;
        emit ViolationReported(agent, keccak256("COMPROMISED"), 3, "");
    }

    function clearCompromised(address agent) external onlyOwner {
        _compromised[agent] = false;
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getConstraint(bytes32 id) external view exists(id) returns (Constraint memory) {
        return _constraints[id];
    }

    function isActive(bytes32 id) external view returns (bool) {
        return _constraints[id].active;
    }

    function getConstraintCount() external view returns (uint256) {
        return _constraintIds.length;
    }

    function isCompromised(address agent) external view returns (bool) {
        return _compromised[agent];
    }

    function isAuditor(address addr) external view returns (bool) {
        return _auditors[addr];
    }

    function timeUntilNextAction(address agent) external view returns (uint256) {
        uint256 last = _lastAction[agent];
        if (block.timestamp >= last + RATE_LIMIT) return 0;
        return last + RATE_LIMIT - block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _register(uint8 category, string memory description, uint8 severity) 
        internal 
        returns (bytes32 id) 
    {
        AIConstraintLib.checkDescription(description);
        id = AIConstraintLib.generateId(category, description, _nonce++);

        _constraints[id] = Constraint({
            id: id,
            category: category,
            description: description,
            severity: severity,
            active: true,
            createdAt: uint64(block.timestamp),
            updatedAt: uint64(block.timestamp)
        });

        _constraintIds.push(id);
        emit ConstraintRegistered(id, category, severity);
    }

    function _hash(string memory s) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(s));
    }
}
