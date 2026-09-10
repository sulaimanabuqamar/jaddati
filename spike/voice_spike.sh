#!/usr/bin/env bash
# JADDATI voice feasibility spike.
# Usage: bash spike/voice_spike.sh /path/to/your_sample.m4a
# Proves: sample -> instant voice clone -> Arabic speech from new text.
# Never prints the API key.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_FILE=""
for candidate in "$ROOT/.secrets/elevenlabs.key" "$ROOT/../.secrets/elevenlabs.key"; do
  [ -s "$candidate" ] && { KEY_FILE="$candidate"; break; }
done
[ -z "$KEY_FILE" ] && KEY_FILE="$ROOT/.secrets/elevenlabs.key"
OUT="$ROOT/spike/out"
API="https://api.elevenlabs.io"
mkdir -p "$OUT"

SAMPLE="${1:-}"
if [ -z "$SAMPLE" ] || [ ! -f "$SAMPLE" ]; then
  echo "ERROR: pass the path to your voice sample."
  echo "   e.g. bash spike/voice_spike.sh \"$ROOT/spike/sample.m4a\""
  exit 1
fi
if [ ! -s "$KEY_FILE" ]; then
  echo "ERROR: no API key at $KEY_FILE"; exit 1
fi
KEY="$(cat "$KEY_FILE")"

hr(){ printf '\n%s\n' "------------------------------------------------------------"; }

echo "sample: $(basename "$SAMPLE")  ($(du -h "$SAMPLE" | cut -f1))"

hr; echo "STEP 1 — account reachable, credits available"
curl -sS -X GET "$API/v1/user/subscription" -H "xi-api-key: $KEY" \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print("  tier:",d.get("tier"),"| used:",d.get("character_count"),"/",d.get("character_limit"))' \
  || { echo "  FAILED — key rejected or network down"; exit 1; }

hr; echo "STEP 2 — text-to-speech models actually available to this account"
curl -sS -X GET "$API/v1/models" -H "xi-api-key: $KEY" \
  | python3 -c '
import sys,json
for m in json.load(sys.stdin):
    if m.get("can_do_text_to_speech"):
        langs=[l.get("language_id") for l in (m.get("languages") or [])]
        print("  ", m["model_id"], "| arabic:", "yes" if "ar" in langs else "no")
'

hr; echo "STEP 3 — creating instant voice clone"
RESP="$(curl -sS -X POST "$API/v1/voices/add" \
  -H "xi-api-key: $KEY" \
  -F "name=JADDATI Spike Voice" \
  -F "files=@$SAMPLE" 2>&1)"

VOICE_ID="$(printf '%s' "$RESP" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin); print(d.get("voice_id",""))
except Exception: print("")' 2>/dev/null)"

if [ -z "$VOICE_ID" ]; then
  echo "  first attempt failed, retrying with files[] field name"
  RESP="$(curl -sS -X POST "$API/v1/voices/add" \
    -H "xi-api-key: $KEY" \
    -F "name=JADDATI Spike Voice" \
    -F "files[]=@$SAMPLE" 2>&1)"
  VOICE_ID="$(printf '%s' "$RESP" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin); print(d.get("voice_id",""))
except Exception: print("")' 2>/dev/null)"
fi

if [ -z "$VOICE_ID" ]; then
  echo "  CLONE FAILED. Raw response:"; echo "$RESP" | head -c 1200; echo; exit 1
fi
echo "  voice_id: $VOICE_ID"
printf '%s' "$RESP" | python3 -c 'import sys,json
d=json.load(sys.stdin)
rv=d.get("requires_verification")
print("  requires_verification:", rv, "" if not rv else "<-- NOTE: voice needs verification before use")'
printf '%s' "$VOICE_ID" > "$OUT/voice_id.txt"

AR='خذي وقتك يا حبيبتي، ما لازم تفهمين كل شي اليوم.'
EN='Take your time, habibti. You do not have to figure everything out today.'

gen(){ # gen <model_id> <text> <outfile> <label>
  local model="$1" text="$2" file="$3" label="$4"
  local body start end ms code
  body="$(python3 -c 'import json,sys; print(json.dumps({"text":sys.argv[1],"model_id":sys.argv[2]}))' "$text" "$model")"
  start=$(python3 -c 'import time;print(int(time.time()*1000))')
  code="$(curl -sS -o "$file" -w '%{http_code}' -X POST \
    "$API/v1/text-to-speech/$VOICE_ID?output_format=mp3_44100_128" \
    -H "xi-api-key: $KEY" -H "Content-Type: application/json" \
    -d "$body")"
  end=$(python3 -c 'import time;print(int(time.time()*1000))')
  ms=$((end-start))
  if [ "$code" = "200" ] && [ -s "$file" ]; then
    echo "  $label [$model] OK  ${ms}ms  $(du -h "$file" | cut -f1)  -> $(basename "$file")"
  else
    echo "  $label [$model] FAILED http=$code"; head -c 400 "$file"; echo
  fi
}

hr; echo "STEP 4 — generating speech from NEW text in the cloned voice"
gen "eleven_multilingual_v2" "$AR" "$OUT/arabic_multilingual_v2.mp3" "arabic"
gen "eleven_flash_v2_5"      "$AR" "$OUT/arabic_flash_v2_5.mp3"      "arabic"
gen "eleven_multilingual_v2" "$EN" "$OUT/english_multilingual_v2.mp3" "english"

hr; echo "DONE. Files in spike/out/ — play them:"
echo "  afplay \"$OUT/arabic_multilingual_v2.mp3\""
