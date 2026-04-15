#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RPC_URL="${RPC_URL:-https://carrot.megaeth.com/rpc}"
FACTORY="${FACTORY:-0x63Baad87dED7c8e8B8F470a0433554045daEA9A8}"
ALLOWLIST="${ALLOWLIST:-0x923B00115D1F8c60DbEf30C52C149eFfD3256f4D}"
USDM="${USDM:-0x9f5A17BD53310D012544966b8e3cF7863fc8F05f}"
DEPLOYER_ADDRESS="${DEPLOYER_ADDRESS:-0xE9E872D867d8e021f2FD0da4672b0373781BC96f}"

SMOKE_INVESTOR_KEY="${SMOKE_INVESTOR_KEY:-0x1000000000000000000000000000000000000000000000000000000000000001}"
REFUND_INVESTOR_KEY="${REFUND_INVESTOR_KEY:-0x1000000000000000000000000000000000000000000000000000000000000002}"
SETTLE_INVESTOR1_KEY="${SETTLE_INVESTOR1_KEY:-0x1000000000000000000000000000000000000000000000000000000000000003}"
SETTLE_INVESTOR2_KEY="${SETTLE_INVESTOR2_KEY:-0x1000000000000000000000000000000000000000000000000000000000000004}"
OPERATOR_KEY="${OPERATOR_KEY:-0x1000000000000000000000000000000000000000000000000000000000000005}"

ETH_FUND_WEI="${ETH_FUND_WEI:-20000000000000000}"
SMOKE_COMMIT="${SMOKE_COMMIT:-1000000000}"
REFUND_COMMIT="${REFUND_COMMIT:-1200000000}"
SETTLE_COMMIT_1="${SETTLE_COMMIT_1:-6000000000}"
SETTLE_COMMIT_2="${SETTLE_COMMIT_2:-4000000000}"
TREASURY_PROFIT="${TREASURY_PROFIT:-2000000000}"
EXPECTED_SETTLED_ASSETS="${EXPECTED_SETTLED_ASSETS:-11900000000}"
EXPECTED_PLATFORM_FEE="${EXPECTED_PLATFORM_FEE:-100000000}"

VALIDATION_LAUNCH_DELAY="${VALIDATION_LAUNCH_DELAY:-30}"
VALIDATION_DURATION="${VALIDATION_DURATION:-120}"
VALIDATION_LOCKUP_MINUTES="${VALIDATION_LOCKUP_MINUTES:-1}"

if [[ -z "${PRIVATE_KEY:-}" ]]; then
  echo "PRIVATE_KEY is required" >&2
  exit 1
fi

smoke_investor="$(cast wallet address --private-key "$SMOKE_INVESTOR_KEY")"
refund_investor="$(cast wallet address --private-key "$REFUND_INVESTOR_KEY")"
settle_investor1="$(cast wallet address --private-key "$SETTLE_INVESTOR1_KEY")"
settle_investor2="$(cast wallet address --private-key "$SETTLE_INVESTOR2_KEY")"
operator_address="$(cast wallet address --private-key "$OPERATOR_KEY")"

log() {
  printf '\n[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"
}

call_uint() {
  cast call "$1" "$2" "${@:3}" --rpc-url "$RPC_URL" | awk '{print $1}'
}

call_bool() {
  cast call "$1" "$2" "${@:3}" --rpc-url "$RPC_URL" | tr '[:upper:]' '[:lower:]'
}

call_addr() {
  cast call "$1" "$2" "${@:3}" --rpc-url "$RPC_URL" | awk '{print $1}'
}

send_tx() {
  local key="$1"
  shift
  cast send "$@" --rpc-url "$RPC_URL" --private-key "$key"
}

wait_until() {
  local target_ts="$1"
  while true; do
    local now
    now="$(cast block latest --field timestamp --rpc-url "$RPC_URL")"
    if (( now >= target_ts )); then
      break
    fi
    local remaining=$(( target_ts - now ))
    log "waiting ${remaining}s until unix ${target_ts}"
    sleep $(( remaining > 10 ? 10 : remaining ))
  done
}

