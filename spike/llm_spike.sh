#!/usr/bin/env bash
# Settles, in about ten seconds, what a chat key can actually reach:
#   which models are live on it, whether the one in Secrets.plist is among
#   them, how long an answer takes, and whether the Arabic comes back readable.
#
#   bash spike/llm_spike.sh
#   bash spike/llm_spike.sh <model-id>          # try a specific model
#
# Reads LLM_API_KEY / LLM_BASE_URL / LLM_MODEL from the environment, falling
# back to Jaddati/Secrets.plist.
set -uo pipefail

plist="$(dirname "$0")/../Jaddati/Secrets.plist"
read_plist() {
  [ -f "$plist" ] || return 0
  /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null || true
}

KEY="${LLM_API_KEY:-$(read_plist LLM_API_KEY)}"
BASE="${LLM_BASE_URL:-$(read_plist LLM_BASE_URL)}"
MODEL="${1:-${LLM_MODEL:-$(read_plist LLM_MODEL)}}"
BASE="${BASE:-https://api.groq.com/openai/v1}"
BASE="${BASE%/}"

if [ -z "$KEY" ] || [ "$KEY" = "PASTE_YOUR_KEY_HERE" ]; then
  echo "No key. Put it in Jaddati/Secrets.plist under LLM_API_KEY, or export LLM_API_KEY."
  exit 1
fi

echo "Host  : $BASE"
echo "Model : $MODEL"
echo
echo "=== Models this key can reach ==="
models_json="$(curl -sS --max-time 20 -H "Authorization: Bearer $KEY" "$BASE/models")"
echo "$models_json" \
  | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | sed 's/.*"\([^"]*\)"$/  \1/' \
  | sort -u
echo

if echo "$models_json" | grep -q "\"$MODEL\""; then
  echo "OK: \"$MODEL\" is in that list."
else
  echo "WARNING: \"$MODEL\" is NOT in that list. Pick one above and put it in Secrets.plist under LLM_MODEL."
fi
echo

ask() {
  local label="$1" prompt="$2" started elapsed body
  echo "=== $label ==="
  started=$(date +%s)
  body=$(curl -sS --max-time 30 -X POST "$BASE/chat/completions" \
    -H "Authorization: Bearer $KEY" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$MODEL\",\"max_tokens\":160,\"temperature\":0.6,\"messages\":[{\"role\":\"user\",\"content\":$prompt}]}")
  elapsed=$(( $(date +%s) - started ))
  echo "$body" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("  unparseable reply:", sys.stdin.read()[:400]); raise SystemExit
if "error" in d:
    print("  ERROR:", json.dumps(d["error"])[:400])
else:
    print(" ", d["choices"][0]["message"]["content"].strip()[:400])'
  echo "  (${elapsed}s)"
  echo
}

ask "English answer" '"In one short sentence a five-year-old would understand: why is the sky blue?"'
ask "Arabic answer"  '"أجب بجملة واحدة قصيرة يفهمها طفل عمره خمس سنوات: لماذا السماء زرقاء؟"'

echo "Done. If both answers look right, the free tier and the model id are settled."
