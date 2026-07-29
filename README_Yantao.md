# Yantao – Tests & Demo Automation

This document summarises the work completed for testing and demonstration.

---

# 1. Unit Tests

Implemented and verified unit tests for all three smart contracts.

| Contract | Tests |
|----------|------:|
| ParticipantRegistry | 4 |
| BatchRegistry | 4 |
| ColdChainCompliance | 10 |

Total:

```
18 Unit Tests
```

Run:

```bash
forge test
```

---

# 2. Integration Tests

File:

```
test/Integration.t.sol
```

Implemented two end-to-end integration tests.

## Test 1 – Complete Supply Chain Flow

```
Farm
    ↓
Processor
    ↓
Logistics
    ↓
Retailer
```

Validates:

- participant registration
- batch creation
- custody transfer
- compliant temperature submission
- Delivered workflow

---

## Test 2 – Temperature Violation

```
Create Batch
      ↓
Submit 9.5°C
      ↓
Violation
      ↓
NonCompliant
```

Validates:

- oracle submission
- compliance checking
- automatic batch status update

Run only integration tests:

```bash
forge test --match-path test/Integration.t.sol -vv
```

---

# 3. Demo Automation

File:

```
run_demo.sh
```

The script automatically performs the complete demonstration.

Workflow:

```
Build contracts
        ↓
Run all tests
        ↓
Create demo batch
        ↓
Submit 4.0°C reading
        ↓
Submit 9.5°C reading
        ↓
Batch becomes NonCompliant
```

Run:

```bash
chmod +x run_demo.sh
./run_demo.sh
```

---

# Prerequisites

Before running the demo:

1.

```
anvil
```

2.

Deploy contracts

```bash
forge script script/Deploy.s.sol \
    --rpc-url http://127.0.0.1:8545 \
    --broadcast
```

3.

Update `.env` with:

```
PARTICIPANT_REGISTRY

BATCH_REGISTRY

COMPLIANCE
```

---

# Expected Output

Successful execution should show:

```
20 tests passed

↓

Batch created

↓

Violation: false

↓

Violation: true

↓

Batch status: NonCompliant

↓

DEMO COMPLETE
```

---

# Relationship with Visual Demo

The demo automation generates the data used by the visual interface.

Available information includes:

- Batch ID
- Current Custodian
- Latest Temperature
- Batch Status
- Violation Status
- Transaction Hash
- Block Number

The visual interface can query or display these values.

---

# Files Added

```
test/Integration.t.sol

run_demo.sh

README_Yantao.md
```

## Notes

The visual demo can directly use the generated blockchain and off-chain data. No modification to the testing or automation scripts should be required.