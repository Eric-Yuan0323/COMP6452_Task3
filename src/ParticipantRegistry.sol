// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ParticipantRegistry
/// @notice Implements participant and IoT-device registration with embedded permissions.
/// @dev FR1: Participant & Device Registration.
contract ParticipantRegistry {
    enum Role {
        None,
        Farm,
        Processor,
        Logistics,
        Retailer
    }

    struct Participant {
        string name;
        Role role;
        bool active;
    }

    struct Sensor {
        address operator;
        bool active;
    }

    address public immutable administrator;

    mapping(address => Participant) private participants;
    mapping(address => Sensor) private sensors;

    event ParticipantRegistered(address indexed account, Role indexed role, string name);
    event ParticipantStatusChanged(address indexed account, bool active);
    event SensorRegistered(address indexed sensor, address indexed operator);
    event SensorStatusChanged(address indexed sensor, bool active);

    error OnlyAdministrator();
    error InvalidAddress();
    error InvalidRole();
    error AlreadyRegistered();
    error ParticipantNotActive();
    error SensorNotRegistered();
    error NotAuthorised();

    modifier onlyAdministrator() {
        if (msg.sender != administrator) revert OnlyAdministrator();
        _;
    }

    constructor() {
        administrator = msg.sender;
    }

    function registerParticipant(address account, Role role, string calldata name) external onlyAdministrator {
        if (account == address(0)) revert InvalidAddress();
        if (role == Role.None) revert InvalidRole();
        if (participants[account].role != Role.None) revert AlreadyRegistered();

        participants[account] = Participant({name: name, role: role, active: true});

        emit ParticipantRegistered(account, role, name);
    }

    function setParticipantActive(address account, bool active) external onlyAdministrator {
        if (participants[account].role == Role.None) {
            revert ParticipantNotActive();
        }

        participants[account].active = active;
        emit ParticipantStatusChanged(account, active);
    }

    /// @notice An active supply-chain participant registers a sensor it controls.
    function registerSensor(address sensor) external {
        if (!isActiveParticipant(msg.sender)) revert ParticipantNotActive();
        if (sensor == address(0)) revert InvalidAddress();
        if (sensors[sensor].operator != address(0)) revert AlreadyRegistered();

        sensors[sensor] = Sensor({operator: msg.sender, active: true});

        emit SensorRegistered(sensor, msg.sender);
    }

    /// @notice A sensor can be disabled by its operator or the administrator.
    function setSensorActive(address sensor, bool active) external {
        Sensor storage storedSensor = sensors[sensor];

        if (storedSensor.operator == address(0)) revert SensorNotRegistered();
        if (msg.sender != storedSensor.operator && msg.sender != administrator) {
            revert NotAuthorised();
        }

        storedSensor.active = active;
        emit SensorStatusChanged(sensor, active);
    }

    function getParticipant(address account) external view returns (Participant memory) {
        return participants[account];
    }

    function getSensor(address sensor) external view returns (Sensor memory) {
        return sensors[sensor];
    }

    function isActiveParticipant(address account) public view returns (bool) {
        return participants[account].role != Role.None && participants[account].active;
    }

    function getRole(address account) external view returns (Role) {
        return participants[account].role;
    }

    function isActiveSensor(address sensor) external view returns (bool) {
        return sensors[sensor].operator != address(0) && sensors[sensor].active;
    }

    function getSensorOperator(address sensor) external view returns (address) {
        return sensors[sensor].operator;
    }
}
