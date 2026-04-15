---
name: long-term-memory-sync
description: iCloud Drive 上の全 Mac dump を取り込んで長期記憶を同期する
---

# 長期記憶 sync（取り込み）

iCloud Drive 上の各 Mac の最新 NDJSON dump を読み込み、本 Mac の DB へ取り込む。
`content_hash` による冪等処理で重複は自動スキップ。自 Mac 分も含めて取り込んでよい（ゼロからの再構築に対応）。

## 前提

全台で `/memory-dump` 完了済みであること。

## dump 対象ファイルを確認

```bash
ls -lh "/Users/bash/Library/Mobile Documents/com~apple~CloudDocs/chiebukuro-mcp/dump/long-term-memory/"
```

## sync 実行

```bash
cd /Users/bash/dev/src/github.com/bash0C7/long-term-memory
bundle exec ruby scripts/merge_memories.rb
```

## 取り込み後の件数確認

```bash
bundle exec ruby -e "
require_relative 'lib/memory_store'
s = MemoryStore.new('db/memory.db')
st = s.stats
puts \"総件数: #{st[:total]}\"
st[:by_source].each { |src, cnt| puts \"  #{src}: #{cnt}\" }
s.close
"
```
