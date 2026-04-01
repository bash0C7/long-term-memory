---
name: long-term-memory-migrate
description: long-term-memory DBのマイグレーション手順とメンテナンス操作リファレンス
---

# long-term-memory migrate

## summary/keywords マイグレーション（初回のみ）

既存DBに `summary` / `keywords` カラムを追加し全レコードを再処理する。

### バックアップ

    cp db/memory.db db/memory.db.bak.$(date +%Y%m%d_%H%M%S)

### マイグレーション実行

    bundle exec ruby scripts/migrate_add_summary_keywords.rb

### 確認

    bundle exec ruby -e "
    \$LOAD_PATH.unshift('lib')
    require 'memory_store'
    class StubEmbedder
      VECTOR_SIZE = 768
      def embed(t); [0.0] * 768; end
    end
    store = MemoryStore.new('db/memory.db', embedder: StubEmbedder.new)
    puts store.stats.inspect
    row = store.db.execute('SELECT id, summary, keywords FROM memories LIMIT 1').first
    puts row.inspect
    "

### ロールバック

    cp db/memory.db.bak.<timestamp> db/memory.db

## 将来のスキーマ変更手順

1. `scripts/migrate_<feature>.rb` を新規作成
2. `cp db/memory.db db/memory.db.bak.$(date +%Y%m%d_%H%M%S)` でバックアップ
3. `bundle exec ruby scripts/migrate_<feature>.rb` を実行
4. 確認クエリで検証
5. 問題があれば `cp db/memory.db.bak.<timestamp> db/memory.db` でロールバック
