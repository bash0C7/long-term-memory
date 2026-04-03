---
name: long-term-memory-rebuild-embeddings
description: 埋め込みモデル変更後に全レコードのベクトルを再構築する
---

# 埋め込みベクトル再構築

埋め込みモデルを変更した場合、既存レコードのベクトルが古いモデルのままになる。
このスキルで全レコードを再ベクトル化する。

## いつ使うか

- `lib/embedder.rb` の `model_name` を変更したとき
- ONNX モデルファイルを更新したとき
- `Embedder::VECTOR_SIZE` が変わったとき（スキーマ再作成も必要、下記参照）

## 通常の再構築（次元数が同じ場合）

```bash
cd /Users/bash/dev/src/github.com/bash0C7/long-term-memory
bundle exec ruby scripts/rebuild_embeddings.rb
```

進捗は stderr に出力される。件数が多い場合は時間がかかる。

## 完了確認

```bash
bundle exec ruby -e "
require_relative 'lib/memory_store'
s = MemoryStore.new('db/memory.db')
total = s.stats[:total]
vec_count = s.db.execute('SELECT COUNT(*) as c FROM memories_vec').first['c']
puts \"memories: #{total}, memories_vec: #{vec_count}\"
puts vec_count == total ? 'OK: 件数一致' : 'NG: 件数不一致'
s.close
"
```

## 次元数が変わる場合（スキーマ再作成が必要）

次元数変更は破壊的操作。**必ず事前バックアップを取ること。**

```bash
# 1. バックアップ
cp db/memory.db db/memory_backup_before_migration_$(date +%Y%m%d).db

# 2. memories_vec テーブルを削除して再作成
bundle exec ruby -e "
require_relative 'lib/memory_store'
db = SQLite3::Database.new('db/memory.db')
db.results_as_hash = true
db.enable_load_extension(true)
require 'sqlite_vec'
SqliteVec.load(db)
db.enable_load_extension(false)
db.execute('DROP TABLE IF EXISTS memories_vec')
puts 'memories_vec dropped'
db.close
"

# 3. MemoryStore を開き直すと新しい VECTOR_SIZE でテーブルが再作成される
# 4. 全件再ベクトル化
bundle exec ruby scripts/rebuild_embeddings.rb
```

## 注意

- 再構築中も DB は読み取り可能（WAL モード）
- 再構築が完了するまでベクトル検索結果が混在する可能性がある
- 大規模 DB（10万件超）では数時間かかる場合がある
