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

hooks の正確な JSON 構成・設定確認・テストは `/long-term-memory-hooks` スキルを参照。

```bash
SETTINGS="$HOME/.claude/settings.local.json"
LTM="/Users/bash/dev/src/github.com/bash0C7/long-term-memory"

# Stop hook が未設定かチェック
if cat "$SETTINGS" | jq -e '.hooks.Stop' > /dev/null 2>&1; then
  echo "Stop hook はすでに設定済み。スキップ。"
else
  echo "hooks が未設定。/long-term-memory-hooks スキルの設定 JSON をもとに登録してください。"
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

---

## トラブルシューティング

### MCP が接続されない

1. `scripts/start_mcp.sh` の rbenv パスが正しいか確認:
   ```bash
   head -3 scripts/start_mcp.sh
   ```
2. スクリプトに実行権限があるか確認:
   ```bash
   ls -l scripts/start_mcp.sh
   # 実行権限がなければ: chmod +x scripts/start_mcp.sh
   ```
3. 手動で起動してエラーを確認:
   ```bash
   echo '{}' | scripts/start_mcp.sh
   ```

### DB の状態確認（ONNX ロードなし）

```ruby
require_relative 'lib/memory_store'
class StubEmbedder
  VECTOR_SIZE = 768
  def embed(t); [0.0] * 768; end
end
store = MemoryStore.new('db/memory.db', embedder: StubEmbedder.new)
stats = store.stats
puts "総記憶数: #{stats[:total]}"
stats[:by_source].each { |src, cnt| puts "  #{src}: #{cnt}" }
store.close
```

**注意:** `command` は `bundle exec ruby` ではなく `start_mcp.sh` の絶対パスを使う。
`bundle exec` では PATH 解決に失敗して MCP が接続されないことがある。
