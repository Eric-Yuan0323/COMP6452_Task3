// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ParticipantRegistry} from "./ParticipantRegistry.sol";
import {BatchRegistry} from "./BatchRegistry.sol";

/// @title ColdChainCompliance
/// @notice Verifies signed sensor observations and applies compliance rules.
/// @dev FR3: Cold-Chain Compliance & Recall.
contract ColdChainCompliance {
    struct LatestReading {
        int16 temperatureTenths;
        uint64 measuredAt;
        address sensor;
        bool violation;
    }

    ParticipantRegistry public immutable participantRegistry;
    BatchRegistry public immutable batchRegistry;
    address public immutable administrator;

    // Temperatures are represented in tenths of a degree Celsius.
    int16 public minimumTemperatureTenths = 0;
    int16 public maximumTemperatureTenths = 60;
    uint64 public maximumReadingAge = 10 minutes;

    mapping(uint256 => LatestReading) private latestReadings;
    mapping(address => mapping(uint256 => bool)) public usedNonces;

    event TemperatureReadingAccepted(
        uint256 indexed batchId,
        address indexed sensor,
        int16 temperatureTenths,
        uint64 measuredAt,
        uint256 nonce,
        bool violation
    );
    event ThresholdsChanged(int16 minimumTemperatureTenths, int16 maximumTemperatureTenths);
    event MaximumReadingAgeChanged(uint64 maximumReadingAge);
    event RecallRequested(uint256 indexed batchId, address indexed requester, string reason);

    error OnlyAdministrator();
    error InvalidAddress();
    error InvalidThreshold();
    error BatchNotFound();
    error InvalidTimestamp();
    error InvalidSignature();
    error SensorNotActive();
    error WrongSensorOperator();
    error NonceAlreadyUsed();
    error NotAuthorisedToRecall();

    modifier onlyAdministrator() {
        if (msg.sender != administrator) revert OnlyAdministrator();
        _;
    }

    constructor(address participantRegistryAddress, address batchRegistryAddress) {
        if (participantRegistryAddress == address(0) || batchRegistryAddress == address(0)) {
            revert InvalidAddress();
        }

        participantRegistry = ParticipantRegistry(participantRegistryAddress);
        batchRegistry = BatchRegistry(batchRegistryAddress);
        administrator = msg.sender;
    }

    function setTemperatureThresholds(int16 minimumTenths, int16 maximumTenths) external onlyAdministrator {
        if (minimumTenths >= maximumTenths) revert InvalidThreshold();

        minimumTemperatureTenths = minimumTenths;
        maximumTemperatureTenths = maximumTenths;

        emit ThresholdsChanged(minimumTenths, maximumTenths);
    }

    function setMaximumReadingAge(uint64 newMaximumAge) external onlyAdministrator {
        if (newMaximumAge == 0) revert InvalidThreshold();

        maximumReadingAge = newMaximumAge;
        emit MaximumReadingAgeChanged(newMaximumAge);
    }

    /// @notice Digest to be signed by the IoT sensor's Ethereum account.
    function getReadingDigest(uint256 batchId, int16 temperatureTenths, uint64 measuredAt, uint256 nonce)
        public
        view
        returns (bytes32)
    {
        return keccak256(abi.encode(address(this), block.chainid, batchId, temperatureTenths, measuredAt, nonce));
    }

    /// @notice Anyone may relay data, but only an approved sensor signature is trusted.
    function submitSignedReading(
        uint256 batchId,
        int16 temperatureTenths,
        uint64 measuredAt,
        uint256 nonce,
        bytes calldata signature
    ) external {
        if (!batchRegistry.batchExists(batchId)) revert BatchNotFound();

        if (measuredAt > block.timestamp || block.timestamp - measuredAt > maximumReadingAge) {
            revert InvalidTimestamp();
        }

        bytes32 digest = getReadingDigest(batchId, temperatureTenths, measuredAt, nonce);

        address sensor = _recoverSigner(digest, signature);

        if (!participantRegistry.isActiveSensor(sensor)) {
            revert SensorNotActive();
        }

        if (usedNonces[sensor][nonce]) revert NonceAlreadyUsed();

        address currentCustodian = batchRegistry.getCurrentCustodian(batchId);

        if (participantRegistry.getSensorOperator(sensor) != currentCustodian) {
            revert WrongSensorOperator();
        }

        // Checks are complete before state changes.
        usedNonces[sensor][nonce] = true;

        bool violation = temperatureTenths < minimumTemperatureTenths || temperatureTenths > maximumTemperatureTenths;

        latestReadings[batchId] = LatestReading({
            temperatureTenths: temperatureTenths, measuredAt: measuredAt, sensor: sensor, violation: violation
        });

        if (violation) {
            batchRegistry.markNonCompliant(batchId);
        }

        emit TemperatureReadingAccepted(batchId, sensor, temperatureTenths, measuredAt, nonce, violation);
    }

    /// @notice The administrator or current custodian may request a recall.
    function requestRecall(uint256 batchId, string calldata reason) external {
        if (!batchRegistry.batchExists(batchId)) revert BatchNotFound();

        if (msg.sender != administrator && msg.sender != batchRegistry.getCurrentCustodian(batchId)) {
            revert NotAuthorisedToRecall();
        }

        batchRegistry.recallBatch(batchId, reason);
        emit RecallRequested(batchId, msg.sender, reason);
    }

    function getLatestReading(uint256 batchId) external view returns (LatestReading memory) {
        return latestReadings[batchId];
    }

    function _recoverSigner(bytes32 digest, bytes calldata signature) internal pure returns (address signer) {
        if (signature.length != 65) revert InvalidSignature();

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        if (v < 27) v += 27;
        if (v != 27 && v != 28) revert InvalidSignature();

        bytes32 signedDigest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));

        signer = ecrecover(signedDigest, v, r, s);
        if (signer == address(0)) revert InvalidSignature();
    }
}
