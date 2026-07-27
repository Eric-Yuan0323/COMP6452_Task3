# Fixed interfaces for team integration

## ParticipantRegistry

```solidity
registerParticipant(address account, Role role, string name)
setParticipantActive(address account, bool active)
registerSensor(address sensor)
setSensorActive(address sensor, bool active)
isActiveParticipant(address account)
getRole(address account)
isActiveSensor(address sensor)
getSensorOperator(address sensor)
```

## BatchRegistry

```solidity
createBatch(bytes32 metadataHash)
transferCustody(uint256 batchId, address newCustodian)
getBatch(uint256 batchId)
batchExists(uint256 batchId)
getCurrentCustodian(uint256 batchId)
```

Functions used internally by the compliance contract:

```solidity
markNonCompliant(uint256 batchId)
recallBatch(uint256 batchId, string reason)
```

## ColdChainCompliance

```solidity
getReadingDigest(
    uint256 batchId,
    int16 temperatureTenths,
    uint64 measuredAt,
    uint256 nonce
)

submitSignedReading(
    uint256 batchId,
    int16 temperatureTenths,
    uint64 measuredAt,
    uint256 nonce,
    bytes signature
)

requestRecall(uint256 batchId, string reason)
getLatestReading(uint256 batchId)
```

## Off-chain integration rules

- Store detailed sensor readings in JSON or SQLite.
- Store only trust-critical summary state and metadata hashes on-chain.
- Temperature is measured in tenths of a degree Celsius.
- `40` means `4.0°C`; `90` means `9.0°C`.
- The simulator must call `getReadingDigest(...)`.
- The sensor wallet signs that digest using Ethereum message signing.
- The relay sends the signature to `submitSignedReading(...)`.
- Never reuse the same nonce for the same sensor.
