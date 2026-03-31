---
name: memory-backup
description: 長期記憶 DB のバックアップ・リストア・古いバックアップの整理
---

# DB バックアップ・リストア

`db/memory.db` はローカルファイルなので、定期バックアップを推奨する。

## バックアップ作成

```bash
cd /Users/bash/dev/src/github.com/bash0C7/long-term-memory
cp db/memory.db db/memory_backup_$(date +%Y%m%d_%H%M%S).db
echo "バックアップ完了: db/memory_backup_$(date +%Y%m%d_%H%M%S).db"
```

## バックアップ一覧

```bash
ls -lh db/memory_backup_*.db 2>/dev/null || echo "バックアップなし"
```

## リストア

**リストア前に現在の DB を退避すること。**

```bash
# 現在の DB を退避
cp db/memory.db db/memory_before_restore_$(date +%Y%m%d_%H%M%S).db

# バックアップからリストア
cp db/memory_backup_YYYYMMDD_HHMMSS.db db/memory.db
echo "リストア完了"
```

## リストア後の確認

```bash
bundle exec ruby -e "
require_relative 'lib/memory_store'
s = MemoryStore.new('db/memory.db')
puts s.stats.inspect
s.close
"
```

## 古いバックアップを削除（7日以上前）

```bash
find db/ -name "memory_backup_*.db" -mtime +7 -exec rm {} \; -print
```

## 外部ストレージへのコピー例

```bash
# Time Machine 対象外ディレクトリに保管している場合の手動コピー
cp db/memory.db ~/Dropbox/backups/long-term-memory_$(date +%Y%m%d).db
```

## 注意

- `db/*.db` はすべて `.gitignore` 対象（git には含まれない）
- `db/.gitkeep` だけが git 管理対象
- 重要な記憶が増えたら外部ストレージへの定期コピーを検討する
