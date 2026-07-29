#!/usr/bin/env node

import { mkdirSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
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

function shortAddress(address) {
  if (!address || address.length < 10) return address || "N/A";
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

function formatTemperature(tenths) {
  return `${(Number(tenths) / 10).toFixed(1)}°C`;
}

function formatTime(timestamp) {
  const value = Number(timestamp);
  if (value === 0) return "N/A";
  return new Date(value * 1000).toLocaleString();
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#039;"
  }[char]));
}

async function queryBatch(batchId, contracts) {
  const batch = await contracts.batches.getBatch(batchId);
  const custodianAddress = await contracts.batches.getCurrentCustodian(batchId);
  const custodian = await contracts.participants.getParticipant(custodianAddress);
  const latest = await contracts.compliance.getLatestReading(batchId);

  const status = STATUS[Number(batch.status)] || `Unknown(${batch.status})`;
  const role = ROLE[Number(custodian.role)] || `Unknown(${custodian.role})`;
  const hasReading = Number(latest.measuredAt) !== 0;

  return {
    batchId,
    status,
    recalled: status === "Recalled",
    custodyTransfers: Number(batch.custodyTransfers),
    currentCustodian: custodianAddress,
    custodianName: custodian.name || "N/A",
    custodianRole: role,
    latestTemperature: hasReading ? formatTemperature(latest.temperatureTenths) : "N/A",
    measuredAt: hasReading ? formatTime(latest.measuredAt) : "N/A",
    sensor: hasReading ? latest.sensor : "N/A",
    violation: hasReading ? Boolean(latest.violation) : null
  };
}

function renderCard(batch) {
  const statusClass = batch.recalled || batch.violation ? "danger" : "ok";
  const tempClass = batch.violation ? "dangerText" : "okText";
  return `
    <section class="batch-card ${statusClass}">
      <div class="card-header">
        <div>
          <p class="eyebrow">Batch ${escapeHtml(batch.batchId)}</p>
          <h2>${escapeHtml(batch.status)}</h2>
        </div>
        <span class="pill ${statusClass}">${batch.recalled ? "Recalled" : "Not recalled"}</span>
      </div>

      <div class="metrics">
        <div>
          <span>Latest temperature</span>
          <strong class="${tempClass}">${escapeHtml(batch.latestTemperature)}</strong>
        </div>
        <div>
          <span>Violation</span>
          <strong>${batch.violation === null ? "N/A" : batch.violation ? "Yes" : "No"}</strong>
        </div>
        <div>
          <span>Custody transfers</span>
          <strong>${escapeHtml(batch.custodyTransfers)}</strong>
        </div>
      </div>

      <div class="flow">
        <span class="node active">Farm</span>
        <span class="edge"></span>
        <span class="node ${batch.custodyTransfers >= 1 ? "active" : ""}">Processor</span>
        <span class="edge"></span>
        <span class="node ${batch.custodyTransfers >= 2 ? "active" : ""}">Logistics</span>
        <span class="edge"></span>
        <span class="node ${batch.custodyTransfers >= 3 ? "active" : ""}">Retailer</span>
      </div>

      <dl class="details">
        <div><dt>Current custodian</dt><dd>${escapeHtml(batch.custodianName)} (${escapeHtml(batch.custodianRole)})</dd></div>
        <div><dt>Custodian address</dt><dd title="${escapeHtml(batch.currentCustodian)}">${escapeHtml(shortAddress(batch.currentCustodian))}</dd></div>
        <div><dt>Sensor</dt><dd title="${escapeHtml(batch.sensor)}">${escapeHtml(shortAddress(batch.sensor))}</dd></div>
        <div><dt>Measured at</dt><dd>${escapeHtml(batch.measuredAt)}</dd></div>
      </dl>
    </section>
  `;
}

