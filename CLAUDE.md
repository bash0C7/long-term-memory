# CLAUDE.md — long-term-memory

## プロジェクト概要

Claude Code / Claude Desktop のやりとりを SQLite + ベクトル DB に長期保存し、MCP ツール経由で検索・参照できるようにするシステム。

- **言語:** Ruby 4.0.1（Python 絶対禁止）
- **DB:** SQLite3 + sqlite-vec（FTS5 trigram + vec0 768次元）
- **埋め込みモデル:** `mochiya98/ruri-v3-310m-onnx`（informers gem、ONNX、VECTOR_SIZE=768）
- **MCP SDK:** `mcp` gem（modelcontextprotocol/ruby-sdk）
- **テスト:** test-unit xUnit スタイル（t-wada スタイル TDD）

---

## 開発ルール

### 言語・依存

- Python（`python3`、`.py`、`pip`）絶対禁止
- gems はプロジェクト配下に閉じる: `bundle config set --local path 'vendor/bundle'`
- すべての Ruby コマンドは `bundle exec` 経由で実行する

### TDD

- Red → Green → Refactor の順を守る
- テストファイルは絶対に削除しない
- スタブは `StubEmbedder`（`test/test_helper.rb`）を使い、実モデルをテストで起動しない

### git

- conventional commits スタイル（`feat:` / `fix:` / `test:` / `chore:` / `docs:`）
- コミットメッセージは英語
- `.claude/` ディレクトリの内容も必ずコミットに含める

### スコープ規律

- 指示されたファイル以外は変更しない
- スコープ外の変更が必要な場合はユーザーに確認してから行う

---

## 重要な実装メモ

### sqlite-vec の require

```ruby
require 'sqlite_vec'   # アンダースコア（ハイフンではない）
```

### MCP::Tool のエラーレスポンス

```ruby
MCP::Tool::Response.new([{ type: "text", text: "..." }], error: true)
# is_error: ではなく error: キーワード
# 確認は response.error? メソッド
```

### FTS5 の日本語対応

`tokenize='trigram'` を使用（3文字以上の部分一致）。
2文字以下の検索語は FTS5 にヒットしないのでテストに注意。

`MemoryStore#search` は FTS5 に渡す前にクエリの演算子文字を除去する:

```ruby
fts_query = query.gsub(/[-+*^"()]/, ' ').squeeze(' ').strip
```

ハイフン付きスキル名（例: `"dotfiles-status"`）をそのまま渡しても安全。

### content_hash による冪等性

`Digest::SHA256.hexdigest(content)` を UNIQUE INDEX で管理。
同一内容の二重保存は DB 層で自動スキップされる。

### 埋め込みバイナリ

```ruby
embedding.pack("f*")   # float配列 → blob
```

### created_at フォーマット

```ruby
Time.now.iso8601   # RFC 3339（タイムゾーンオフセットにコロンあり）
```

### stats メソッドの返却キー

```ruby
stats = store.stats
# 正しいキー: :total, :by_source, :oldest_at, :newest_at
# NG: :total_memories, :total_vectors, :db_size_mb（存在しない）
stats[:total]      # Integer
stats[:by_source]  # Hash { source => count }
stats[:oldest_at]  # String (ISO8601)
stats[:newest_at]  # String (ISO8601)
```

### CLIで素早くDB確認する場合のStubEmbedder

ONNX モデルのロードを避けて stats/list だけ確認したいとき:

```ruby
require_relative 'lib/memory_store'
class StubEmbedder
  VECTOR_SIZE = 768                  # VECTOR_SIZE 定数が必須
  def embed(t); [0.0] * 768; end
end
store = MemoryStore.new('db/memory.db', embedder: StubEmbedder.new)
```

---

## ファイル構成と責務

| ファイル | 責務 |
|---|---|
| `lib/embedder.rb` | informers ONNX パイプライン、`embed(text)` |
| `lib/memory_store.rb` | DB 初期化・store / search / list / delete / stats |
| `scripts/mcp_server.rb` | MCP サーバー 3ツール定義（Store/Delete/Stats）+ 起動エントリポイント。読み取りは chiebukuro-mcp 経由 |
| `scripts/start_mcp.sh` | Claude Desktop 用起動スクリプト（rbenv 絶対パス） |
| `scripts/ingest_directory.rb` | ディレクトリ一括取り込み CLI |
| `scripts/rebuild_embeddings.rb` | 全レコード再ベクトル化 |
| `test/test_helper.rb` | StubEmbedder（位置重み付きハッシュ、決定論的ベクトル） |

---

## 設定ファイル

- `.claude/settings.json` — プロジェクト MCP サーバー登録（`start_mcp.sh` 経由）
- `~/Library/Application Support/Claude/claude_desktop_config.json` — Claude Desktop 向け MCP サーバー登録済み（`start_mcp.sh` 経由）
- hook は **登録しない方針**（保存は MCP ツール経由で明示的に行う）

---

## メンテナンス skills

`.claude/skills/` に以下を用意（すべて `long-term-memory-` prefix 付き）:

| スキル（呼び出し名） | ディレクトリ名 | 用途 |
|---|---|---|
| `/long-term-memory-ingest-vault` | `long-term-memory-ingest-vault/` | ディレクトリ一括取り込み |
| `/long-term-memory-search` | `long-term-memory-search/` | 検索・スコア確認 |
| `/long-term-memory-cleanup` | `long-term-memory-cleanup/` | 不要記憶削除ワークフロー |
| `/long-term-memory-backup` | `long-term-memory-backup/` | バックアップ・リストア |
| `/long-term-memory-rebuild-embeddings` | `long-term-memory-rebuild-embeddings/` | モデル変更後の再ベクトル化 |
| `/long-term-memory-stats` | `long-term-memory-stats/` | 統計・健全性チェック |
| `/long-term-memory-dump` | `long-term-memory-dump/` | 複数Mac同期用 iCloud へ NDJSON dump |
| `/long-term-memory-sync` | `long-term-memory-sync/` | 複数Mac同期用 iCloud dump を取り込み |
| `/long-term-memory-maintenance` | `long-term-memory-maintenance/` | 全操作リファレンス |
| `/long-term-memory-register` | `long-term-memory-register/` | 新 Mac セットアップ — hooks・MCP 登録 |
