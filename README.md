# Fresh Milk Traceability — Deployment and Blockchain Interaction

This section documents the deployment and on-chain interaction work completed
for the fresh-milk traceability system. The three smart contracts were deployed
to the Ethereum Sepolia test network, and the end-to-end supply-chain workflow
was successfully demonstrated through public transactions.

## 1. Technology and Network

| Item | Configuration |
| --- | --- |
| Smart-contract language | Solidity `0.8.24` |
| Development framework | Foundry |
| Target network | Ethereum Sepolia |
| Chain ID | `11155111` |
| Optimiser | Enabled, 200 runs |

## 2. Deployed Contracts

The contracts must be deployed in the order shown below because each later
contract depends on the address of an earlier contract.

1. `ParticipantRegistry`
2. `BatchRegistry`
3. `ColdChainCompliance`
4. Configure `BatchRegistry` by calling `setComplianceContract`

| Contract | Sepolia address | Purpose |
| --- | --- | --- |
| `ParticipantRegistry` | [`0x71d9c2286F8D918ceA38eD71DeCecDa3A3A89441`](https://sepolia.etherscan.io/address/0x71d9c2286F8D918ceA38eD71DeCecDa3A3A89441) | Registers authorised supply-chain participants and IoT sensors |
| `BatchRegistry` | [`0x438f99B334F5c3245bd28689f76E848591DA485f`](https://sepolia.etherscan.io/address/0x438f99B334F5c3245bd28689f76E848591DA485f) | Records milk batches, custody transfers, and batch status |
| `ColdChainCompliance` | [`0xdC68A2246EcDa30A8fAE316587Df2A31F8E4b2CD`](https://sepolia.etherscan.io/address/0xdC68A2246EcDa30A8fAE316587Df2A31F8E4b2CD) | Verifies signed sensor readings and manages violations and recalls |

The same addresses should also be recorded in `addresses.txt` for use by other
project components.

## 3. Environment Setup

### Prerequisites

- Git
- Foundry (`forge`, `cast`, and `anvil`)
- A Sepolia RPC endpoint
- A deployment wallet funded with Sepolia ETH

Install project dependencies and check the code:

```bash
forge install
forge fmt --check
forge build
forge test -vv
```

Create a local `.env` file:

```dotenv
SEPOLIA_RPC_URL=<YOUR_SEPOLIA_RPC_URL>
PRIVATE_KEY=<YOUR_DEPLOYER_PRIVATE_KEY>
```

Load the variables before running a script:

```bash
source .env
```

The `.env` file contains sensitive information and must never be committed to
the repository.

## 4. Sepolia Deployment

Run a simulation before broadcasting:

```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$SEPOLIA_RPC_URL" \
  -vvvv
```

After confirming that the simulation succeeds and the wallet has sufficient
Sepolia ETH, broadcast the deployment:

```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --broadcast \
  -vvvv
```

`Deploy.s.sol` performs four operations:

1. Deploys `ParticipantRegistry`.
2. Deploys `BatchRegistry` with the participant-registry address.
3. Deploys `ColdChainCompliance` with both registry addresses.
4. Authorises `ColdChainCompliance` in `BatchRegistry`.

## 5. Blockchain Interaction

The interaction script demonstrates both a normal delivery and an abnormal
cold-chain scenario. A dry run should be performed first:

```bash
forge script script/Interact.s.sol:Interact \
  --rpc-url "$SEPOLIA_RPC_URL" \
  -vvvv
```

Broadcast only after the dry run completes successfully:

```bash
forge script script/Interact.s.sol:Interact \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --broadcast \
  -vvvv
```

The interaction sequence:

1. Registers the farm, processor, logistics provider, and retailer.
2. Registers an IoT temperature sensor controlled by the logistics provider.
3. Creates Batch 1 and transfers custody from the farm to the processor and
   then to the logistics provider.
4. Submits a signed `4.0°C` reading for Batch 1. The signature is recovered
   on-chain with `ecrecover`, and the reading is accepted without a violation.
5. Transfers Batch 1 to the retailer, changing its status to `Delivered`.
6. Creates Batch 2 and transfers it from the farm to the processor and then to
   the logistics provider.
7. Submits a signed `8.5°C` reading for Batch 2. This exceeds the configured
   maximum of `6.0°C`, so the batch is marked `NonCompliant`.
8. Requests a recall, changing Batch 2's final status to `Recalled`.

The contracts store temperature in tenths of a degree Celsius. Therefore, `40`
represents `4.0°C`, while `85` represents `8.5°C`.

## 6. On-Chain Execution Results

The Sepolia interaction completed successfully with 15 transactions.

| Scenario | Batch | Reading | Violation | Final status | Custody transfers |
| --- | ---: | ---: | --- | --- | ---: |
| Normal delivery | 1 | `4.0°C` | `false` | `Delivered` | 3 |
| Temperature violation and recall | 2 | `8.5°C` | `true` | `Recalled` | 2 |

The successful execution produced the following final states:

```text
Compliant batch created: 1
Normal temperature (tenths C): 40
Normal reading violation: false
Compliant batch final status: 3
Compliant batch custody transfers: 3

Recall-demo batch created: 2
Abnormal temperature (tenths C): 85
Abnormal reading violation: true
Status after violation: 4
Recalled batch final status: 5
Recalled batch custody transfers: 2

Sepolia interaction completed successfully.
ONCHAIN EXECUTION COMPLETE & SUCCESSFUL.
```

The `BatchRegistry.Status` values used above are:

| Value | Status |
| ---: | --- |
| `0` | `None` |
| `1` | `Created` |
| `2` | `InTransit` |
| `3` | `Delivered` |
| `4` | `NonCompliant` |
| `5` | `Recalled` |

The complete on-chain sequence used `1,062,669` gas and cost approximately
`0.00111998` Sepolia ETH.

## 7. Representative On-Chain Evidence

All transactions below have a successful status and can be independently
verified on Sepolia Etherscan.

| Evidence | Contract method | Transaction |
| --- | --- | --- |
| Batch 1 created by the farm | `createBatch` | [`0xfce2...f4a9c`](https://sepolia.etherscan.io/tx/0xfce2abd84286314da1164e0d3f57f8581e58f2a8f6bd77489b97c162ecff4a9c) |
| Normal signed reading of `4.0°C` accepted | `submitSignedReading` | [`0x3dd9...bebf`](https://sepolia.etherscan.io/tx/0x3dd96261478e7bdeed372f159d15ee1ea0492fb4ee9310625bbf96545f95bebf) |
| Batch 1 delivered to the retailer | `transferCustody` | [`0xea20...feb7`](https://sepolia.etherscan.io/tx/0xea203a308eb3d420c0d6aa549613a6909adc5146f424717e36455af97e4cfeb7) |
| Abnormal signed reading of `8.5°C` detected | `submitSignedReading` | [`0xcfc7...88b4`](https://sepolia.etherscan.io/tx/0xcfc7bb2cf0105e9e3da8ac45189676df84e2fb626e5f1749ba941acdaa7f88b4) |
| Batch 2 recalled after the violation | `requestRecall` | [`0x70ce...9402`](https://sepolia.etherscan.io/tx/0x70cee666e64fe937b3b046fe2f1b037085e64d93f7d9bd6e2f241b4c135e9402) |

Important emitted events include:

- `ParticipantRegistered`
- `SensorRegistered`
- `BatchCreated`
- `CustodyTransferred`
- `TemperatureReadingAccepted`
- `BatchMarkedNonCompliant`
- `RecallRequested`
- `BatchRecalled`

These events provide a public audit trail for registration, custody, sensor
validation, compliance decisions, and recall actions.

## 8. Security and Reproducibility Notes

- Do not commit `.env`, wallet private keys, or files in `cache/`.
- Do not publish the sensitive Foundry cache file generated during script
  execution.
- Use a fresh set of accounts or a fresh deployment before broadcasting
  `Interact.s.sol` again. Reusing the same deployed contracts may cause
  duplicate participant or sensor registration transactions to revert.
- Every sensor reading includes the compliance-contract address, chain ID,
  batch ID, temperature, timestamp, and nonce in its signed digest.
- Reused sensor nonces are rejected to prevent replay attacks.
- Only an active, registered sensor operated by the batch's current custodian
  can submit a trusted reading.
- Detailed sensor data remains off-chain; only trust-critical hashes, summary
  readings, custody state, and compliance state are stored on-chain.
