---
name: long-term-memory-register
description: 新しい Mac に long-term-memory の MCP を登録する。git pull 後に実行する。
---

# long-term-memory 登録セットアップ

新しい Mac または環境再セットアップ時に実行する。`git pull` 後に叩けば OK。

long-term-memory は **hook を登録しない方針**（保存は MCP ツール経由で明示的に行う）。登録対象は MCP サーバーのみ。

## Step 1: gems インストール

```bash
cd /Users/bash/dev/src/github.com/bash0C7/long-term-memory
bundle install
```

## Step 2: テスト確認

```bash
bundle exec ruby test/test_memory_store.rb 2>/dev/null
```

## Step 3: Claude Desktop MCP を登録

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

## Step 4: Claude Code MCP 確認

`.claude/settings.json`（プロジェクト）に `mcpServers` が含まれているか確認:

```bash
cat /Users/bash/dev/src/github.com/bash0C7/long-term-memory/.claude/settings.json
```

`long-term-memory` の `mcpServers` エントリがあれば OK。

## Step 5: 登録確認

```bash
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