function renderHtml(batches) {
  const generatedAt = new Date().toLocaleString();
  const compliant = batches.filter((batch) => !batch.recalled && !batch.violation).length;
  const alerts = batches.length - compliant;
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Fresh Milk Cold-Chain Demo Dashboard</title>
  <style>
    :root {
      --navy: #10264a;
      --blue: #1f64d1;
      --green: #14854a;
      --red: #c2412d;
      --orange: #e46a22;
      --bg: #f7fafc;
      --card: #ffffff;
      --border: #dbe5f2;
      --muted: #637083;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: Inter, Segoe UI, Arial, sans-serif;
      color: var(--navy);
      background: linear-gradient(180deg, #ffffff 0%, var(--bg) 100%);
    }
    main { max-width: 1180px; margin: 0 auto; padding: 36px 24px; }
    header { display: flex; justify-content: space-between; gap: 24px; align-items: flex-start; margin-bottom: 24px; }
    h1 { margin: 0 0 8px; font-size: 32px; line-height: 1.12; }
    .subtitle { margin: 0; color: var(--muted); font-size: 15px; }
    .summary { display: grid; grid-template-columns: repeat(3, minmax(120px, 1fr)); gap: 12px; margin-bottom: 22px; }
    .summary-card {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 18px;
      padding: 16px;
      box-shadow: 0 8px 26px rgba(16, 38, 74, 0.08);
    }
    .summary-card span { display: block; color: var(--muted); font-size: 13px; margin-bottom: 6px; }
    .summary-card strong { font-size: 25px; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(360px, 1fr)); gap: 18px; }
    .batch-card {
      background: var(--card);
      border: 1px solid var(--border);
      border-left: 7px solid var(--green);
      border-radius: 22px;
      padding: 20px;
      box-shadow: 0 10px 30px rgba(16, 38, 74, 0.08);
    }
    .batch-card.danger { border-left-color: var(--red); }
    .card-header { display: flex; justify-content: space-between; align-items: flex-start; gap: 12px; margin-bottom: 16px; }
    .eyebrow { margin: 0 0 2px; color: var(--muted); font-weight: 700; text-transform: uppercase; letter-spacing: 0.08em; font-size: 12px; }
    h2 { margin: 0; font-size: 28px; }
    .pill { border-radius: 999px; padding: 7px 10px; font-size: 13px; font-weight: 700; white-space: nowrap; }
    .pill.ok { color: var(--green); background: #eaf8ef; }
    .pill.danger { color: var(--red); background: #fff0ed; }
    .metrics { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; margin-bottom: 18px; }
    .metrics div { background: #f7faff; border: 1px solid var(--border); border-radius: 14px; padding: 12px; }
    .metrics span { display: block; color: var(--muted); font-size: 12px; margin-bottom: 5px; }
    .metrics strong { font-size: 20px; }
    .okText { color: var(--green); }
    .dangerText { color: var(--red); }
    .flow { display: flex; align-items: center; gap: 6px; margin: 12px 0 18px; overflow-x: auto; padding-bottom: 4px; }
    .node { flex: 0 0 auto; padding: 9px 11px; border-radius: 999px; color: var(--muted); background: #eef3f8; border: 1px solid var(--border); font-size: 13px; font-weight: 700; }
    .node.active { color: #fff; background: var(--blue); border-color: var(--blue); }
    .edge { flex: 0 0 22px; height: 2px; background: var(--border); }
    .details { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; margin: 0; }
    dt { color: var(--muted); font-size: 12px; margin-bottom: 4px; }
    dd { margin: 0; font-weight: 700; overflow-wrap: anywhere; }
    .note { margin-top: 20px; color: var(--muted); font-size: 13px; }
    @media (max-width: 760px) {
      header { display: block; }
      .summary, .metrics, .details { grid-template-columns: 1fr; }
      .grid { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <main>
    <header>
      <div>
        <h1>Fresh Milk Cold-Chain Demo Dashboard</h1>
        <p class="subtitle">Generated from deployed smart-contract state and latest sensor readings.</p>
      </div>
      <p class="subtitle">Generated at ${escapeHtml(generatedAt)}</p>
    </header>

    <section class="summary" aria-label="Demo summary">
      <div class="summary-card"><span>Total batches</span><strong>${batches.length}</strong></div>
      <div class="summary-card"><span>Compliant / normal</span><strong>${compliant}</strong></div>
      <div class="summary-card"><span>Alerts or recalls</span><strong>${alerts}</strong></div>
    </section>

    <section class="grid">
      ${batches.map(renderCard).join("\n")}
    </section>

    <p class="note">On-chain: batch status, custody state, compliance status and recall status. Off-chain: raw readings, certificates and detailed shipment records.</p>
  </main>
</body>
</html>`;
}

async function main() {
  const ids = process.argv.slice(2).map(Number).filter((id) => Number.isSafeInteger(id) && id > 0);
  const batchIds = ids.length > 0 ? ids : [1, 2];

  const config = getConfig();
  const provider = new JsonRpcProvider(config.rpcUrl);

  const contracts = {
    participants: new Contract(
      config.participantRegistry,
      ["function getParticipant(address account) view returns (tuple(string name,uint8 role,bool active))"],
      provider
    ),
    batches: new Contract(
      config.batchRegistry,
      [
        "function getBatch(uint256 batchId) view returns (tuple(bytes32 metadataHash,address creator,address currentCustodian,uint8 status,uint64 createdAt,uint32 custodyTransfers))",
        "function getCurrentCustodian(uint256 batchId) view returns (address)"
      ],
      provider
    ),
    compliance: new Contract(
      config.compliance,
      ["function getLatestReading(uint256 batchId) view returns (tuple(int16 temperatureTenths,uint64 measuredAt,address sensor,bool violation))"],
      provider
    )
  };

  const batches = [];
  for (const id of batchIds) {
    batches.push(await queryBatch(id, contracts));
  }

  const outputPath = resolve("visualization", "batch-dashboard.html");
  mkdirSync(dirname(outputPath), { recursive: true });
  writeFileSync(outputPath, renderHtml(batches), "utf8");

  console.log(`Visualization written to ${outputPath}`);
  console.log("Open this file in a browser to show the demo dashboard.");
}

main().catch((error) => {
  console.error("Visualization failed:");
  console.error(error.shortMessage || error.reason || error.message);
  process.exit(1);
});
