---
name: long-term-memory-register
description: 新しい Mac に long-term-memory の hooks と MCP を登録する。git pull 後に実行する。
---

# long-term-memory 登録セットアップ

新しい Mac または環境再セットアップ時に実行する。`git pull` 後に叩けば OK。

## Step 1: gems インストール

```bash
cd /Users/bash/dev/src/github.com/bash0C7/long-term-memory
bundle install
```

## Step 2: テスト確認

```bash
bundle exec ruby test/test_capture_session.rb 2>/dev/null
bundle exec ruby test/test_capture_tool_use.rb 2>/dev/null
bundle exec ruby test/test_memory_store.rb 2>/dev/null
```

## Step 3: ~/.claude/settings.local.json に hooks を登録

既存の設定を壊さずに long-term-memory の hooks だけをマージする。

```bash
SETTINGS="$HOME/.claude/settings.local.json"
LTM="/Users/bash/dev/src/github.com/bash0C7/long-term-memory"

# ファイルがなければ空オブジェクトで初期化
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

# 現在の内容を確認
echo "=== 現在の hooks ==="
cat "$SETTINGS" | jq '.hooks // "なし"'
```

hooks がすでに設定されている場合は Step 4 をスキップ。
**なし** または long-term-memory の hooks がない場合は Step 4 を実行。

## Step 4: hooks を追記（未設定の場合のみ）

```bash
SETTINGS="$HOME/.claude/settings.local.json"
LTM="/Users/bash/dev/src/github.com/bash0C7/long-term-memory"

# 既存JSONに long-term-memory hooks をマージ（既存の他設定は保持）
EXISTING=$(cat "$SETTINGS")

# Stop hook が未設定かチェック
if echo "$EXISTING" | jq -e '.hooks.Stop' > /dev/null 2>&1; then
  echo "Stop hook はすでに設定済み。スキップ。"
else
  jq --arg ltm "$LTM" '
    .hooks.Stop += [{
      "hooks": [{
        "type": "command",
        "command": ("cd " + $ltm + " && bundle exec ruby scripts/capture_session.rb"),
        "async": true
      }]
    }]
    |
    .hooks.PostToolUse += [{
      "matcher": "Edit|Write|Bash|WebFetch|WebSearch",
      "hooks": [{
        "type": "command",
        "command": ("cd " + $ltm + " && bundle exec ruby scripts/capture_tool_use.rb"),
        "async": true
      }]
    }]
    |
    .hooks.PreToolUse += [
      {
        "hooks": [{
          "type": "command",
          "command": "jq -c --arg t \"$(TZ=Asia/Tokyo date \"+%Y-%m-%d %H:%M:%S JST\")\" \"{time: \\$t, tool: .tool_name, summary: (.tool_input | .command // .file_path // .pattern // .path // .prompt // \\\"?\\\")}\" >> ~/.claude/tool-log.jsonl 2>/dev/null || true",
          "async": true
        }]
      },
      {
        "matcher": "Skill",
        "hooks": [{
          "type": "command",
          "command": ("cd " + $ltm + " && bundle exec ruby scripts/skill_context.rb"),
          "async": false
        }]
      }
    ]
  ' "$SETTINGS" > /tmp/settings_merged.json && mv /tmp/settings_merged.json "$SETTINGS"
  echo "hooks を登録しました。"
fi
```

## Step 5: Claude Desktop MCP を登録

```bash
DESKTOP_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
LTM="/Users/bash/dev/src/github.com/bash0C7/long-term-memory"

[ -f "$DESKTOP_CONFIG" ] || echo '{}' > "$DESKTOP_CONFIG"

if cat "$DESKTOP_CONFIG" | jq -e '.mcpServers["long-term-memory"]' > /dev/null 2>&1; then
  echo "Claude Desktop MCP はすでに登録済み。"
else
  jq --arg ltm "$LTM" '
    .mcpServers["long-term-memory"] = {
      "command": ($ltm + "/scripts/start_mcp.sh")
    }
  ' "$DESKTOP_CONFIG" > /tmp/desktop_merged.json && mv /tmp/desktop_merged.json "$DESKTOP_CONFIG"
  echo "Claude Desktop MCP を登録しました。Claude Desktop を再起動してください。"
fi
```

## Step 6: Claude Code MCP 確認

`.claude/settings.json`（プロジェクト）に `mcpServers` が含まれているか確認:

```bash
cat /Users/bash/dev/src/github.com/bash0C7/long-term-memory/.claude/settings.json
```

`long-term-memory` の `mcpServers` エントリがあれば OK。

## Step 7: 登録確認

```bash
echo "=== hooks 登録状態 ==="
cat ~/.claude/settings.local.json | jq '.hooks | keys'

echo "=== Claude Desktop MCP ==="
cat ~/Library/Application\ Support/Claude/claude_desktop_config.json | jq '.mcpServers | keys'
```

## 完了後

- **Claude Code** を再起動 → 新スキル（`/long-term-memory-*`）がタブ補完に出る
- **Claude Desktop** を再起動 → MCP ツールが利用可能になる
