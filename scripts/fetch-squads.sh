#!/usr/bin/env bash
# Prints the current squads and coaches for the scripted demo match
# (Arsenal v Chelsea, plus Liverpool v Manchester City for the side match)
# so mock-match-script.json only names real players.
#
# Usage: bash scripts/fetch-squads.sh > /tmp/squads.txt
# The key comes from $API_FOOTBALL_KEY, else the macOS Keychain item
# "copahud-apifootball" (add it once with:
#   security add-generic-password -a "$USER" -s copahud-apifootball -w
# which prompts for the key without echoing it). Nothing is written to the repo.
set -euo pipefail

API_FOOTBALL_KEY="${API_FOOTBALL_KEY:-$(security find-generic-password -s copahud-apifootball -w 2>/dev/null || true)}"
if [[ -z "${API_FOOTBALL_KEY}" ]]; then
  echo "No API-Football key: set API_FOOTBALL_KEY or add the Keychain item 'copahud-apifootball'." >&2
  exit 1
fi

api() {
  curl -fsS -H "x-apisports-key: ${API_FOOTBALL_KEY}" "https://v3.football.api-sports.io/$1"
}

for team in 42 49 40 50; do
  api "players/squads?team=${team}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
errors = d.get("errors")
if errors: sys.exit("API error: " + str(errors))
for entry in d["response"]:
    t = entry["team"]
    print("## {}\t{}".format(t["id"], t["name"]))
    for p in entry["players"]:
        print("{}\t{}\t{}\t{}".format(p["id"], p.get("number"), p.get("position"), p["name"]))
'
  api "coachs?team=${team}" | TEAM="${team}" python3 -c '
import json, os, sys
team = int(os.environ["TEAM"])
d = json.load(sys.stdin)
current = [c["name"] for c in d["response"]
           if any((j.get("team") or {}).get("id") == team and j.get("end") is None for j in c.get("career", []))]
print("coach\t" + (current[0] if current else "unknown"))
'
done
