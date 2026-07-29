#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"

print_line() {
  printf '\n============================================================\n'
}

print_step() {
  print_line
  printf '%s\n' "$1"
  print_line
}

fail() {
  printf '\n[ERROR] %s\n' "$1" >&2
  exit 1
}

command -v forge >/dev/null 2>&1 || fail "forge is not installed or not on PATH."
command -v node >/dev/null 2>&1 || fail "Node.js is not installed or not on PATH."
command -v npm >/dev/null 2>&1 || fail "npm is not installed or not on PATH."

[[ -f ".env" ]] || fail "Missing .env in the project root."
[[ -f "package.json" ]] || fail "Missing package.json."
[[ -f "offchain/setup-demo.js" ]] || fail "Missing offchain/setup-demo.js."
[[ -f "offchain/cli.js" ]] || fail "Missing offchain/cli.js."

# Load RPC_URL from .env for the local-chain connectivity check.
set -a
# shellcheck disable=SC1091
source .env
set +a
RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"

print_step "Fresh Milk Cold-Chain Demo Automation"

printf 'Checking local blockchain at %s...\n' "$RPC_URL"
if command -v cast >/dev/null 2>&1; then
  cast block-number --rpc-url "$RPC_URL" >/dev/null 2>&1 \
    || fail "Cannot connect to Anvil. Start it in another terminal with: anvil"
fi
printf '[OK] Environment check passed.\n'

print_step "Step 1/5 - Build smart contracts"
forge build
printf '[OK] Smart contracts compiled.\n'

print_step "Step 2/5 - Run unit and integration tests"
forge test -vv
printf '[OK] All Foundry tests passed.\n'

print_step "Step 3/5 - Initialise the demo"
SETUP_OUTPUT="$(node offchain/setup-demo.js)"
printf '%s\n' "$SETUP_OUTPUT"

BATCH_ID="$(
  printf '%s\n' "$SETUP_OUTPUT" \
    | sed -nE 's/^[[:space:]]*Batch ID:[[:space:]]*([0-9]+).*$/\1/p' \
    | tail -n 1
)"

[[ -n "$BATCH_ID" ]] || fail "Unable to extract the Batch ID from setup-demo.js output."
printf '[OK] Demo batch %s created.\n' "$BATCH_ID"

print_step "Step 4/5 - Submit a compliant temperature reading"
node offchain/cli.js \
  --batch "$BATCH_ID" \
  --temperature 4.0
printf '[OK] Compliant reading submitted.\n'

print_step "Step 5/5 - Submit a violating temperature reading"
node offchain/cli.js \
  --batch "$BATCH_ID" \
  --temperature 9.5
printf '[OK] Violating reading submitted.\n'

print_line
printf 'DEMO COMPLETE\n'
printf 'Batch ID: %s\n' "$BATCH_ID"
printf 'Expected first result: Violation = false\n'
printf 'Expected final result: Violation = true; Batch status = NonCompliant\n'
printf 'Off-chain records are stored in the configured SQLite database.\n'
print_line
