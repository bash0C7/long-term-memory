---
name: long-term-memory-maintenance
description: Long-term memory DB のメンテナンス操作（統計確認・一覧・削除・埋め込み再構築・ディレクトリ一括取り込み）
---

# 長期記憶メンテナンス

このスキルを使って長期記憶 DB を操作する。

## 統計確認

```bash
bundle exec ruby -e "
require_relative 'lib/memory_store'
store = MemoryStore.new('db/memory.db')
puts store.stats.inspect
store.close
"
```

## 最近の記憶を一覧表示

```bash
bundle exec ruby -e "
require_relative 'lib/memory_store'
store = MemoryStore.new('db/memory.db')
store.list(limit: 20).each { |r| puts \"[#{r['id']}] #{r['source']} | #{r['project']} | #{r['created_at']}\n  #{r['content'][0, 80]}...\" }
store.close
"
```

source/project で絞り込む場合:

```bash
bundle exec ruby -e "
require_relative 'lib/memory_store'
store = MemoryStore.new('db/memory.db')
store.list(scope: 'obsidian', limit: 10).each { |r| puts \"[#{r['id']}] #{r['content'][0, 80]}\" }
store.close
"
```

## 記憶を検索

```bash
bundle exec ruby -e "
require_relative 'lib/memory_store'
store = MemoryStore.new('db/memory.db')
store.search(query: 'YOUR_QUERY', limit: 5).each { |r| puts \"[#{r['id']}] score=#{r['score'].round(4)} | #{r['content'][0, 80]}\" }
store.close
"
```

## 記憶を削除

ID を確認してから削除する:

```bash
bundle exec ruby -e "
require_relative 'lib/memory_store'
store = MemoryStore.new('db/memory.db')
store.delete(ID_HERE)
puts 'deleted'
store.close
"
```

## 記憶類似分析（重複・ノイズ検出）

ベクトル類似度を使って重複・類似グループを検出する。読み取り専用、DB変更なし。

```bash
bundle exec ruby scripts/analyze_memories.rb
```

オプション:
- `--threshold FLOAT`  類似度しきい値 (default: 0.95、高いほど厳しい)
- `--limit N`          表示グループ数上限 (default: 30)

分析結果をClaudeに見せると矛盾・削除候補を判断してもらえる。
削除確定後は上記「記憶を削除」セクションで実行。

## ディレクトリ一括取り込み

```bash
bundle exec ruby scripts/ingest_directory.rb /path/to/directory --source obsidian --project my-vault
```

オプション:
- `--source SOURCE`  保存ソース名（デフォルト: obsidian）
- `--project NAME`   プロジェクト名（省略時はディレクトリ名）
- `--ext md,txt,rb`  対象拡張子（デフォルト: md,txt,rb,yaml,yml）

## 埋め込みベクトル再構築（モデル変更後）

埋め込みモデルを変更したあとは全レコードの再ベクトル化が必要:

```bash
bundle exec ruby scripts/rebuild_embeddings.rb
```

進捗は stderr に出力される。大規模 DB では時間がかかる。

## MCP サーバー起動確認

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | bundle exec ruby scripts/mcp_server.rb
```

## DB バックアップ

```bash
cp db/memory.db db/memory_backup_$(date +%Y%m%d).db
```
