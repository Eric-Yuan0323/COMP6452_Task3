// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ParticipantRegistry} from "./ParticipantRegistry.sol";

/// @title BatchRegistry
/// @notice Maintains trust-critical milk-batch and custody state on-chain.
/// @dev FR2: Batch & Custody Traceability.
contract BatchRegistry {
    enum Status {
        None,
        Created,
        InTransit,
        Delivered,
        NonCompliant,
        Recalled
    }

    struct Batch {
        bytes32 metadataHash;
        address creator;
        address currentCustodian;
        Status status;
        uint64 createdAt;
        uint32 custodyTransfers;
    }

    ParticipantRegistry public immutable participantRegistry;
    address public immutable administrator;
    address public complianceContract;

    uint256 public nextBatchId = 1;
    mapping(uint256 => Batch) private batches;

    event ComplianceContractSet(address indexed complianceContract);
    event BatchCreated(uint256 indexed batchId, address indexed farm, bytes32 indexed metadataHash);
    event CustodyTransferred(
        uint256 indexed batchId, address indexed previousCustodian, address indexed newCustodian, Status newStatus
    );
    event BatchMarkedNonCompliant(uint256 indexed batchId);
    event BatchRecalled(uint256 indexed batchId, string reason);

    error OnlyAdministrator();
    error OnlyComplianceContract();
    error InvalidAddress();
    error ParticipantNotActive();
    error OnlyFarmCanCreate();
    error BatchNotFound();
    error NotCurrentCustodian();
    error InvalidCustodyTransition();
    error FinalState();

    modifier onlyAdministrator() {
        if (msg.sender != administrator) revert OnlyAdministrator();
        _;
    }

    modifier onlyComplianceContract() {
        if (msg.sender != complianceContract) {
            revert OnlyComplianceContract();
        }
        _;
    }

    constructor(address participantRegistryAddress) {
        if (participantRegistryAddress == address(0)) revert InvalidAddress();

        participantRegistry = ParticipantRegistry(participantRegistryAddress);
        administrator = msg.sender;
    }

    function setComplianceContract(address contractAddress) external onlyAdministrator {
        if (contractAddress == address(0)) revert InvalidAddress();

        complianceContract = contractAddress;
        emit ComplianceContractSet(contractAddress);
    }

    /// @notice Stores only a metadata hash on-chain; detailed batch data stays off-chain.
    function createBatch(bytes32 metadataHash) external returns (uint256 batchId) {
        if (!participantRegistry.isActiveParticipant(msg.sender)) {
            revert ParticipantNotActive();
        }

        if (participantRegistry.getRole(msg.sender) != ParticipantRegistry.Role.Farm) {
            revert OnlyFarmCanCreate();
        }

        batchId = nextBatchId;
        nextBatchId += 1;

        batches[batchId] = Batch({
            metadataHash: metadataHash,
            creator: msg.sender,
            currentCustodian: msg.sender,
            status: Status.Created,
            createdAt: uint64(block.timestamp),
            custodyTransfers: 0
        });

        emit BatchCreated(batchId, msg.sender, metadataHash);
    }

    /// @notice Enforces the expected supply-chain sequence.
    function transferCustody(uint256 batchId, address newCustodian) external {
        Batch storage batch = _getExistingBatch(batchId);

        if (batch.currentCustodian != msg.sender) {
            revert NotCurrentCustodian();
        }

        if (!participantRegistry.isActiveParticipant(newCustodian)) {
            revert ParticipantNotActive();
        }

        if (batch.status == Status.Delivered || batch.status == Status.Recalled) {
            revert FinalState();
        }

        ParticipantRegistry.Role fromRole = participantRegistry.getRole(msg.sender);
        ParticipantRegistry.Role toRole = participantRegistry.getRole(newCustodian);

        if (!_validTransition(fromRole, toRole)) {
            revert InvalidCustodyTransition();
        }

        address previousCustodian = batch.currentCustodian;
        batch.currentCustodian = newCustodian;
        batch.custodyTransfers += 1;

        if (toRole == ParticipantRegistry.Role.Retailer) {
            batch.status = Status.Delivered;
        } else {
            batch.status = Status.InTransit;
        }

        emit CustodyTransferred(batchId, previousCustodian, newCustodian, batch.status);
    }

    function markNonCompliant(uint256 batchId) external onlyComplianceContract {
        Batch storage batch = _getExistingBatch(batchId);

        if (batch.status == Status.Delivered || batch.status == Status.Recalled) {
            revert FinalState();
        }

        batch.status = Status.NonCompliant;
        emit BatchMarkedNonCompliant(batchId);
    }

    function recallBatch(uint256 batchId, string calldata reason) external onlyComplianceContract {
        Batch storage batch = _getExistingBatch(batchId);

        if (batch.status == Status.Recalled) revert FinalState();

        batch.status = Status.Recalled;
        emit BatchRecalled(batchId, reason);
    }

    function getBatch(uint256 batchId) external view returns (Batch memory) {
        Batch memory batch = batches[batchId];
        if (batch.status == Status.None) revert BatchNotFound();
        return batch;
    }

    function batchExists(uint256 batchId) external view returns (bool) {
        return batches[batchId].status != Status.None;
    }

    function getCurrentCustodian(uint256 batchId) external view returns (address) {
        Batch memory batch = batches[batchId];
        if (batch.status == Status.None) revert BatchNotFound();
        return batch.currentCustodian;
    }

    function _getExistingBatch(uint256 batchId) internal view returns (Batch storage batch) {
        batch = batches[batchId];
        if (batch.status == Status.None) revert BatchNotFound();
    }

    function _validTransition(ParticipantRegistry.Role fromRole, ParticipantRegistry.Role toRole)
        internal
        pure
        returns (bool)
    {
        return (fromRole == ParticipantRegistry.Role.Farm && toRole == ParticipantRegistry.Role.Processor)
            || (fromRole == ParticipantRegistry.Role.Processor && toRole == ParticipantRegistry.Role.Logistics)
            || (fromRole == ParticipantRegistry.Role.Logistics && toRole == ParticipantRegistry.Role.Retailer);
    }
}