ensure_allowlisted() {
  local target="$1"
  local is_allowed
  is_allowed="$(call_bool "$ALLOWLIST" "isAllowed(address)(bool)" "$target")"
  if [[ "$is_allowed" != "true" ]]; then
    log "allowlisting $target"
    send_tx "$PRIVATE_KEY" "$ALLOWLIST" "addContract(address)" "$target" >/dev/null
  fi
}

fund_wallet() {
  local target="$1"
  local usdm_amount="$2"

  log "funding $target"
  send_tx "$PRIVATE_KEY" "$target" --value "$ETH_FUND_WEI" >/dev/null
  send_tx "$PRIVATE_KEY" "$USDM" "transfer(address,uint256)" "$target" "$usdm_amount" >/dev/null
}

approve_and_commit() {
  local investor_key="$1"
  local investor="$2"
  local sale="$3"
  local amount="$4"

  log "approving $amount USDM from $investor to $sale"
  send_tx "$investor_key" "$USDM" "approve(address,uint256)" "$sale" "$amount" >/dev/null
  log "committing $amount USDM from $investor into $sale"
  send_tx "$investor_key" "$sale" "commit(uint256)" "$amount" >/dev/null
}

extract_value() {
  local key="$1"
  local output="$2"
  echo "$output" | awk -F= -v k="$key" '
    {
      lhs = $1
      rhs = $2
      sub(/^[[:space:]]+/, "", lhs)
      sub(/[[:space:]]+$/, "", lhs)
      if (lhs == k) print rhs
    }
  ' | tail -n 1
}

log "running local backend test suite first"
(cd "$ROOT_DIR" && forge test -vvv >/dev/null)

log "funding operator and investor wallets"
fund_wallet "$smoke_investor" "$SMOKE_COMMIT"
fund_wallet "$refund_investor" "$REFUND_COMMIT"
fund_wallet "$settle_investor1" "$SETTLE_COMMIT_1"
fund_wallet "$settle_investor2" "$SETTLE_COMMIT_2"
fund_wallet "$operator_address" 0

log "creating validation projects on testnet"
current_ts="$(cast block latest --field timestamp --rpc-url "$RPC_URL")"
validation_launch_time=$(( current_ts + VALIDATION_LAUNCH_DELAY + 15 ))
setup_output="$(
  cd "$ROOT_DIR" && \
  NO_PROXY="*" \
  PRIVATE_KEY="$PRIVATE_KEY" \
  TEST_OPERATOR="$operator_address" \
  VALIDATION_LAUNCH_DELAY="$VALIDATION_LAUNCH_DELAY" \
  VALIDATION_LAUNCH_TIME="$validation_launch_time" \
  VALIDATION_DURATION="$VALIDATION_DURATION" \
  VALIDATION_LOCKUP_MINUTES="$VALIDATION_LOCKUP_MINUTES" \
  forge script script/TestnetProductionValidationSetup.s.sol:TestnetProductionValidationSetup \
    --rpc-url "$RPC_URL" \
    --broadcast \
    --gas-estimate-multiplier 5000 \
    --code-size-limit 100000 \
    -vvv
)"
printf '%s\n' "$setup_output"

launch_time="$(extract_value "VALIDATION_LAUNCH_TIME" "$setup_output")"
smoke_sale="$(extract_value "SMOKE_SALE" "$setup_output")"
refund_sale="$(extract_value "REFUND_SALE" "$setup_output")"
settlement_sale="$(extract_value "SETTLEMENT_SALE" "$setup_output")"
settlement_executor="$(extract_value "SETTLEMENT_EXECUTOR" "$setup_output")"

if [[ -z "$launch_time" || -z "$smoke_sale" || -z "$refund_sale" || -z "$settlement_sale" || -z "$settlement_executor" ]]; then
  echo "failed to parse setup output" >&2
  exit 1
