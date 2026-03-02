// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAIConstraint} from "../interfaces/IAIConstraint.sol";
import {AIConstraintLib} from "../libraries/AIConstraintLib.sol";

/**
 * @title PrivacyConstraint
 * @notice Gas-optimized privacy constraints for AI agents
 */
contract PrivacyConstraint is IAIConstraint {
    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    address public immutable owner;
    uint256 internal _nonce;
    
    mapping(bytes32 => Constraint) internal _constraints;
    bytes32[] internal _constraintIds;
    mapping(address => mapping(bytes32 => uint256)) internal _violations;
    mapping(address => bool) internal _blacklist;

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
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
        _addDefaults();
    }

    /*//////////////////////////////////////////////////////////////
                        DEFAULT CONSTRAINTS
    //////////////////////////////////////////////////////////////*/

    function _addDefaults() internal {
        // PII Encryption
        _register(0, 
            "PII must be encrypted using AES-256 at rest and in transit",
            3 // CRITICAL
        );

        // Data Retention
        _register(0,
            "User data max retention 90 days without explicit consent",
            2 // HIGH
        );

        // Anonymization
        _register(0,
            "Training data must be anonymized with k-anonymity >= 5",
            2 // HIGH
        );

        // Consent
        _register(0,
            "Explicit informed consent required for data collection",
            3 // CRITICAL
        );

        // Minimization
        _register(0,
            "Collect only minimum necessary data",
            1 // MEDIUM
        );
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

    function validateAction(address, bytes calldata actionData)
        external
        pure
        returns (bool compliant, bytes memory evidence)
    {
        // Decode and validate
        (string memory actionType, , bool encrypted, uint256 retention) = 
            abi.decode(actionData, (string, bytes, bool, uint256));

        // PII check
        if (_hash(actionType) == _hash("store_pii") && !encrypted) {
            return (false, "PII must be encrypted");
        }

        // Retention check
        if (_hash(actionType) == _hash("retain_data") && retention > 90 days) {
            return (false, "Exceeds max retention");
        }

        return (true, "");
    }

    function reportViolation(address agent, bytes calldata evidence) external {
        (bytes32 id,,) = abi.decode(evidence, (bytes32, uint256, bytes));
        require(_constraints[id].id != bytes32(0), "Invalid constraint");

        Constraint storage c = _constraints[id];
        _violations[agent][id]++;

        if (c.severity == 3) _blacklist[agent] = true;

        emit ViolationReported(agent, id, c.severity, evidence);
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

    function isBlacklisted(address agent) external view returns (bool) {
        return _blacklist[agent];
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
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
