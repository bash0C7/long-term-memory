---
name: long-term-memory-ingest-vault
description: ディレクトリ（Obsidian vault・コードリポジトリ等）を長期記憶 DB に一括取り込みする
---

# Vault 一括取り込み

ディレクトリ内のテキストファイルを長期記憶 DB に一括取り込みする。
同一内容の重複取り込みは自動でスキップされる（冪等）。

## 基本コマンド

```bash
cd /Users/bash/dev/src/github.com/bash0C7/long-term-memory
bundle exec ruby scripts/ingest_directory.rb /path/to/directory \
  --source obsidian \
  --project my-vault
```

## オプション

| オプション | デフォルト | 説明 |
|---|---|---|
| `--source SOURCE` | obsidian | 記憶のソース名（obsidian / claude_code / notes など） |
| `--project NAME` | ディレクトリ名 | プロジェクト名（後で絞り込みに使う） |
| `--ext md,txt,rb` | md,txt,rb,yaml,yml | 対象拡張子（カンマ区切り） |

## よく使うパターン

### Obsidian vault

```bash
bundle exec ruby scripts/ingest_directory.rb ~/Documents/ObsidianVault \
  --source obsidian \
  --project obsidian-vault
```

### コードリポジトリ（Ruby + Markdown のみ）

```bash
bundle exec ruby scripts/ingest_directory.rb ~/dev/my-project \
  --source code \
  --project my-project \
  --ext rb,md
```

### 取り込み後に件数確認

```bash
bundle exec ruby -e "
require_relative 'lib/memory_store'
s = MemoryStore.new('db/memory.db')
puts s.stats.inspect
s.close
"
```

## 注意

- サブディレクトリを再帰的に処理する
- 空ファイルはスキップされる
- バイナリファイルや読み取りエラーのファイルは警告を出してスキップされる
- 同じ内容を再度取り込んでも DB に重複は発生しない
