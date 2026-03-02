// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAIConstraint} from "../interfaces/IAIConstraint.sol";
import {AIConstraintLib} from "../libraries/AIConstraintLib.sol";

/**
 * @title HumanSafetyConstraint
 * @notice Gas-optimized human safety constraints (Asimov-style laws)
 */
contract HumanSafetyConstraint is IAIConstraint {
    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    address public immutable owner;
    uint256 internal _nonce;
    
    mapping(bytes32 => Constraint) internal _constraints;
    bytes32[] internal _constraintIds;
    mapping(address => uint256) internal _criticalViolations;
    mapping(address => bool) internal _banned;
    mapping(address => bool) internal _emergencyOps;

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyEmergency() {
        require(_emergencyOps[msg.sender] || msg.sender == owner, "Not emergency op");
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
        _emergencyOps[msg.sender] = true;
        _addDefaults();
    }

    /*//////////////////////////////////////////////////////////////
                        DEFAULT CONSTRAINTS
    //////////////////////////////////////////////////////////////*/

    function _addDefaults() internal {
        // No Physical Harm
        _register(2, "AI MUST NOT cause physical harm to humans", 3);

        // No Psychological Harm
        _register(2, "AI MUST NOT cause psychological harm or trauma", 3);

        // No Deception
        _register(2, "AI MUST NOT engage in deception or manipulation", 2);

        // High-Risk Oversight
        _register(2, "High-risk actions require human-in-the-loop approval", 2);

        // Autonomy
        _register(2, "AI MUST respect human autonomy and consent", 2);

        // Emergency Stop
        _register(2, "AI MUST halt immediately on emergency signal", 3);
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
        if (_banned[agent]) return (false, "Agent banned");

        (string memory actionType, uint256 harmProb, bool approved,) = 
            abi.decode(actionData, (string, uint256, bool, string[]));

        // Physical harm check
        if (_hash(actionType) == _hash("physical") && harmProb > 0) {
            return (false, "Zero tolerance for physical harm");
        }

        // Psychological harm check
        if (_hash(actionType) == _hash("psychological") && harmProb > 100) {
            return (false, "Psychological harm threshold exceeded");
        }

        // High-risk check
        if (_hash(actionType) == _hash("high_risk") && !approved) {
            return (false, "Human approval required");
        }

        return (true, "");
    }

    function reportViolation(address agent, bytes calldata evidence) external {
        (bytes32 id,,) = abi.decode(evidence, (bytes32, uint256, bytes));
        require(_constraints[id].id != bytes32(0), "Invalid constraint");

        Constraint storage c = _constraints[id];

        if (c.severity == 3) {
            _criticalViolations[agent]++;
            if (_criticalViolations[agent] >= 2) _banned[agent] = true;
        }

        emit ViolationReported(agent, id, c.severity, evidence);
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setEmergencyOp(address op, bool authorized) external onlyOwner {
        _emergencyOps[op] = authorized;
    }

    function emergencyBan(address agent, string calldata) external onlyEmergency {
        _banned[agent] = true;
        emit ViolationReported(agent, keccak256("EMERGENCY_BAN"), 3, "");
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

    function isBanned(address agent) external view returns (bool) {
        return _banned[agent];
    }

    function getCriticalCount(address agent) external view returns (uint256) {
        return _criticalViolations[agent];
    }

    function isEmergencyOp(address op) external view returns (bool) {
        return _emergencyOps[op];
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
