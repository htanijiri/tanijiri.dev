#!/bin/bash
# UserPromptSubmit hook：ユーザーの指示を原文のまま journal/raw/YYYY-MM-DD.md に記録する。
# あわせて、Stop hook がジャーナル記入の有無を判定できるよう、指示時点の状態を保存する。
#
# 注意：UserPromptSubmit で exit 2 するとプロンプトが破棄されるため、何が起きても exit 0 で終える。
# stdout に出したテキストは Claude のコンテキストに入るので、何も出力しない。

PROJECT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
RAW_DIR="$PROJECT/journal/raw"
STATE_DIR="$RAW_DIR/.state"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

INPUT="$(cat)"
jq -e . >/dev/null 2>&1 <<<"$INPUT" || exit 0
SESSION_ID="$(jq -r '.session_id // "unknown"' <<<"$INPUT" 2>/dev/null)"
PROMPT_ID="$(jq -r '.prompt_id // ""' <<<"$INPUT" 2>/dev/null)"
PROMPT="$(jq -r '.prompt // ""' <<<"$INPUT" 2>/dev/null)"

DATE="$(date '+%Y-%m-%d')"
TIME="$(date '+%H:%M:%S')"
STATE="$STATE_DIR/$SESSION_ID.json"

# 前の指示に対して Stop が来ていない（＝中断された）場合は、その旨を残す
if [ -f "$STATE" ]; then
  PREV_DATE="$(jq -r '.date' "$STATE" 2>/dev/null)"
  printf '\n> [!NOTE]\n> 上の指示への応答は記録されていません（ユーザーによる中断の可能性）。\n' \
    >>"$RAW_DIR/$PREV_DATE.md"
fi

RAW="$RAW_DIR/$DATE.md"
[ -f "$RAW" ] || printf '# %s（自動記録：指示と応答の原文）\n' "$DATE" >"$RAW"

# 指示に含まれるバッククォートより長いフェンスで囲み、原文を崩さない
LONGEST="$(grep -o '`\+' <<<"$PROMPT" | awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')"
FENCE_LEN=$(( LONGEST >= 3 ? LONGEST + 1 : 3 ))
FENCE="$(printf '%*s' "$FENCE_LEN" '' | tr ' ' '`')"

{
  printf '\n---\n\n## %s 指示\n\n' "$TIME"
  printf '<!-- session: %s / prompt: %s -->\n\n' "$SESSION_ID" "$PROMPT_ID"
  printf '%stext\n%s\n%s\n' "$FENCE" "$PROMPT" "$FENCE"
} >>"$RAW"

# 指示時点での、その日の整理済みジャーナルのサイズを記録する（Stop で増えたかを見る）
JOURNAL="$PROJECT/journal/$DATE.md"
SIZE=0
[ -f "$JOURNAL" ] && SIZE="$(wc -c <"$JOURNAL" | tr -d ' ')"
jq -n --arg date "$DATE" --arg time "$TIME" --arg prompt_id "$PROMPT_ID" --argjson size "$SIZE" \
  '{date: $date, time: $time, prompt_id: $prompt_id, journal_size: $size}' >"$STATE" 2>/dev/null

exit 0
