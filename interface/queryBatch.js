#!/usr/bin/env node

import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { Contract, JsonRpcProvider, isAddress } from "ethers";

const STATUS = ["None", "Created", "InTransit", "Delivered", "NonCompliant", "Recalled"];
const ROLE = ["None", "Farm", "Processor", "Logistics", "Retailer"];

function loadEnv() {
  const envPath = resolve(".env");
  if (existsSync(envPath) && typeof process.loadEnvFile === "function") {
    process.loadEnvFile(envPath);
  }
}

function readAddressFile() {
  const path = resolve("addresses.txt");
  if (!existsSync(path)) return {};
  const text = readFileSync(path, "utf8");
  const lines = text.split(/\r?\n/);
  const result = {};
  for (let i = 0; i < lines.length; i += 1) {
    const label = lines[i].trim().replace(/:$/, "");
    const next = (lines[i + 1] || "").trim();
    if (/^0x[a-fA-F0-9]{40}$/.test(next)) {
      if (label === "ParticipantRegistry") result.PARTICIPANT_REGISTRY = next;
      if (label === "BatchRegistry") result.BATCH_REGISTRY = next;
      if (label === "ColdChainCompliance") result.COMPLIANCE = next;
    }
  }
  return result;
}

function nonZeroAddress(value) {
  return isAddress(value || "") && !/^0x0{40}$/i.test(value);
}

function getConfig() {
  loadEnv();
  const fromFile = readAddressFile();

  const rpcUrl = process.env.SEPOLIA_RPC_URL || process.env.RPC_URL;
  if (!rpcUrl) {
    throw new Error("Missing RPC URL. Set SEPOLIA_RPC_URL or RPC_URL in .env.");
  }

  const participantRegistry = process.env.PARTICIPANT_REGISTRY || fromFile.PARTICIPANT_REGISTRY;
  const batchRegistry = process.env.BATCH_REGISTRY || fromFile.BATCH_REGISTRY;
  const compliance = process.env.COMPLIANCE || process.env.COLD_CHAIN_COMPLIANCE || fromFile.COMPLIANCE;

  for (const [name, value] of Object.entries({
    PARTICIPANT_REGISTRY: participantRegistry,
    BATCH_REGISTRY: batchRegistry,
    COMPLIANCE: compliance
  })) {
    if (!nonZeroAddress(value)) {
      throw new Error(`${name} is missing or invalid. Set it in .env or addresses.txt.`);
    }
  }

  return { rpcUrl, participantRegistry, batchRegistry, compliance };
}

function formatTemperature(tenths) {
  return `${(Number(tenths) / 10).toFixed(1)} °C`;
}

function formatTime(timestamp) {
  const value = Number(timestamp);
  if (value === 0) return "N/A";
  return new Date(value * 1000).toLocaleString();
}

function requireBatchId() {
  const batchId = Number(process.argv[2]);
  if (!Number.isSafeInteger(batchId) || batchId <= 0) {
    console.error("Usage: npm run query -- <batchId>");
    console.error("Example: npm run query -- 1");
    process.exit(1);
  }
  return batchId;
}

async function main() {
  const batchId = requireBatchId();
  const config = getConfig();
  const provider = new JsonRpcProvider(config.rpcUrl);

  const participants = new Contract(
    config.participantRegistry,
    ["function getParticipant(address account) view returns (tuple(string name,uint8 role,bool active))"],
    provider
  );

  const batches = new Contract(
    config.batchRegistry,
    [
      "function getBatch(uint256 batchId) view returns (tuple(bytes32 metadataHash,address creator,address currentCustodian,uint8 status,uint64 createdAt,uint32 custodyTransfers))",
      "function getCurrentCustodian(uint256 batchId) view returns (address)"
    ],
    provider
  );

  const compliance = new Contract(
    config.compliance,
    ["function getLatestReading(uint256 batchId) view returns (tuple(int16 temperatureTenths,uint64 measuredAt,address sensor,bool violation))"],
    provider
  );

  const batch = await batches.getBatch(batchId);
  const custodianAddress = await batches.getCurrentCustodian(batchId);
  const custodian = await participants.getParticipant(custodianAddress);
  const latest = await compliance.getLatestReading(batchId);

  const status = STATUS[Number(batch.status)] || `Unknown(${batch.status})`;
  const role = ROLE[Number(custodian.role)] || `Unknown(${custodian.role})`;
  const hasReading = Number(latest.measuredAt) !== 0;

  console.log("==================================================");
  console.log(" Fresh Milk Batch Query Result");
  console.log("==================================================");
  console.log(`Batch ID:               ${batchId}`);
  console.log(`Batch Status:           ${status}`);
  console.log(`Is Recalled:            ${status === "Recalled" ? "Yes" : "No"}`);
  console.log(`Current Custodian:      ${custodianAddress}`);
  console.log(`Custodian Name:         ${custodian.name || "N/A"}`);
  console.log(`Custodian Role:         ${role}`);
  console.log(`Custody Transfers:      ${batch.custodyTransfers.toString()}`);
  console.log("--------------------------------------------------");

  if (hasReading) {
    console.log(`Latest Temperature:     ${formatTemperature(latest.temperatureTenths)}`);
    console.log(`Measured At:            ${formatTime(latest.measuredAt)}`);
    console.log(`Sensor Address:         ${latest.sensor}`);
    console.log(`Cold-chain Violation:   ${latest.violation ? "Yes" : "No"}`);
  } else {
    console.log("Latest Temperature:     N/A");
    console.log("Measured At:            N/A");
    console.log("Sensor Address:         N/A");
    console.log("Cold-chain Violation:   N/A");
  }

  console.log("==================================================");
}

main().catch((error) => {
  console.error("Query failed:");
  console.error(error.shortMessage || error.reason || error.message);
  process.exit(1);
});