fi

settlement_treasury="$(call_addr "$settlement_sale" "TREASURY()(address)")"

wait_until $(( launch_time + 2 ))

approve_and_commit "$SMOKE_INVESTOR_KEY" "$smoke_investor" "$smoke_sale" "$SMOKE_COMMIT"
approve_and_commit "$REFUND_INVESTOR_KEY" "$refund_investor" "$refund_sale" "$REFUND_COMMIT"
approve_and_commit "$SETTLE_INVESTOR1_KEY" "$settle_investor1" "$settlement_sale" "$SETTLE_COMMIT_1"
approve_and_commit "$SETTLE_INVESTOR2_KEY" "$settle_investor2" "$settlement_sale" "$SETTLE_COMMIT_2"

smoke_total="$(call_uint "$smoke_sale" "totalCommitted()(uint256)")"
refund_total="$(call_uint "$refund_sale" "totalCommitted()(uint256)")"
settlement_total="$(call_uint "$settlement_sale" "totalCommitted()(uint256)")"

[[ "$smoke_total" == "$SMOKE_COMMIT" ]]
[[ "$refund_total" == "$REFUND_COMMIT" ]]
expected_settlement_total=$(( SETTLE_COMMIT_1 + SETTLE_COMMIT_2 ))
[[ "$settlement_total" == "$expected_settlement_total" ]]

log "triggering emergency refund path"
refund_balance_before="$(call_uint "$USDM" "balanceOf(address)(uint256)" "$refund_investor")"
send_tx "$PRIVATE_KEY" "$refund_sale" "emergencyRefund()" >/dev/null
send_tx "$REFUND_INVESTOR_KEY" "$refund_sale" "refund()" >/dev/null
refund_balance_after="$(call_uint "$USDM" "balanceOf(address)(uint256)" "$refund_investor")"
[[ $(( refund_balance_after - refund_balance_before )) -eq REFUND_COMMIT ]]

smoke_end="$(call_uint "$smoke_sale" "endTime()(uint256)")"
settlement_end="$(call_uint "$settlement_sale" "endTime()(uint256)")"
finalize_after="$smoke_end"
if (( settlement_end > finalize_after )); then
  finalize_after="$settlement_end"
fi
wait_until $(( finalize_after + 2 ))

log "finalizing under-min smoke flow"
smoke_balance_before="$(call_uint "$USDM" "balanceOf(address)(uint256)" "$smoke_investor")"
send_tx "$PRIVATE_KEY" "$smoke_sale" "finalize()" >/dev/null
[[ "$(call_bool "$smoke_sale" "finalized()(bool)")" == "true" ]]
[[ "$(call_bool "$smoke_sale" "failed()(bool)")" == "true" ]]
send_tx "$SMOKE_INVESTOR_KEY" "$smoke_sale" "refund()" >/dev/null
smoke_balance_after="$(call_uint "$USDM" "balanceOf(address)(uint256)" "$smoke_investor")"
[[ $(( smoke_balance_after - smoke_balance_before )) -eq SMOKE_COMMIT ]]

log "finalizing successful settlement flow"
send_tx "$PRIVATE_KEY" "$settlement_sale" "finalize()" >/dev/null
accepted_amount="$(call_uint "$settlement_sale" "acceptedAmount()(uint256)")"
[[ "$accepted_amount" == "$expected_settlement_total" ]]
share_token="$(call_addr "$settlement_sale" "token()(address)")"
[[ "$share_token" != "0x0000000000000000000000000000000000000000" ]]

log "claiming investor shares"
send_tx "$SETTLE_INVESTOR1_KEY" "$settlement_sale" "claim()" >/dev/null
send_tx "$SETTLE_INVESTOR2_KEY" "$settlement_sale" "claim()" >/dev/null

