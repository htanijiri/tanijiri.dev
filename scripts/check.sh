#!/usr/bin/env bash
# 仕様書 000〜002 の受け入れ条件のうち、コマンドで確認できるものをまとめて確認する。
# 使い方：
#   scripts/check.sh                      # 本番（https://tanijiri.dev）
#   scripts/check.sh http://localhost:8000 # ローカル（python3 -m http.server -d public 8000）
# 失敗が1つでもあれば終了コード 1 を返す。
set -u

BASE="${1:-https://tanijiri.dev}"
BASE="${BASE%/}"
IS_PROD=0
[ "$BASE" = "https://tanijiri.dev" ] && IS_PROD=1

FAIL=0
ok() { printf '  OK   %s\n' "$1"; }
ng() { printf '  NG   %s\n' "$1"; FAIL=1; }
status() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

HTML="$(curl -s "$BASE/")"
# 表示される本文（タグを除いたテキスト）。meta タグの中の文言では合格させない
TEXT="$(sed -n '/<body/,/<\/body>/p' <<<"$HTML" | sed 's/<[^>]*>//g' | tr -d '\n')"
CSS="$(curl -s "$BASE/style.css")"
if [ -z "$HTML" ] || [ -z "$CSS" ]; then
  echo "トップページか style.css を取得できなかった（${BASE}）。サーバーが起動しているか確認する" >&2
  exit 2
fi

echo "== 000 基盤とデプロイ（${BASE}）"
[ "$(status "$BASE/")" = "200" ] && ok "AC1 トップが 200" || ng "AC1 トップが 200"
[ "$(status "$BASE/this-page-does-not-exist")" = "404" ] && ok "AC3 存在しないパスが 404" || ng "AC3 存在しないパスが 404"
for f in TASKS.md CLAUDE.md; do
  [ "$(status "$BASE/$f")" = "404" ] && ok "AC8 /$f が 404（public/ の外を配信しない）" || ng "AC8 /$f が 404"
done
if [ "$IS_PROD" = 1 ]; then
  loc="$(curl -sI http://tanijiri.dev/ | tr -d '\r' | awk 'tolower($1)=="location:"{print $2}')"
  code="$(status http://tanijiri.dev/)"
  { [ "$code" = "301" ] || [ "$code" = "308" ]; } && [ "$loc" = "https://tanijiri.dev/" ] \
    && ok "AC2 http → https（${code}）" || ng "AC2 http → https（${code} ${loc}）"
  loc="$(curl -sI https://www.tanijiri.dev/ | tr -d '\r' | awk 'tolower($1)=="location:"{print $2}')"
  code="$(status https://www.tanijiri.dev/)"
  [ "$code" = "301" ] && [ "$loc" = "https://tanijiri.dev/" ] \
    && ok "AC4 www → apex（301）" || ng "AC4 www → apex（${code} ${loc}）"
fi

echo "== 001 プロフィールページ"
for t in "エンジニア / 個人開発" "自分が使うものを、自分でつくるのが好きです。" "谷尻 浩" "HIROSHI TANIJIRI"; do
  grep -qF "$t" <<<"$TEXT" && ok "AC1 「${t}」がある" || ng "AC1 「${t}」がある"
done
for u in https://github.com/htanijiri https://zenn.dev/htanijiri; do
  grep -qF "href=\"$u\"" <<<"$HTML" || { ng "AC2 $u へのリンクがある"; continue; }
  [ "$(status -L "$u")" = "200" ] && ok "AC2 $u が 200" || ng "AC2 $u が 200"
done
grep -qF 'href="mailto:hiroshi@tanijiri.dev"' <<<"$HTML" && ok "AC3 mailto がある" || ng "AC3 mailto がある"
colors="$(grep -oiE '#[0-9a-f]{3,8}\b|rgba?\([^)]*\)|hsla?\([^)]*\)' <<<"$CSS" | tr 'a-f' 'A-F' | sort -u | tr '\n' ' ')"
extra="$(tr ' ' '\n' <<<"$colors" | grep -v '^$' | grep -vxE '#23282D|#6E7781|#1F7A6C|#FFFFFF|#FFF' || true)"
[ -z "$extra" ] && ok "AC4 CSS の色は4色だけ（${colors}）" || ng "AC4 CSS に4色以外の色がある：${extra}"
for m in '<html lang="ja">' 'name="viewport" content="width=device-width, initial-scale=1"' '<title>' 'name="description"' 'property="og:title"' 'property="og:description"' 'property="og:url"' 'property="og:type"'; do
  grep -qF "$m" <<<"$HTML" && ok "AC7 $m がある" || ng "AC7 $m がある"
done
for f in favicon-32.png apple-touch-icon.png icon.webp; do
  [ "$(status "$BASE/$f")" = "200" ] && ok "AC12 /$f が 200" || ng "AC12 /$f が 200"
done
icon_size="$(curl -s "$BASE/icon.webp" | wc -c | tr -d ' ')"
[ "$icon_size" -le 30720 ] && ok "AC12 icon.webp が 30KB 以下（${icon_size}B）" || ng "AC12 icon.webp が 30KB 以下（${icon_size}B）"
grep -qE '<img [^>]*alt="[^"]+"[^>]*width="[0-9]+"[^>]*height="[0-9]+"' <<<"$HTML" && ok "AC12 img に alt・width・height" || ng "AC12 img に alt・width・height"
n="$(grep -c 'target="_blank"' <<<"$HTML")"
[ "$n" = "0" ] && ok "AC12 target=\"_blank\" がない" || ng "AC12 target=\"_blank\" が ${n} 個ある"
total=0
for f in / /style.css /icon.webp /favicon-32.png; do
  total=$((total + $(curl -s "$BASE$f" | wc -c | tr -d ' ')))
done
[ "$total" -le 102400 ] && ok "AC9 初回表示のファイル合計が 100KB 以下（圧縮前 ${total}B）" || ng "AC9 初回表示のファイル合計が 100KB 以下（${total}B）"

echo "== 002 作っているもの一覧"
for name in "local-llm-transcriber" "おでかけスカウト" "2036 Personal AI Network"; do
  grep -qF "<h3>$name</h3>" <<<"$HTML" && ok "AC1 「${name}」がある" || ng "AC1 「${name}」がある"
done
# 自サイト（canonical など）は 000 で確認するので除く
links="$(grep -oE 'href="https://[^"]+"' <<<"$HTML" | sed 's/^href="//; s/"$//' | grep -v '^https://tanijiri.dev' | sort -u)"
for u in $links; do
  [ "$(status -L "$u")" = "200" ] && ok "AC2 $u が 200" || ng "AC2 $u が 200"
done

echo
[ "$FAIL" = 0 ] && echo "すべて OK" || echo "NG があります"
exit "$FAIL"
