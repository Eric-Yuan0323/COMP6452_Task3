#!/usr/bin/env node

import { loadOracleConfig } from "./config.js";
import { OracleService } from "./oracle-service.js";
import { generateReading } from "./sensor-simulator.js";
import { ReadingStorage } from "./storage.js";

function parseArguments(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (!argument.startsWith("--")) {
      throw new Error(`Unexpected argument '${argument}'.`);
    }
    const name = argument.slice(2);
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) {
      throw new Error(`Missing value for --${name}.`);
    }
    options[name] = value;
    index += 1;
  }
  return options;
}

function printUsage() {
  console.log(`Usage:
  npm run sensor -- --batch <id> [--temperature <celsius>]
  npm run sensor -- --batch <id> --mode <normal|violation|random>
  npm run sensor -- --batch <id> --nonce <number> --temperature <celsius>`);
}

async function main() {
  const args = parseArguments(process.argv.slice(2));
  if (!args.batch) {
    printUsage();
    throw new Error("--batch is required.");
  }

  const config = loadOracleConfig();
  const storage = new ReadingStorage(config.databasePath);

  try {
    const oracle = new OracleService(config, storage);
    const nonce = args.nonce === undefined ? oracle.nextNonce() : Number(args.nonce);
    const reading = generateReading({
      batchId: Number(args.batch),
      nonce,
      temperatureCelsius: args.temperature,
      mode: args.mode || "normal"
    });

    console.log("Generated sensor reading");
    console.log(`  Batch: ${reading.batchId}`);
    console.log(`  Temperature: ${(reading.temperatureTenths / 10).toFixed(1)}°C`);
    console.log(`  Measured at: ${new Date(reading.measuredAt * 1000).toISOString()}`);
    console.log(`  Nonce: ${reading.nonce}`);
    console.log(`  Sensor: ${oracle.sensorAddress}`);

    const result = await oracle.submit(reading);

    console.log("Submission confirmed");
    console.log(`  Off-chain record: ${result.recordId}`);
    console.log(`  Transaction: ${result.transactionHash}`);
    console.log(`  Block: ${result.blockNumber}`);
    console.log(`  Violation: ${result.violation}`);
    console.log(`  Batch status: ${result.batchStatus}`);
    console.log(`  Current custodian: ${result.currentCustodian}`);
  } finally {
    storage.close();
  }
}

main().catch((error) => {
  const message = error.shortMessage || error.reason || error.message || String(error);
  console.error(`Sensor submission failed: ${message}`);
  if (error.recordId !== undefined) {
    console.error(`Failure saved as off-chain record ${error.recordId}.`);
  }
  process.exitCode = 1;
});
