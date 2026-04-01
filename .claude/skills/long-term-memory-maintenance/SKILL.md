---
name: long-term-memory-maintenance
description: やりたいことを伝えると適切な long-term-memory スキルに誘導するオーケストレーター
---

# 長期記憶メンテナンス — スキル案内

何をしたいか教えて。適切なスキルに誘導する。

## スキル一覧

| やりたいこと | スキル |
|---|---|
| 新しい Mac にセットアップ・hooks/MCP 登録 | `/long-term-memory-register` |
| hook の設定確認・テスト・修正 | `/long-term-memory-hooks` |
| DB の統計確認・健全性チェック・VACUUM | `/long-term-memory-stats` |
| 不要な記憶を探して削除 | `/long-term-memory-cleanup` |
| キーワードや意味で記憶を検索 | `/long-term-memory-search` |
| バックアップ作成・リストア | `/long-term-memory-backup` |
| ディレクトリ（Obsidian vault など）を一括取り込み | `/long-term-memory-ingest-vault` |
| 埋め込みモデル変更後にベクトルを再構築 | `/long-term-memory-rebuild-embeddings` |
| DB スキーマのマイグレーション | `/long-term-memory-migrate` |
| 複数 Mac 間で記憶を同期（export） | `/long-term-memory-dump` |
| 複数 Mac 間で記憶を同期（import） | `/long-term-memory-sync` |

## クイックコマンドリファレンス

### DB 統計確認

```bash
bundle exec ruby -e "
require_relative 'lib/memory_store'
store = MemoryStore.new('db/memory.db')
puts store.stats.inspect
total = store.stats[:total]
vec_count = store.db.execute('SELECT COUNT(*) AS c FROM memories_vec').first['c']
puts \"memories: #{total}, memories_vec: #{vec_count}\"
puts vec_count == total ? 'OK: 件数一致' : 'NG: 件数不一致'
store.close
"
```

> **注意:** `MemoryStore#db` は `results_as_hash = true` で初期化されているため、
> `execute(...).first[0]` は `nil` になる。必ず `first['カラム名']` または
> `SELECT ... AS alias` + `first['alias']` を使うこと。

### 最近の記憶を一覧表示

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

### 記憶を検索

```bash
bundle exec ruby -e "
require_relative 'lib/memory_store'
store = MemoryStore.new('db/memory.db')
store.search(query: 'YOUR_QUERY', limit: 5).each { |r| puts \"[#{r['id']}] score=#{r['score'].round(4)} | #{r['content'][0, 80]}\" }
store.close
"
```

### 記憶を削除

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

### 記憶類似分析（重複・ノイズ検出）

ベクトル類似度を使って重複・類似グループを検出する。読み取り専用、DB変更なし。

```bash
bundle exec ruby scripts/analyze_memories.rb
```

オプション:
- `--threshold FLOAT`  類似度しきい値 (default: 0.95、高いほど厳しい)
- `--limit N`          表示グループ数上限 (default: 30)

分析結果をClaudeに見せると矛盾・削除候補を判断してもらえる。
削除確定後は上記「記憶を削除」セクションで実行。

### ディレクトリ一括取り込み

```bash
bundle exec ruby scripts/ingest_directory.rb /path/to/directory --source obsidian --project my-vault
```

オプション:
- `--source SOURCE`  保存ソース名（デフォルト: obsidian）
- `--project NAME`   プロジェクト名（省略時はディレクトリ名）
- `--ext md,txt,rb`  対象拡張子（デフォルト: md,txt,rb,yaml,yml）

### 埋め込みベクトル再構築（モデル変更後）

埋め込みモデルを変更したあとは全レコードの再ベクトル化が必要:

```bash
bundle exec ruby scripts/rebuild_embeddings.rb
```

進捗は stderr に出力される。大規模 DB では時間がかかる。

### MCP サーバー起動確認

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | bundle exec ruby scripts/mcp_server.rb
```

### DB バックアップ

```bash
cp db/memory.db db/memory_backup_$(date +%Y%m%d).db
```
