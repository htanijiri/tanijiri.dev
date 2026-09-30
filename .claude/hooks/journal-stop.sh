#!/bin/bash
# Stop hook：
#   1. Claude の最終応答を journal/raw/YYYY-MM-DD.md に追記する。
#   2. このターンで整理済みジャーナル（journal/YYYY-MM-DD.md）が書かれたかを確認し、
#      未記入なら一度だけ終了をブロックして Claude に書かせる。
#
# ユーザーが中断した場合 Stop は発火しない（その場合は journal-prompt.sh が次の指示時に注記を残す）。

PROJECT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
RAW_DIR="$PROJECT/journal/raw"
STATE_DIR="$RAW_DIR/.state"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

INPUT="$(cat)"
jq -e . >/dev/null 2>&1 <<<"$INPUT" || exit 0
SESSION_ID="$(jq -r '.session_id // "unknown"' <<<"$INPUT" 2>/dev/null)"
STOP_HOOK_ACTIVE="$(jq -r '.stop_hook_active // false' <<<"$INPUT" 2>/dev/null)"
MESSAGE="$(jq -r '.last_assistant_message // "（last_assistant_message が渡されませんでした）"' <<<"$INPUT" 2>/dev/null)"

STATE="$STATE_DIR/$SESSION_ID.json"
TODAY="$(date '+%Y-%m-%d')"
TIME="$(date '+%H:%M:%S')"

# 指示の記録がない（hook 導入前に始まったターンなど）場合は、応答だけ今日のファイルに残す
if [ -f "$STATE" ]; then
  PROMPT_DATE="$(jq -r '.date' "$STATE")"
  BASE_SIZE="$(jq -r '.journal_size' "$STATE")"
else
  PROMPT_DATE="$TODAY"
  BASE_SIZE=""
fi

RAW="$RAW_DIR/$PROMPT_DATE.md"
[ -f "$RAW" ] || printf '# %s（自動記録：指示と応答の原文）\n' "$PROMPT_DATE" >"$RAW"

LABEL="Claude応答"
[ "$STOP_HOOK_ACTIVE" = "true" ] && LABEL="Claude応答（ジャーナル記入の差し戻し後）"
LONGEST="$(grep -o '`\+' <<<"$MESSAGE" | awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')"
FENCE_LEN=$(( LONGEST >= 3 ? LONGEST + 1 : 3 ))
FENCE="$(printf '%*s' "$FENCE_LEN" '' | tr ' ' '`')"
{
  printf '\n## %s %s\n\n' "$TIME" "$LABEL"
  printf '%smarkdown\n%s\n%s\n' "$FENCE" "$MESSAGE" "$FENCE"
} >>"$RAW"

[ -n "$BASE_SIZE" ] || exit 0

# このターンで追記された整理済みジャーナルの内容を取り出す
# （日付をまたいだ場合に備え、指示日のファイルの増分と、今日のファイル全体の両方を見る）
NEW_CONTENT=""
JOURNAL="$PROJECT/journal/$PROMPT_DATE.md"
[ -f "$JOURNAL" ] && NEW_CONTENT="$(tail -c +"$((BASE_SIZE + 1))" "$JOURNAL")"
if [ "$TODAY" != "$PROMPT_DATE" ] && [ -f "$PROJECT/journal/$TODAY.md" ]; then
  NEW_CONTENT="$NEW_CONTENT$(cat "$PROJECT/journal/$TODAY.md")"
fi

MISSING=()
for heading in '### 指示（原文）' '### 実施内容' '### 結果・気づき'; do
  grep -qF -- "$heading" <<<"$NEW_CONTENT" || MISSING+=("$heading")
done

if [ ${#MISSING[@]} -eq 0 ]; then
  rm -f "$STATE"
  exit 0
fi

# 差し戻し後もまだ書かれていなければ、ループさせずに諦めて記録だけ残す
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  printf '\n> [!WARNING]\n> 整理済みジャーナル（journal/%s.md）が未記入のまま終了しました。\n' "$PROMPT_DATE" >>"$RAW"
  rm -f "$STATE"
  exit 0
fi

PROMPT_TIME="$(jq -r '.time' "$STATE" | cut -c1-5)"
REASON="このターンの作業ジャーナルが journal/$TODAY.md に記入されていません（不足している見出し: ${MISSING[*]}）。CLAUDE.md の「作業ジャーナル」のルールとフォーマットに従って、このターンのエントリを追記してください。見出しの時刻は指示を受けた $PROMPT_TIME とし、ユーザーの指示は原文のまま引用すること。追記後は、ユーザーへの返答を繰り返さず、一言だけ述べて終了してください。"
jq -n --arg reason "$REASON" '{decision: "block", reason: $reason}'
exit 0
