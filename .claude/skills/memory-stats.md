---
name: memory-stats
description: 長期記憶 DB の統計・健全性チェック・チューニング確認
---

# 長期記憶統計・ヘルスチェック

## 基本統計

```bash
cd /Users/bash/dev/src/github.com/bash0C7/long-term-memory
bundle exec ruby -e "
require_relative 'lib/memory_store'
s = MemoryStore.new('db/memory.db')
st = s.stats
puts '=== 長期記憶統計 ==='
puts \"総件数    : #{st[:total]}\"
puts \"source 別 :\"
st[:by_source].each { |src, cnt| puts \"  #{src}: #{cnt}\" }
puts \"最古      : #{st[:oldest_at]}\"
puts \"最新      : #{st[:newest_at]}\"
s.close
"
```

## DB ファイルサイズ

```bash
ls -lh db/memory.db 2>/dev/null || echo "DB 未作成"
```

## 健全性チェック（memories と memories_vec の件数一致）

```bash
bundle exec ruby -e "
require_relative 'lib/memory_store'
s = MemoryStore.new('db/memory.db')
total = s.stats[:total]
vec = s.db.execute('SELECT COUNT(*) as c FROM memories_vec').first['c']
puts \"memories     : #{total}\"
puts \"memories_vec : #{vec}\"
if total == vec
  puts 'OK: 件数一致'
else
  puts \"NG: #{total - vec} 件のベクトルが欠損。rebuild-embeddings スキルで再構築してください\"
end
s.close
"
```

## 検索チューニング確認

実際のクエリでスコア分布を確認する:

```bash
bundle exec ruby -e "
require_relative 'lib/memory_store'
s = MemoryStore.new('db/memory.db')
results = s.search(query: 'TUNING_QUERY', limit: 10)
puts '=== スコア分布 ==='
results.each_with_index do |r, i|
  puts \"#{i+1}. score=#{r['score'].round(6)} [#{r['source']}] #{r['content'][0,60]}\"
end
s.close
"
```

**スコアの目安:**
- `0.03` 以上: 強い関連（FTS5 + ベクトル両方でヒット）
- `0.01~0.03`: 中程度の関連
- `0.001` 以下: 弱い関連（ノイズに近い）

## FTS5 インデックスの最適化

記憶の削除を大量に行った後はインデックスを最適化する:

```bash
bundle exec ruby -e "
require_relative 'lib/memory_store'
s = MemoryStore.new('db/memory.db')
s.db.execute(\"INSERT INTO memories_fts(memories_fts) VALUES('optimize')\")
puts 'FTS5 インデックス最適化完了'
s.close
"
```

## SQLite VACUUM（DB ファイルサイズ縮小）

大量削除後にファイルサイズを縮小する（WAL モードでは接続が閉じている状態で実行）:

```bash
bundle exec ruby -e "
require 'sqlite3'
db = SQLite3::Database.new('db/memory.db')
db.execute('VACUUM')
db.close
puts 'VACUUM 完了'
"
```
