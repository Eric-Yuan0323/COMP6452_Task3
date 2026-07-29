import { existsSync, readFileSync } from "node:fs";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { isAddress } from "ethers";

const offchainDirectory = dirname(fileURLToPath(import.meta.url));
export const projectRoot = resolve(offchainDirectory, "..");

const envPath = join(projectRoot, ".env");
if (existsSync(envPath)) {
  process.loadEnvFile(envPath);
}

function required(name) {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`Missing ${name}. Copy .env.example to .env and set it.`);
  }
  return value;
}

function address(name) {
  const value = required(name);
  if (!isAddress(value)) {
    throw new Error(`${name} is not a valid Ethereum address.`);
  }
  return value;
}

function privateKey(name) {
  const value = required(name);
  if (!/^0x[0-9a-fA-F]{64}$/.test(value)) {
    throw new Error(`${name} must be a 32-byte hex private key beginning with 0x.`);
  }
  return value;
}

export function loadOracleConfig() {
  const configuredDatabase = process.env.DATABASE_PATH?.trim() || "./data/sensor-readings.db";

  return {
    rpcUrl: process.env.RPC_URL?.trim() || "http://127.0.0.1:8545",
    batchRegistryAddress: address("BATCH_REGISTRY"),
    complianceAddress: address("COMPLIANCE"),
    sensorPrivateKey: privateKey("SENSOR_PRIVATE_KEY"),
    relayerPrivateKey: privateKey("RELAYER_PRIVATE_KEY"),
    databasePath: isAbsolute(configuredDatabase)
      ? configuredDatabase
      : resolve(projectRoot, configuredDatabase)
  };
}

export function loadSetupConfig() {
  return {
    rpcUrl: process.env.RPC_URL?.trim() || "http://127.0.0.1:8545",
    participantRegistryAddress: address("PARTICIPANT_REGISTRY"),
    batchRegistryAddress: address("BATCH_REGISTRY"),
    administratorPrivateKey: privateKey("ADMIN_PRIVATE_KEY"),
    farmPrivateKey: privateKey("FARM_PRIVATE_KEY"),
    sensorPrivateKey: privateKey("SENSOR_PRIVATE_KEY")
  };
}

export function loadArtifact(contractName) {
  const artifactPath = join(projectRoot, "out", `${contractName}.sol`, `${contractName}.json`);
  if (!existsSync(artifactPath)) {
    throw new Error(`Missing ${artifactPath}. Run 'forge build' first.`);
  }
  return JSON.parse(readFileSync(artifactPath, "utf8"));
}
