---
name: long-term-memory-dump
description: 長期記憶 DB を iCloud Drive へ NDJSON dump する
---

# 長期記憶 dump

現在の DB を iCloud Drive へ NDJSON 形式でエクスポートする。
ファイル名は `{hostname}_{timestamp}.ndjson` — 複数 Mac 間で衝突しない。

## dump 実行

```bash
cd /Users/bash/dev/src/github.com/bash0C7/long-term-memory
bundle exec ruby scripts/dump_memories.rb
```

## 出力先確認

```bash
ls -lh "/Users/bash/Library/Mobile Documents/com~apple~CloudDocs/chiebukuro-mcp/dump/long-term-memory/"
```

## 次のステップ

他の Mac でも同様に `/memory-dump` を実行。
全台 dump 完了後、各 Mac で `/memory-sync` を実行して取り込む。
