// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IAIConstraint
 * @notice Gas-optimized interface for AI constraint contracts
 * @dev Uses uint8 for enums to save gas
 */
interface IAIConstraint {
    /*//////////////////////////////////////////////////////////////
                                ENUMS
    //////////////////////////////////////////////////////////////*/
    //约束类型
    enum ConstraintCategory { 
        PRIVACY,         //隐私
        SECURITY,        //安全性
        HUMAN_SAFETY,    //人类安全
        ETHICS,          //行为准则
        TRANSPARENCY     //清晰度
    }
    //安全等级
    enum SeverityLevel { 
        LOW,        //低
        MEDIUM,     //中
        HIGH,       //高
        CRITICAL    //极其严重
    }

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    //AI约束结构体
    struct Constraint {
        bytes32 id;                //AI的id编号   
        uint8 category;            //种类
        string description;        //描述
        uint256 score;             //AI获得的人类评分
        uint8 severity;            //安全分数
        bool active;               //是否活跃，24小时汇报一次
        uint64 createdAt;          //创建时间
        uint64 updatedAt;          //更新时间
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    //AI约束注册事件
    event ConstraintRegistered(bytes32 indexed id, uint8 category, uint8 severity);
    //AI约束更新事件
    event ConstraintUpdated(bytes32 indexed id, uint8 category, uint8 severity);
    //AI约束活跃状态事件
    event ConstraintToggled(bytes32 indexed id, bool active);
    //AI违约事件报告
    event ViolationReported(address indexed agent, bytes32 indexed constraintId, uint8 severity, bytes evidence);

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function registerConstraint(
        uint8 category, 
        string memory description, 
        uint8 severity
    )
        external
        returns (bytes32 id);
    function updateConstraint(bytes32 id, string calldata description, uint8 severity, bool active) external;
    function validateAction(address agent, bytes calldata actionData) external view returns (bool compliant, bytes memory evidence);
    function reportViolation(address agent, bytes calldata evidence) external;
    function getConstraint(bytes32 id) external view returns (Constraint memory);
    function isActive(bytes32 id) external view returns (bool);
    function getConstraintCount() external view returns (uint256);
}
