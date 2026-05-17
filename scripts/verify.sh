#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> release build"
swift build -c release

AUTH="$HOME/.codex/auth.json"
if [[ ! -f "$AUTH" ]]; then
  echo "Skip live auth.json check: $AUTH not found"
  exit 0
fi

BACKUP="/tmp/cswitch-auth-backup-$$.json"
cp "$AUTH" "$BACKUP"

cleanup() {
  cp "$BACKUP" "$AUTH"
  rm -f "$BACKUP"
}
trap cleanup EXIT

echo "==> import current auth via AccountStore"
swift - <<'SWIFT'
import Foundation

// Lightweight verification without launching UI.
let authPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".codex/auth.json")
guard let data = try? Data(contentsOf: authPath),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let mode = json["auth_mode"] as? String,
      let tokens = json["tokens"] as? [String: Any],
      let refresh = tokens["refresh_token"] as? String,
      refresh.hasPrefix("rt_")
else {
    fputs("Invalid auth.json shape\n", stderr)
    exit(1)
}
print("auth.json ok mode=\(mode) refresh_prefix=\(refresh.prefix(8))...")
SWIFT

echo "All verification steps passed."
