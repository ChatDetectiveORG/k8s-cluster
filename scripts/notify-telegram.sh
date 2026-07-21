#!/usr/bin/env bash
# Send a plain-text ops notification via Telegram Bot API.
#
# Required env:
#   TELEGRAM_OPS_BOT_TOKEN
#   TELEGRAM_OPS_CHAT_ID
#
# Usage:
#   ./scripts/notify-telegram.sh "Deploy started for payment-service"
set -euo pipefail

message="${1:-}"
[ -n "$message" ] || exit 0

token="${TELEGRAM_OPS_BOT_TOKEN:-}"
chat_id="${TELEGRAM_OPS_CHAT_ID:-}"

if [ -z "$token" ] || [ -z "$chat_id" ]; then
  echo "notify-telegram: TELEGRAM_OPS_BOT_TOKEN or TELEGRAM_OPS_CHAT_ID not set; skipping" >&2
  exit 0
fi

if [ "${#message}" -gt 3500 ]; then
  message="${message:0:3500}"$'\n… (truncated)'
fi

export TELEGRAM_MESSAGE="$message"
export TELEGRAM_OPS_CHAT_ID="$chat_id"
payload="$(python3 -c 'import json, os; print(json.dumps({"chat_id": os.environ["TELEGRAM_OPS_CHAT_ID"], "text": os.environ["TELEGRAM_MESSAGE"], "disable_web_page_preview": True}))')"

curl -fsS -X POST "https://api.telegram.org/bot${token}/sendMessage" \
  -H 'Content-Type: application/json' \
  -d "$payload" >/dev/null

echo "==> telegram notification sent"
