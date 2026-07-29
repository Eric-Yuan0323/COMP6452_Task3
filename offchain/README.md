# Off-chain sensor, oracle and storage

This component implements the off-chain side of the fresh-milk cold-chain PoC:

1. A sensor simulator generates a timestamped temperature reading.
2. SQLite stores the complete raw reading and its submission lifecycle.
3. A sensor wallet signs the digest returned by `ColdChainCompliance`.
4. A separate relayer submits the signed reading to the blockchain.
5. The transaction receipt and verified on-chain result are written back to SQLite.

The implementation intentionally follows the existing Solidity interfaces. Temperature is represented in tenths of a degree Celsius, and the same sensor nonce is never automatically reused.

## Requirements

- Node.js 22.5 or later
- Foundry (`forge` and `anvil`)
- Deployed `ParticipantRegistry`, `BatchRegistry`, and `ColdChainCompliance` contracts

## Install and build

```bash
npm install
forge build
cp .env.example .env
```

Set the RPC URL, deployed addresses, and private keys in `.env`. Never commit `.env`.

## Prepare a demo batch

The administrator must be the account that deployed `ParticipantRegistry`. The setup command registers the configured farm and sensor, then creates a batch owned by that farm.

```bash
npm run setup:demo
```

Copy the printed batch ID into the sensor commands below.

## Submit readings

Normal reading:

```bash
npm run sensor:normal -- --batch 1
```

Cold-chain violation:

```bash
npm run sensor:violation -- --batch 1
```

Explicit temperature:

```bash
npm run sensor -- --batch 1 --temperature 4.2
```

Random temperature:

```bash
npm run sensor -- --batch 1 --mode random
```

An explicit `--nonce` may be supplied to demonstrate local replay prevention. Automatic nonces are allocated from the highest nonce previously stored for the sensor, and the database enforces a unique sensor/nonce pair. The smart contract independently rejects a reused nonce even if local storage is bypassed.

## Stored evidence

The SQLite database defaults to `data/sensor-readings.db`. It contains the raw reading, sensor address, digest, signature, transaction hash, block number, violation result, batch status, and any submission error. Database files are ignored by Git.

## Current-contract limitation

The current `submitSignedReading` interface does not accept an off-chain storage hash. The signed reading and transaction receipt are retained locally, but the contract does not anchor the complete SQLite record on-chain.
