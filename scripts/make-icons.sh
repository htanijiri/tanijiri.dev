#!/usr/bin/env bash
# 元画像（512×512 の PNG）から、サイトのアイコンと favicon を作る。
# 使い方：scripts/make-icons.sh [元画像のパス]（省略時は brief/ の元画像。brief/ は Git 管理外）
# 必要なもの：sips（macOS 標準）、cwebp（brew install webp）、python3
set -euo pipefail

SRC="${1:-brief/Slackアイコン画像.png}"
OUT="public"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

sips -z 256 256 "$SRC" --out "$TMP/icon-256.png" >/dev/null
cwebp -quiet -q 80 -m 6 "$TMP/icon-256.png" -o "$OUT/icon.webp"
sips -z 32 32 "$SRC" --out "$OUT/favicon-32.png" >/dev/null
sips -z 180 180 "$SRC" --out "$OUT/apple-touch-icon.png" >/dev/null

# sips が付ける eXIf・cHRM のチャンクを取り除く（表示には不要なため）
python3 - "$OUT/favicon-32.png" "$OUT/apple-touch-icon.png" <<'EOF'
import struct, sys
for f in sys.argv[1:]:
    b = open(f, "rb").read()
    out, i = b[:8], 8
    while i < len(b):
        n = struct.unpack(">I", b[i:i + 4])[0]
        if b[i + 4:i + 8] not in (b"eXIf", b"cHRM"):
            out += b[i:i + 12 + n]
        i += 12 + n
    open(f, "wb").write(out)
EOF

ls -l "$OUT/icon.webp" "$OUT/favicon-32.png" "$OUT/apple-touch-icon.png"
