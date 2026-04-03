---
name: long-term-memory-setup
description: long-term-memory のセットアップ手順を案内し、gems インストール・テスト・Claude Code/Desktop への MCP 登録を行う
---

# long-term-memory セットアップ

新しい環境でのセットアップ、または設定の確認・修正を行う。

## Step 1: gems インストール

```bash
cd /Users/bash/dev/src/github.com/bash0C7/long-term-memory
bundle install
```

`vendor/bundle` 配下にインストールされる（`.bundle/config` で設定済み）。

## Step 2: テスト実行（動作確認）

```bash
bundle exec ruby test/test_memory_store.rb
bundle exec ruby test/test_mcp_server.rb
bundle exec ruby test/test_capture_session.rb
bundle exec ruby test/test_ingest_directory.rb
bundle exec ruby test/test_rebuild_embeddings.rb
```

全テスト 0 failures / 0 errors であれば OK。

## Step 3: Claude Code への MCP 登録確認

`.claude/settings.json` に以下が設定されているか確認する:

```json
{
  "hooks": {
    "Stop": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "cd /Users/bash/dev/src/github.com/bash0C7/long-term-memory && bundle exec ruby scripts/capture_session.rb"
      }]
    }]
  },
  "mcpServers": {
    "long-term-memory": {
      "command": "/Users/bash/dev/src/github.com/bash0C7/long-term-memory/scripts/start_mcp.sh"
    }
  }
}
```

**重要:** `command` は `bundle exec ruby` ではなく `start_mcp.sh` の絶対パスを使う。
`bundle exec` では PATH 解決に失敗して MCP が接続されないことがある。

## Step 4: Claude Desktop への MCP 登録確認

`~/Library/Application Support/Claude/claude_desktop_config.json` に以下が設定されているか確認する:

```json
{
  "mcpServers": {
    "long-term-memory": {
      "command": "/Users/bash/dev/src/github.com/bash0C7/long-term-memory/scripts/start_mcp.sh"
    }
  }
}
```

設定後は Claude Desktop を再起動する。

## Step 5: MCP 接続確認

Claude Code を再起動し、`search_memory_tool` が利用可能になっているか確認する。
接続されていれば以下の5ツールが使える:

| ツール名 | 説明 |
|---|---|
| `search_memory_tool` | ハイブリッド検索（FTS5 + ベクトル + RRF） |
| `store_memory_tool` | 記憶を手動保存 |
| `list_memories_tool` | 最近の記憶を一覧表示 |
| `delete_memory_tool` | 指定 ID の記憶を削除 |
| `memory_stats_tool` | DB の統計情報 |

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
