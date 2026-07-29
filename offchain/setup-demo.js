#!/usr/bin/env node

import {
  Contract,
  JsonRpcProvider,
  NonceManager,
  Wallet,
  ZeroAddress,
  keccak256,
  toUtf8Bytes
} from "ethers";
import { loadArtifact, loadSetupConfig } from "./config.js";

async function main() {
  const config = loadSetupConfig();
  const provider = new JsonRpcProvider(config.rpcUrl);
  const administrator = new Wallet(config.administratorPrivateKey, provider);
  const farmWallet = new Wallet(config.farmPrivateKey, provider);
  const farm = new NonceManager(farmWallet);
  const farmAddress = farmWallet.address;
  const sensor = new Wallet(config.sensorPrivateKey);

  const participants = new Contract(
    config.participantRegistryAddress,
    loadArtifact("ParticipantRegistry").abi,
    administrator
  );
  const batches = new Contract(
    config.batchRegistryAddress,
    loadArtifact("BatchRegistry").abi,
    farm
  );

  const farmRole = Number(await participants.getRole(farmAddress));
  if (farmRole === 0) {
    console.log(`Registering farm ${farmAddress}`);
    await (await participants.registerParticipant(farmAddress, 1, "Demo Dairy Farm")).wait();
  } else if (!(await participants.isActiveParticipant(farmAddress))) {
    console.log(`Reactivating farm ${farmAddress}`);
    await (await participants.setParticipantActive(farmAddress, true)).wait();
  }

  const sensorOperator = await participants.getSensorOperator(sensor.address);
  if (sensorOperator === ZeroAddress) {
    console.log(`Registering sensor ${sensor.address}`);
    await (await participants.connect(farm).registerSensor(sensor.address)).wait();
  } else if (sensorOperator.toLowerCase() !== farmAddress.toLowerCase()) {
    throw new Error(`Sensor is already owned by ${sensorOperator}, not the demo farm.`);
  } else if (!(await participants.isActiveSensor(sensor.address))) {
    console.log(`Reactivating sensor ${sensor.address}`);
    await (await participants.connect(farm).setSensorActive(sensor.address, true)).wait();
  }

  const batchId = Number(await batches.nextBatchId());
  const metadata = JSON.stringify({
    batchReference: `MILK-${String(batchId).padStart(3, "0")}`,
    product: "Fresh Milk",
    farm: farmAddress
  });
  const metadataHash = keccak256(toUtf8Bytes(metadata));

  console.log(`Creating demo batch ${batchId}`);
  await (await batches.createBatch(metadataHash)).wait();

  console.log("Demo setup complete");
  console.log(`  Batch ID: ${batchId}`);
  console.log(`  Farm/current custodian: ${farmAddress}`);
  console.log(`  Sensor: ${sensor.address}`);
  console.log(`  Metadata hash: ${metadataHash}`);
}

main().catch((error) => {
  console.error(`Demo setup failed: ${error.shortMessage || error.message || String(error)}`);
  process.exitCode = 1;
});