investor1_shares="$(call_uint "$share_token" "balanceOf(address)(uint256)" "$settle_investor1")"
investor2_shares="$(call_uint "$share_token" "balanceOf(address)(uint256)" "$settle_investor2")"
[[ "$investor1_shares" == "6000000000000000000000" ]]
[[ "$investor2_shares" == "4000000000000000000000" ]]

ensure_allowlisted "$USDM"
ensure_allowlisted "$share_token"
send_tx "$PRIVATE_KEY" "$settlement_executor" "setSelectorAllowed(address,bytes4,bool)" "$USDM" "0xa9059cbb" "true" >/dev/null
send_tx "$PRIVATE_KEY" "$settlement_executor" "setSelectorAllowed(address,bytes4,bool)" "$share_token" "0x1bb3399d" "true" >/dev/null

log "topping up treasury with simulated profit"
send_tx "$PRIVATE_KEY" "$USDM" "transfer(address,uint256)" "$settlement_treasury" "$TREASURY_PROFIT" >/dev/null

lockup_end="$(call_uint "$share_token" "LOCKUP_END_TIME()(uint256)")"
wait_until "$lockup_end"

gross_assets=$(( accepted_amount + TREASURY_PROFIT ))
transfer_calldata="$(cast calldata "transfer(address,uint256)" "$share_token" "$gross_assets")"
log "moving treasury assets into share token and finalizing settlement"
send_tx "$OPERATOR_KEY" "$settlement_executor" "execute(address,uint256,bytes)" "$USDM" "0" "$transfer_calldata" >/dev/null
send_tx "$OPERATOR_KEY" "$settlement_executor" "execute(address,uint256,bytes)" "$share_token" "0" "0x1bb3399d" >/dev/null

[[ "$(call_bool "$share_token" "settled()(bool)")" == "true" ]]
settled_assets="$(call_uint "$share_token" "totalAssets()(uint256)")"
[[ "$settled_assets" == "$EXPECTED_SETTLED_ASSETS" ]]
platform_fee_balance="$(call_uint "$USDM" "balanceOf(address)(uint256)" "$DEPLOYER_ADDRESS")"
log "platform fee recipient balance is now $platform_fee_balance raw units"

investor1_balance_before="$(call_uint "$USDM" "balanceOf(address)(uint256)" "$settle_investor1")"
investor2_balance_before="$(call_uint "$USDM" "balanceOf(address)(uint256)" "$settle_investor2")"
expected_redeem_1=7140000000
expected_redeem_2=4760000000

log "redeeming final settlement proceeds"
send_tx "$SETTLE_INVESTOR1_KEY" "$share_token" "redeem(uint256,address,address)" "$investor1_shares" "$settle_investor1" "$settle_investor1" >/dev/null
send_tx "$SETTLE_INVESTOR2_KEY" "$share_token" "redeem(uint256,address,address)" "$investor2_shares" "$settle_investor2" "$settle_investor2" >/dev/null

investor1_balance_after="$(call_uint "$USDM" "balanceOf(address)(uint256)" "$settle_investor1")"
investor2_balance_after="$(call_uint "$USDM" "balanceOf(address)(uint256)" "$settle_investor2")"
[[ $(( investor1_balance_after - investor1_balance_before )) -eq expected_redeem_1 ]]
[[ $(( investor2_balance_after - investor2_balance_before )) -eq expected_redeem_2 ]]

remaining_total_assets="$(call_uint "$share_token" "totalAssets()(uint256)")"
[[ "$remaining_total_assets" == "0" ]]

fee_delta=$(( platform_fee_balance - 1956009316478 ))
[[ "$fee_delta" == "$EXPECTED_PLATFORM_FEE" ]]

log "validation complete"
echo "SMOKE_SALE=$smoke_sale"
echo "REFUND_SALE=$refund_sale"
echo "SETTLEMENT_SALE=$settlement_sale"
echo "SETTLEMENT_SHARE_TOKEN=$share_token"
