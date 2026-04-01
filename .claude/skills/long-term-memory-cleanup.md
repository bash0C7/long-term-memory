---
name: memory-cleanup
description: 不要な記憶の特定と削除。古い・重複・低品質なエントリを整理する
---

# 長期記憶クリーンアップ

不要な記憶を特定して削除するワークフロー。**削除は不可逆なので、先にバックアップを取ること。**

## 0. 作業前にバックアップ

```bash
cd /Users/bash/dev/src/github.com/bash0C7/long-term-memory
cp db/memory.db db/memory_backup_$(date +%Y%m%d_%H%M%S).db
```

## 1. 統計で全体像を把握

```bash
bundle exec ruby -e "
require_relative 'lib/memory_store'
s = MemoryStore.new('db/memory.db')
st = s.stats
puts \"総件数: #{st[:total]}\"
puts \"source別:\"
st[:by_source].each { |src, cnt| puts \"  #{src}: #{cnt}\" }
puts \"最古: #{st[:oldest_at]}\"
puts \"最新: #{st[:newest_at]}\"
s.close
"
```

## 2. 一覧表示（source/project 絞り込み）

```bash
bundle exec ruby -e "
require_relative 'lib/memory_store'
s = MemoryStore.new('db/memory.db')
# scope: や project: を省略すると全件
s.list(limit: 50).each do |r|
  puts \"[#{r['id']}] #{r['source']} | #{r['project']} | #{r['created_at']}\"
  puts \"  #{r['content'][0, 80]}\"
end
s.close
"
```

## 3. 特定 source をすべて一覧

```bash
bundle exec ruby -e "
require_relative 'lib/memory_store'
s = MemoryStore.new('db/memory.db')
s.list(scope: 'SOURCE_NAME', limit: 100).each do |r|
  puts \"[#{r['id']}] #{r['created_at']} #{r['content'][0, 80]}\"
end
s.close
"
```

## 4. 単一エントリを削除

```bash
bundle exec ruby -e "
require_relative 'lib/memory_store'
s = MemoryStore.new('db/memory.db')
s.delete(ID_HERE)
puts \"deleted id=#{ID_HERE}\"
s.close
"
```

## 5. 複数 ID をまとめて削除

```bash
bundle exec ruby -e "
require_relative 'lib/memory_store'
s = MemoryStore.new('db/memory.db')
ids = [1, 2, 3]  # 削除したい ID を列挙
ids.each do |id|
  s.delete(id)
  puts \"deleted id=#{id}\"
end
s.close
"
```

## 6. 特定 source のエントリをすべて削除

```bash
bundle exec ruby -e "
require_relative 'lib/memory_store'
s = MemoryStore.new('db/memory.db')
rows = s.list(scope: 'SOURCE_NAME', limit: 9999)
rows.each do |r|
  s.delete(r['id'])
  puts \"deleted id=#{r['id']}\"
end
puts \"#{rows.size} 件削除\"
s.close
"
```

## 注意

- バックアップファイル（`db/*.db`）は `.gitignore` 対象
- 削除後に `rebuild-embeddings` スキルで vec テーブルを整合させる必要はない（DELETE トリガーが自動で vec を削除する）
