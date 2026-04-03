---
name: long-term-memory-hooks
description: 長期記憶 DB への自動キャプチャ hook の登録・確認・テストを行う
---

# 長期記憶 hooks 設定

Claude Code のセッション・ツール操作を自動で長期記憶に保存する hook の設定。

## hook 構成

| hook | 設定ファイル | スクリプト | 用途 |
|---|---|---|---|
| `Stop` | `~/.claude/settings.local.json` | `capture_session.rb` | セッション終了時にトランスクリプト保存 |
| `PostToolUse` (Edit/Write/Bash/WebFetch/WebSearch) | `~/.claude/settings.local.json` | `capture_tool_use.rb` | ツール操作をキャプチャ |
| `PreToolUse` (Skill) | `~/.claude/settings.local.json` | `skill_context.rb` | スキル呼び出し前に関連記憶を注入 |

**注意:** Stop hook は `~/.claude/settings.local.json`（グローバル）にのみ設定する。
プロジェクトの `.claude/settings.json` に重複登録しないこと（二重キャプチャになる）。

## 設定確認

```bash
# グローバル hooks 確認
cat ~/.claude/settings.local.json | grep -A 30 '"hooks"'
```

## 正しい `~/.claude/settings.local.json` の hooks セクション

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "hooks": [{
          "type": "command",
          "command": "jq -c --arg t \"$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S JST')\" '{time: $t, tool: .tool_name, summary: (.tool_input | .command // .file_path // .pattern // .path // .prompt // \"?\")}' >> ~/.claude/tool-log.jsonl 2>/dev/null || true",
          "async": true
        }]
      },
      {
        "matcher": "Skill",
        "hooks": [{
          "type": "command",
          "command": "cd /Users/bash/dev/src/github.com/bash0C7/long-term-memory && bundle exec ruby scripts/skill_context.rb",
          "async": false
        }]
      }
    ],
    "PostToolUse": [{
      "matcher": "Edit|Write|Bash|WebFetch|WebSearch",
      "hooks": [{
        "type": "command",
        "command": "cd /Users/bash/dev/src/github.com/bash0C7/long-term-memory && bundle exec ruby scripts/capture_tool_use.rb",
        "async": true
      }]
    }],
    "Stop": [{
      "hooks": [{
        "type": "command",
        "command": "cd /Users/bash/dev/src/github.com/bash0C7/long-term-memory && bundle exec ruby scripts/capture_session.rb",
        "async": true
      }]
    }]
  }
}
```

## 動作確認（ノイズが入っていないか）

```bash
cd /Users/bash/dev/src/github.com/bash0C7/long-term-memory
bundle exec ruby -e "
require_relative 'lib/memory_store'
class StubEmbedder; VECTOR_SIZE=768; def embed(t); [0.0]*768; end; end
s = MemoryStore.new('db/memory.db', embedder: StubEmbedder.new)
rows = s.db.execute('SELECT id, source, created_at, content FROM memories ORDER BY id DESC LIMIT 5')
rows.each do |r|
  puts \"[#{r['id']}] #{r['source']} #{r['created_at']}\"
  puts \"  #{r['content'][0,100]}\"
end
s.close
" 2>/dev/null
```

`/remote-control is active` や `[unknown]` だけのエントリが増えていなければ正常。

## フィルタ仕様

**capture_session.rb**: `role == "user"` または `"assistant"` のみ保存。`system`/`unknown` ロールは除外。

**capture_tool_use.rb**: 合計コンテンツ長が `MIN_CONTENT_LENGTH = 200` 未満の場合はスキップ。
Bash は `curl`/`wget` を含むコマンドのみキャプチャ。

## hook テスト実行

```bash
cd /Users/bash/dev/src/github.com/bash0C7/long-term-memory
bundle exec ruby test/test_capture_session.rb 2>/dev/null
bundle exec ruby test/test_capture_tool_use.rb 2>/dev/null
```
