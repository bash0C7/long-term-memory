# Long-Term Memory System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ruby + SQLite で Claude Code / Claude Desktop のやりとりを長期記憶化し、MCP サーバー経由でハイブリッド検索（FTS5 + ベクトル検索 + RRF）できるシステムを構築する。

**Architecture:** 単一 SQLite DB (`db/memory.db`) にメタデータ付きで記憶を保存し、informers gem (ONNX) + `cl-nagoya/ruri-v3-310m` で日本語埋め込みを生成、FTS5 全文検索と sqlite-vec ベクトル検索を RRF 融合してスコアリングする。MCP サーバーが `search_memory` / `store_memory` 等のツールを公開し、Claude Code Stop hook が自動キャプチャ、`ingest_directory.rb` がバルク取り込みを担う。

**Tech Stack:** Ruby 4.0.1, sqlite3 gem, sqlite-vec gem, informers gem (ONNX), mcp gem (modelcontextprotocol/ruby-sdk), test-unit gem

---

## File Map

| ファイル | 役割 |
|---|---|
| `Gemfile` | 依存 gem 宣言 |
| `.gitignore` | db/*.db を除外 |
| `lib/embedder.rb` | informers pipeline ラッパー。`embed(text) → Float[]` |
| `lib/memory_store.rb` | DB 初期化・store・search・list・delete・stats |
| `scripts/mcp_server.rb` | MCP stdio サーバー（5ツール） |
| `scripts/capture_session.rb` | Stop hook エントリポイント。stdin JSON → MemoryStore |
| `scripts/ingest_directory.rb` | CLI。ディレクトリを再帰スキャンして一括保存 |
| `scripts/rebuild_embeddings.rb` | 全エントリを再ベクトル化（モデル変更時） |
| `test/test_helper.rb` | :memory: DB の共通セットアップ、StubEmbedder 定義 |
| `test/test_embedder.rb` | Embedder 単体テスト |
| `test/test_memory_store.rb` | schema・store テスト |
| `test/test_search.rb` | FTS5・vec・RRF・time_decay テスト |
| `test/test_mcp_server.rb` | MCP ツール統合テスト |
| `test/test_capture_session.rb` | Stop hook JSON パーステスト |
| `test/test_ingest_directory.rb` | tmpdir スキャン・冪等テスト |
| `.claude/settings.json` | Stop hook 登録 + MCP サーバー登録 |
| `.claude/skills/memory-maintenance.md` | メンテナンス subagent スキル |

---

## Task 1: Project Bootstrap

**Files:**
- Create: `Gemfile`
- Create: `.gitignore`
- Create: `lib/.keep`, `scripts/.keep`, `test/.keep`, `db/.keep`

- [ ] **Step 1: Gemfile を作成する**

```ruby
# Gemfile
source "https://rubygems.org"

ruby "4.0.1"

gem "sqlite3"
gem "sqlite-vec"
gem "mcp"
gem "informers"

group :test do
  gem "test-unit"
end
```

- [ ] **Step 2: .gitignore を作成する**

```
db/*.db
db/memory.db
```

- [ ] **Step 3: ディレクトリと空ファイルを作成する**

```bash
mkdir -p lib scripts test db .claude/skills
touch lib/.keep scripts/.keep test/.keep db/.keep
```

- [ ] **Step 4: bundle install を実行する**

```bash
bundle install
```

Expected: `Bundle complete!` — sqlite3, sqlite-vec, mcp, informers, test-unit がインストールされる

- [ ] **Step 5: gem が正常にロードされることを確認する**

```bash
bundle exec ruby -e "require 'sqlite3'; require 'sqlite_vec'; require 'informers'; puts 'OK'"
```

Expected: `OK`

もし `require 'sqlite_vec'` が失敗する場合は `require 'sqlite-vec'` を試す。以降のコードでも正しい require 名を使うこと。

- [ ] **Step 6: コミットする**

```bash
git add Gemfile .gitignore lib/.keep scripts/.keep test/.keep db/.keep
git commit -m "chore: bootstrap project structure"
```

---

## Task 2: ruri-v3-310m の次元数を確認する

sqlite-vec スキーマの `FLOAT[N]` に使う次元数を実測で確定させる。

**Files:**
- Create: `scripts/probe_model.rb` (一時スクリプト、確認後削除)

- [ ] **Step 1: probe スクリプトを作成する**

```ruby
# scripts/probe_model.rb
require "informers"

pipeline = Informers.pipeline("feature-extraction", "cl-nagoya/ruri-v3-310m")
result = pipeline.("テスト文章", pooling: "mean", normalize: true)
vector = result.flatten
puts "次元数: #{vector.size}"
puts "最初の3値: #{vector.first(3).inspect}"
puts "型: #{vector.first.class}"
```

- [ ] **Step 2: 実行して次元数を記録する**

```bash
bundle exec ruby scripts/probe_model.rb
```

Expected 出力例:
```
次元数: 1024
最初の3値: [0.023, -0.041, 0.018]
型: Float
```

次元数を `VECTOR_SIZE = <確認した値>` として `lib/embedder.rb` に定義する。
もし 768 や 384 が返ってきたらその値を使う。

- [ ] **Step 3: probe スクリプトを削除してコミットする**

```bash
rm scripts/probe_model.rb
git add -A
git commit -m "chore: confirm ruri-v3-310m vector dimensions"
```

---

## Task 3: Embedder (TDD)

**Files:**
- Create: `lib/embedder.rb`
- Create: `test/test_embedder.rb`

- [ ] **Step 1: テストを書く**

```ruby
# test/test_embedder.rb
require "test/unit"
require_relative "../lib/embedder"

class TestEmbedder < Test::Unit::TestCase
  def test_embed_returns_float_array
    embedder = Embedder.new
    result = embedder.embed("テスト文章です")
    assert_instance_of Array, result
    assert_equal Embedder::VECTOR_SIZE, result.size
    assert result.all? { |v| v.is_a?(Float) }, "全要素が Float であること"
  end

  def test_embed_different_texts_give_different_vectors
    embedder = Embedder.new
    v1 = embedder.embed("りんご")
    v2 = embedder.embed("コンピュータサイエンス")
    assert v1 != v2, "異なるテキストは異なるベクトルになること"
  end

  def test_vector_is_normalized
    embedder = Embedder.new
    v = embedder.embed("正規化テスト")
    norm = Math.sqrt(v.sum { |x| x * x })
    assert_in_delta 1.0, norm, 0.01, "normalize: true なので L2ノルムが1に近いこと"
  end
end
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
bundle exec ruby test/test_embedder.rb
```

Expected: `NameError: uninitialized constant Embedder`

- [ ] **Step 3: Embedder を実装する**

Task 2 で確認した次元数を `VECTOR_SIZE` に設定する（例: 1024）。

```ruby
# lib/embedder.rb
require "informers"

class Embedder
  # Task 2 で確認した次元数に更新すること
  VECTOR_SIZE = 1024

  def initialize(model_name: "cl-nagoya/ruri-v3-310m")
    @pipeline = Informers.pipeline("feature-extraction", model_name)
  end

  def embed(text)
    result = @pipeline.(text, pooling: "mean", normalize: true)
    result.flatten.map(&:to_f)
  end
end
```

- [ ] **Step 4: テストが通ることを確認する**

```bash
bundle exec ruby test/test_embedder.rb
```

Expected: `3 tests, 3 assertions, 0 failures, 0 errors`

- [ ] **Step 5: コミットする**

```bash
git add lib/embedder.rb test/test_embedder.rb
git commit -m "feat: add Embedder with ruri-v3-310m ONNX model"
```

---

## Task 4: test_helper と MemoryStore スキーマ (TDD)

**Files:**
- Create: `test/test_helper.rb`
- Create: `lib/memory_store.rb`
- Create: `test/test_memory_store.rb`

- [ ] **Step 1: test_helper を作成する**

```ruby
# test/test_helper.rb
require "test/unit"
require "sqlite3"
require "sqlite_vec"   # Task 1 で確認した正しい require 名を使う
require_relative "../lib/embedder"
require_relative "../lib/memory_store"

# テスト用スタブ埋め込み器。モデルロードを省いて高速化する
class StubEmbedder
  VECTOR_SIZE = Embedder::VECTOR_SIZE

  def embed(text)
    # テキストのハッシュ値から決定論的なベクトルを生成
    seed = text.bytes.sum
    Array.new(VECTOR_SIZE) { |i| Math.sin(seed + i) }
  end
end
```

- [ ] **Step 2: スキーマテストを書く**

```ruby
# test/test_memory_store.rb
require_relative "test_helper"

class TestMemoryStoreSchema < Test::Unit::TestCase
  def setup
    @store = MemoryStore.new(":memory:", embedder: StubEmbedder.new)
  end

  def teardown
    @store.close
  end

  def test_memories_table_exists
    tables = @store.db.execute("SELECT name FROM sqlite_master WHERE type='table'").map { |r| r["name"] }
    assert_include tables, "memories"
  end

  def test_memories_fts_table_exists
    tables = @store.db.execute("SELECT name FROM sqlite_master WHERE type='table'").map { |r| r["name"] }
    assert_include tables, "memories_fts"
  end

  def test_memories_vec_table_exists
    tables = @store.db.execute("SELECT name FROM sqlite_master WHERE type='table'").map { |r| r["name"] }
    assert_include tables, "memories_vec"
  end
end
```

- [ ] **Step 3: テストが失敗することを確認する**

```bash
bundle exec ruby test/test_memory_store.rb
```

Expected: `NameError: uninitialized constant MemoryStore`

- [ ] **Step 4: MemoryStore のスキーマ初期化を実装する**

```ruby
# lib/memory_store.rb
require "sqlite3"
require "sqlite_vec"   # Task 1 で確認した正しい require 名を使う
require "json"
require "digest"
require "time"
require_relative "embedder"

class MemoryStore
  attr_reader :db

  def initialize(db_path, embedder: nil)
    @db = SQLite3::Database.new(db_path)
    @db.results_as_hash = true
    @db.busy_timeout = 5000
    @embedder = embedder || Embedder.new
    setup_extensions
    setup_pragmas
    create_schema
  end

  def close
    @db.close
  end

  private

  def setup_extensions
    @db.enable_load_extension(true)
    SqliteVec.load(@db)
    @db.enable_load_extension(false)
  end

  def setup_pragmas
    @db.execute("PRAGMA journal_mode=WAL")
    @db.execute("PRAGMA synchronous=NORMAL")
  end

  def create_schema
    @db.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS memories (
        id           INTEGER PRIMARY KEY,
        content      TEXT    NOT NULL,
        source       TEXT    NOT NULL,
        project      TEXT,
        tags         TEXT,
        content_hash TEXT,
        created_at   TEXT    NOT NULL
      )
    SQL

    @db.execute(<<~SQL)
      CREATE UNIQUE INDEX IF NOT EXISTS uix_content_hash
        ON memories(content_hash)
        WHERE content_hash IS NOT NULL
    SQL

    @db.execute(<<~SQL)
      CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
        content,
        tags,
        content='memories',
        content_rowid='id'
      )
    SQL

    vector_size = @embedder.class::VECTOR_SIZE
    @db.execute(<<~SQL)
      CREATE VIRTUAL TABLE IF NOT EXISTS memories_vec USING vec0(
        memory_id INTEGER PRIMARY KEY,
        embedding FLOAT[#{vector_size}]
      )
    SQL

    @db.execute(<<~SQL)
      CREATE TRIGGER IF NOT EXISTS memories_ai
        AFTER INSERT ON memories BEGIN
          INSERT INTO memories_fts(rowid, content, tags)
            VALUES (new.id, new.content, COALESCE(new.tags, ''));
        END
    SQL

    @db.execute(<<~SQL)
      CREATE TRIGGER IF NOT EXISTS memories_ad
        AFTER DELETE ON memories BEGIN
          INSERT INTO memories_fts(memories_fts, rowid, content, tags)
            VALUES ('delete', old.id, old.content, COALESCE(old.tags, ''));
        END
    SQL
  end
end
```

- [ ] **Step 5: テストが通ることを確認する**

```bash
bundle exec ruby test/test_memory_store.rb
```

Expected: `3 tests, 3 assertions, 0 failures, 0 errors`

- [ ] **Step 6: コミットする**

```bash
git add lib/memory_store.rb test/test_helper.rb test/test_memory_store.rb
git commit -m "feat: add MemoryStore with schema initialization"
```

---

## Task 5: MemoryStore#store (TDD)

**Files:**
- Modify: `lib/memory_store.rb`
- Modify: `test/test_memory_store.rb`

- [ ] **Step 1: store のテストを追加する**

`test/test_memory_store.rb` の末尾に追加：

```ruby
class TestMemoryStoreStore < Test::Unit::TestCase
  def setup
    @store = MemoryStore.new(":memory:", embedder: StubEmbedder.new)
  end

  def teardown
    @store.close
  end

  def test_store_returns_integer_id
    id = @store.store(content: "テストの記憶", source: "claude_code")
    assert_instance_of Integer, id
    assert id > 0
  end

  def test_store_persists_to_memories_table
    @store.store(content: "保存テスト", source: "claude_desktop", project: "myapp", tags: ["ruby", "test"])
    rows = @store.db.execute("SELECT * FROM memories WHERE content = '保存テスト'")
    assert_equal 1, rows.size
    row = rows.first
    assert_equal "claude_desktop", row["source"]
    assert_equal "myapp", row["project"]
    assert_equal '["ruby","test"]', row["tags"]
  end

  def test_store_syncs_to_fts
    @store.store(content: "FTS同期テスト ruby", source: "claude_code")
    rows = @store.db.execute("SELECT rowid FROM memories_fts WHERE memories_fts MATCH 'FTS同期テスト'")
    assert_equal 1, rows.size
  end

  def test_store_syncs_to_vec
    id = @store.store(content: "ベクトル保存テスト", source: "claude_code")
    rows = @store.db.execute("SELECT memory_id FROM memories_vec WHERE memory_id = ?", [id])
    assert_equal 1, rows.size
  end

  def test_store_idempotent_with_same_content_hash
    id1 = @store.store(content: "重複テスト", source: "claude_code")
    id2 = @store.store(content: "重複テスト", source: "claude_code")
    assert_equal id1, id2, "同じ content は同じ ID を返す（重複保存しない）"
    count = @store.db.execute("SELECT COUNT(*) as c FROM memories").first["c"]
    assert_equal 1, count
  end
end
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
bundle exec ruby test/test_memory_store.rb
```

Expected: `NoMethodError: undefined method 'store'`

- [ ] **Step 3: store を実装する**

`lib/memory_store.rb` の `private` より前に追加：

```ruby
def store(content:, source:, project: nil, tags: nil)
  content_hash = Digest::SHA256.hexdigest(content)

  # 冪等: 同じ content_hash が既にあればその id を返す
  existing = @db.execute(
    "SELECT id FROM memories WHERE content_hash = ?", [content_hash]
  ).first
  return existing["id"] if existing

  tags_json = tags ? JSON.generate(tags) : nil
  created_at = Time.now.strftime("%Y-%m-%dT%H:%M:%S%z")

  @db.execute(
    "INSERT INTO memories (content, source, project, tags, content_hash, created_at) VALUES (?, ?, ?, ?, ?, ?)",
    [content, source, project, tags_json, content_hash, created_at]
  )
  id = @db.last_insert_row_id

  embedding = @embedder.embed(content)
  embedding_blob = embedding.pack("f*")
  @db.execute(
    "INSERT INTO memories_vec(memory_id, embedding) VALUES (?, ?)",
    [id, embedding_blob]
  )

  id
end
```

- [ ] **Step 4: テストが通ることを確認する**

```bash
bundle exec ruby test/test_memory_store.rb
```

Expected: `8 tests, 11 assertions, 0 failures, 0 errors`

- [ ] **Step 5: コミットする**

```bash
git add lib/memory_store.rb test/test_memory_store.rb
git commit -m "feat: implement MemoryStore#store with FTS5/vec sync and idempotency"
```

---

## Task 6: MemoryStore#search — FTS5 + ベクトル + RRF + 時間減衰 (TDD)

**Files:**
- Create: `test/test_search.rb`
- Modify: `lib/memory_store.rb`

- [ ] **Step 1: search のテストを書く**

```ruby
# test/test_search.rb
require_relative "test_helper"

class TestMemoryStoreSearch < Test::Unit::TestCase
  def setup
    @store = MemoryStore.new(":memory:", embedder: StubEmbedder.new)
    @store.store(content: "Rubyでのメタプログラミングの考え方", source: "claude_code", project: "myapp", tags: ["ruby"])
    @store.store(content: "SQLiteのFTS5を使った全文検索", source: "claude_code", tags: ["sqlite", "fts"])
    @store.store(content: "ObsidianでのZettelkasten手法", source: "obsidian", tags: ["obsidian", "メモ"])
  end

  def teardown
    @store.close
  end

  def test_search_returns_array
    results = @store.search(query: "Ruby")
    assert_instance_of Array, results
  end

  def test_search_result_has_required_keys
    results = @store.search(query: "Ruby")
    assert results.size > 0
    result = results.first
    assert_include result.keys, "id"
    assert_include result.keys, "content"
    assert_include result.keys, "source"
    assert_include result.keys, "score"
    assert_include result.keys, "created_at"
  end

  def test_search_fts_finds_keyword_match
    results = @store.search(query: "全文検索")
    assert results.any? { |r| r["content"].include?("全文検索") }, "FTS5 でキーワードが見つかること"
  end

  def test_search_scope_filters_by_source
    results = @store.search(query: "メモ", scope: "obsidian")
    assert results.all? { |r| r["source"] == "obsidian" }, "scope フィルタが機能すること"
  end

  def test_search_project_filters
    results = @store.search(query: "Ruby", project: "myapp")
    assert results.all? { |r| r["project"] == "myapp" || r["project"].nil? }
    assert results.any? { |r| r["project"] == "myapp" }
  end

  def test_search_respects_limit
    results = @store.search(query: "SQLite", limit: 1)
    assert_equal 1, results.size
  end

  def test_search_scores_are_positive
    results = @store.search(query: "Ruby")
    assert results.all? { |r| r["score"] > 0 }, "スコアは正の値"
  end
end
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
bundle exec ruby test/test_search.rb
```

Expected: `NoMethodError: undefined method 'search'`

- [ ] **Step 3: search を実装する**

`lib/memory_store.rb` の `store` メソッドの後に追加（`private` より前）：

```ruby
def search(query:, scope: nil, project: nil, limit: 5)
  conditions = []
  conditions << "m.source = '#{scope.gsub("'", "''")}'" if scope
  conditions << "m.project = '#{project.gsub("'", "''")}'" if project
  where_clause = conditions.empty? ? "" : "AND #{conditions.join(' AND ')}"

  # FTS5 検索
  fts_rows = begin
    @db.execute(<<~SQL, [query, limit * 2])
      SELECT m.id, m.content, m.source, m.project, m.tags, m.created_at
      FROM memories m
      JOIN memories_fts ON memories_fts.rowid = m.id
      WHERE memories_fts MATCH ? #{where_clause}
      ORDER BY rank
      LIMIT ?
    SQL
  rescue SQLite3::Exception
    []
  end

  # ベクトル検索
  query_blob = @embedder.embed(query).pack("f*")
  vec_rows = begin
    if conditions.empty?
      @db.execute(
        "SELECT mv.memory_id, mv.distance FROM memories_vec mv ORDER BY mv.embedding <-> ? LIMIT ?",
        [query_blob, limit * 2]
      )
    else
      @db.execute(
        "SELECT mv.memory_id, mv.distance FROM memories_vec mv JOIN memories m ON m.id = mv.memory_id WHERE 1=1 #{where_clause} ORDER BY mv.embedding <-> ? LIMIT ?",
        [query_blob, limit * 2]
      )
    end
  rescue SQLite3::Exception
    []
  end

  # RRF 融合
  k = 60
  scores = Hash.new(0.0)

  fts_rows.each_with_index do |row, rank|
    id = row["id"] || row[0]
    scores[id] += 1.0 / (k + rank + 1)
  end

  vec_rows.each_with_index do |row, rank|
    id = row["memory_id"] || row[0]
    scores[id] += 1.0 / (k + rank + 1)
  end

  return [] if scores.empty?

  # 時間減衰をかけてスコア確定
  all_ids = scores.keys
  placeholders = all_ids.map { "?" }.join(",")
  meta_rows = @db.execute(
    "SELECT id, content, source, project, tags, created_at FROM memories WHERE id IN (#{placeholders})",
    all_ids
  )
  meta_by_id = meta_rows.each_with_object({}) { |r, h| h[r["id"]] = r }

  scored = scores.map do |id, rrf|
    row = meta_by_id[id]
    next unless row
    age_days = (Time.now - Time.parse(row["created_at"])).abs / 86400.0
    decay = 0.5 ** (age_days / 30.0)
    row.merge("score" => rrf * decay)
  end.compact

  scored.sort_by { |r| -r["score"] }.first(limit)
end
```

- [ ] **Step 4: テストが通ることを確認する**

```bash
bundle exec ruby test/test_search.rb
```

Expected: `7 tests, 10 assertions, 0 failures, 0 errors`

- [ ] **Step 5: コミットする**

```bash
git add lib/memory_store.rb test/test_search.rb
git commit -m "feat: implement MemoryStore#search with FTS5+vec+RRF+time_decay"
```

---

## Task 7: MemoryStore メンテナンスメソッド (TDD)

**Files:**
- Modify: `lib/memory_store.rb`
- Modify: `test/test_memory_store.rb`

- [ ] **Step 1: メンテナンスメソッドのテストを追加する**

`test/test_memory_store.rb` の末尾に追加：

```ruby
class TestMemoryStoreMaintenance < Test::Unit::TestCase
  def setup
    @store = MemoryStore.new(":memory:", embedder: StubEmbedder.new)
    @store.store(content: "記憶1", source: "claude_code", project: "proj_a")
    @store.store(content: "記憶2", source: "claude_desktop")
    @store.store(content: "記憶3", source: "obsidian", project: "proj_a")
  end

  def teardown
    @store.close
  end

  def test_list_returns_all_by_default
    results = @store.list
    assert_equal 3, results.size
  end

  def test_list_filters_by_scope
    results = @store.list(scope: "claude_code")
    assert_equal 1, results.size
    assert_equal "claude_code", results.first["source"]
  end

  def test_list_filters_by_project
    results = @store.list(project: "proj_a")
    assert_equal 2, results.size
    assert results.all? { |r| r["project"] == "proj_a" }
  end

  def test_list_respects_limit
    results = @store.list(limit: 2)
    assert_equal 2, results.size
  end

  def test_delete_removes_record
    id = @store.store(content: "削除テスト", source: "claude_code")
    @store.delete(id)
    rows = @store.db.execute("SELECT id FROM memories WHERE id = ?", [id])
    assert_equal 0, rows.size
  end

  def test_delete_removes_from_vec
    id = @store.store(content: "vec削除テスト", source: "claude_code")
    @store.delete(id)
    rows = @store.db.execute("SELECT memory_id FROM memories_vec WHERE memory_id = ?", [id])
    assert_equal 0, rows.size
  end

  def test_stats_returns_counts
    stats = @store.stats
    assert_equal 3, stats[:total]
    assert_equal 1, stats[:by_source]["claude_code"]
    assert_equal 1, stats[:by_source]["claude_desktop"]
    assert_equal 1, stats[:by_source]["obsidian"]
    assert_not_nil stats[:oldest_at]
    assert_not_nil stats[:newest_at]
  end
end
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
bundle exec ruby test/test_memory_store.rb
```

Expected: `NoMethodError: undefined method 'list'`

- [ ] **Step 3: list・delete・stats を実装する**

`lib/memory_store.rb` の `search` の後に追加（`private` より前）：

```ruby
def list(scope: nil, project: nil, limit: 20)
  conditions = []
  conditions << "source = ?" if scope
  conditions << "project = ?" if project
  where = conditions.empty? ? "" : "WHERE #{conditions.join(' AND ')}"
  params = [scope, project].compact + [limit]
  @db.execute("SELECT id, content, source, project, tags, created_at FROM memories #{where} ORDER BY created_at DESC LIMIT ?", params)
end

def delete(id)
  @db.transaction do
    @db.execute("DELETE FROM memories_vec WHERE memory_id = ?", [id])
    @db.execute("DELETE FROM memories WHERE id = ?", [id])
  end
end

def stats
  total = @db.execute("SELECT COUNT(*) as c FROM memories").first["c"]
  by_source = @db.execute("SELECT source, COUNT(*) as c FROM memories GROUP BY source")
    .each_with_object({}) { |r, h| h[r["source"]] = r["c"] }
  oldest = @db.execute("SELECT MIN(created_at) as t FROM memories").first["t"]
  newest = @db.execute("SELECT MAX(created_at) as t FROM memories").first["t"]
  { total: total, by_source: by_source, oldest_at: oldest, newest_at: newest }
end
```

- [ ] **Step 4: テストが通ることを確認する**

```bash
bundle exec ruby test/test_memory_store.rb
```

Expected: `15 tests, 22 assertions, 0 failures, 0 errors`

- [ ] **Step 5: コミットする**

```bash
git add lib/memory_store.rb test/test_memory_store.rb
git commit -m "feat: add MemoryStore list/delete/stats maintenance methods"
```

---

## Task 8: MCP サーバー (TDD)

**Files:**
- Create: `scripts/mcp_server.rb`
- Create: `test/test_mcp_server.rb`

- [ ] **Step 1: MCP ツールのテストを書く**

```ruby
# test/test_mcp_server.rb
require_relative "test_helper"
require_relative "../scripts/mcp_server"

class TestSearchMemoryTool < Test::Unit::TestCase
  def setup
    @store = MemoryStore.new(":memory:", embedder: StubEmbedder.new)
    @store.store(content: "Rubyのブロックとプロック", source: "claude_code", tags: ["ruby"])
    @store.store(content: "ObsidianのPKM戦略", source: "obsidian")
  end

  def teardown
    @store.close
  end

  def test_search_memory_returns_text_response
    response = SearchMemoryTool.call(
      query: "Ruby",
      server_context: { memory_store: @store }
    )
    assert_instance_of MCP::Tool::Response, response
    assert response.content.first[:text].include?("Ruby"), "検索結果に Ruby が含まれること"
  end

  def test_search_memory_with_scope
    response = SearchMemoryTool.call(
      query: "PKM",
      scope: "obsidian",
      server_context: { memory_store: @store }
    )
    text = response.content.first[:text]
    assert text.include?("obsidian") || text.include?("PKM")
  end

  def test_search_memory_empty_query_returns_error
    response = SearchMemoryTool.call(
      query: "",
      server_context: { memory_store: @store }
    )
    assert response.content.first[:text].include?("error") || response.is_error
  end
end

class TestStoreMemoryTool < Test::Unit::TestCase
  def setup
    @store = MemoryStore.new(":memory:", embedder: StubEmbedder.new)
  end

  def teardown
    @store.close
  end

  def test_store_memory_saves_record
    response = StoreMemoryTool.call(
      content: "新しい記憶",
      source: "claude_desktop",
      server_context: { memory_store: @store }
    )
    assert_instance_of MCP::Tool::Response, response
    count = @store.db.execute("SELECT COUNT(*) as c FROM memories").first["c"]
    assert_equal 1, count
  end
end

class TestMemoryStatsTool < Test::Unit::TestCase
  def setup
    @store = MemoryStore.new(":memory:", embedder: StubEmbedder.new)
    @store.store(content: "統計テスト", source: "claude_code")
  end

  def teardown
    @store.close
  end

  def test_memory_stats_returns_counts
    response = MemoryStatsTool.call(server_context: { memory_store: @store })
    text = response.content.first[:text]
    assert text.include?("1"), "総件数 1 が含まれること"
  end
end
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
bundle exec ruby test/test_mcp_server.rb
```

Expected: `LoadError` または `NameError`

- [ ] **Step 3: MCP サーバーを実装する**

```ruby
# scripts/mcp_server.rb
$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))
require "mcp"
require "json"
require "memory_store"
require "embedder"

DB_PATH = File.expand_path("../../db/memory.db", __FILE__).freeze

class SearchMemoryTool < MCP::Tool
  description <<~DESC
    長期記憶をハイブリッド検索（FTS5+ベクトル+RRF）で照会する。
    query に scope ワード（"obsidian", "claude_code" など）や
    プロジェクト名を含めると絞り込みが効く。
  DESC

  input_schema(
    properties: {
      query:   { type: "string",  description: "検索クエリ" },
      scope:   { type: "string",  description: "source 絞り込み: claude_code | claude_desktop | obsidian" },
      project: { type: "string",  description: "プロジェクト名絞り込み" },
      limit:   { type: "integer", description: "最大件数（デフォルト 5）" }
    },
    required: ["query"]
  )

  class << self
    def call(query:, scope: nil, project: nil, limit: 5, server_context:)
      return MCP::Tool::Response.new([{ type: "text", text: '{"error":"query is required"}' }], is_error: true) if query.to_s.strip.empty?

      store = server_context[:memory_store]
      results = store.search(query: query, scope: scope, project: project, limit: limit)
      MCP::Tool::Response.new([{ type: "text", text: JSON.pretty_generate(results) }])
    rescue => e
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate({ error: e.message }) }], is_error: true)
    end
  end
end

class StoreMemoryTool < MCP::Tool
  description "記憶を保存する（Claude Desktop からの手動保存用）"

  input_schema(
    properties: {
      content: { type: "string", description: "保存するテキスト" },
      source:  { type: "string", description: "claude_desktop | obsidian など" },
      project: { type: "string", description: "プロジェクト名（省略可）" },
      tags:    { type: "array", items: { type: "string" }, description: "タグ（省略可）" }
    },
    required: ["content", "source"]
  )

  class << self
    def call(content:, source:, project: nil, tags: nil, server_context:)
      store = server_context[:memory_store]
      id = store.store(content: content, source: source, project: project, tags: tags)
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate({ id: id, status: "stored" }) }])
    rescue => e
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate({ error: e.message }) }], is_error: true)
    end
  end
end

class ListMemoriesTool < MCP::Tool
  description "最近の記憶を一覧表示する"

  input_schema(
    properties: {
      scope:   { type: "string",  description: "source 絞り込み（省略可）" },
      project: { type: "string",  description: "プロジェクト絞り込み（省略可）" },
      limit:   { type: "integer", description: "最大件数（デフォルト 20）" }
    },
    required: []
  )

  class << self
    def call(scope: nil, project: nil, limit: 20, server_context:)
      store = server_context[:memory_store]
      results = store.list(scope: scope, project: project, limit: limit)
      MCP::Tool::Response.new([{ type: "text", text: JSON.pretty_generate(results) }])
    rescue => e
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate({ error: e.message }) }], is_error: true)
    end
  end
end

class DeleteMemoryTool < MCP::Tool
  description "指定 ID の記憶を削除する"

  input_schema(
    properties: {
      id: { type: "integer", description: "削除する記憶の ID" }
    },
    required: ["id"]
  )

  class << self
    def call(id:, server_context:)
      store = server_context[:memory_store]
      store.delete(id)
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate({ id: id, status: "deleted" }) }])
    rescue => e
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate({ error: e.message }) }], is_error: true)
    end
  end
end

class MemoryStatsTool < MCP::Tool
  description "記憶 DB の統計情報（総件数・source 別・最古/最新日時）を返す"

  input_schema(properties: {}, required: [])

  class << self
    def call(server_context:)
      store = server_context[:memory_store]
      stats = store.stats
      MCP::Tool::Response.new([{ type: "text", text: JSON.pretty_generate(stats) }])
    rescue => e
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate({ error: e.message }) }], is_error: true)
    end
  end
end

# エントリポイント（直接実行時のみ起動）
if __FILE__ == $0
  store = MemoryStore.new(DB_PATH)
  server = MCP::Server.new(
    name: "long-term-memory",
    version: "1.0.0",
    tools: [SearchMemoryTool, StoreMemoryTool, ListMemoriesTool, DeleteMemoryTool, MemoryStatsTool],
    server_context: { memory_store: store }
  )
  transport = MCP::Server::Transports::StdioTransport.new(server)
  transport.open
end
```

- [ ] **Step 4: テストが通ることを確認する**

```bash
bundle exec ruby test/test_mcp_server.rb
```

Expected: `7 tests, 9 assertions, 0 failures, 0 errors`

- [ ] **Step 5: コミットする**

```bash
git add scripts/mcp_server.rb test/test_mcp_server.rb
git commit -m "feat: add MCP server with 5 tools (search/store/list/delete/stats)"
```

---

## Task 9: Stop hook 形式の調査と capture_session.rb (TDD)

**Files:**
- Create: `scripts/capture_session.rb`
- Create: `test/test_capture_session.rb`
- Create: `.claude/settings.json` (probe 用)

- [ ] **Step 1: probe 用 settings.json を作成して Stop hook JSON を確認する**

```json
{
  "hooks": {
    "Stop": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "cat >> /tmp/hook_probe.json"
      }]
    }]
  }
}
```

このプロジェクトで Claude Code を使って会話し、セッション終了後に以下で確認：

```bash
cat /tmp/hook_probe.json
```

JSON の構造（`session_id`, `transcript`, `cwd` などのキー）を確認し、
以下の `capture_session.rb` の `parse_hook_input` メソッドに反映する。

- [ ] **Step 2: capture_session のテストを書く**

```ruby
# test/test_capture_session.rb
require_relative "test_helper"
require_relative "../scripts/capture_session"

class TestCaptureSession < Test::Unit::TestCase
  def setup
    @store = MemoryStore.new(":memory:", embedder: StubEmbedder.new)
  end

  def teardown
    @store.close
  end

  def test_parse_extracts_cwd
    input = JSON.generate({
      "session_id" => "abc123",
      "cwd" => "/home/user/myproject",
      "transcript" => []
    })
    result = CaptureSession.parse_hook_input(input)
    assert_equal "/home/user/myproject", result[:project]
  end

  def test_parse_builds_content_from_transcript
    input = JSON.generate({
      "session_id" => "abc123",
      "cwd" => "/home/user/myproject",
      "transcript" => [
        { "role" => "user", "content" => "Rubyのブロックを教えて" },
        { "role" => "assistant", "content" => "ブロックとはクロージャです" }
      ]
    })
    result = CaptureSession.parse_hook_input(input)
    assert result[:content].include?("Rubyのブロックを教えて")
    assert result[:content].include?("ブロックとはクロージャです")
  end

  def test_run_stores_to_memory_store
    input = JSON.generate({
      "session_id" => "abc123",
      "cwd" => "/home/user/myproject",
      "transcript" => [
        { "role" => "user", "content" => "テスト会話" },
        { "role" => "assistant", "content" => "テスト応答" }
      ]
    })
    CaptureSession.run(input, store: @store)
    count = @store.db.execute("SELECT COUNT(*) as c FROM memories").first["c"]
    assert_equal 1, count
  end

  def test_run_skips_empty_transcript
    input = JSON.generate({
      "session_id" => "abc123",
      "cwd" => "/home/user/myproject",
      "transcript" => []
    })
    CaptureSession.run(input, store: @store)
    count = @store.db.execute("SELECT COUNT(*) as c FROM memories").first["c"]
    assert_equal 0, count, "空の transcript は保存しない"
  end
end
```

- [ ] **Step 3: テストが失敗することを確認する**

```bash
bundle exec ruby test/test_capture_session.rb
```

Expected: `LoadError` または `NameError`

- [ ] **Step 4: capture_session.rb を実装する**

Step 1 で確認した JSON 構造に合わせて `parse_hook_input` を調整すること。

```ruby
# scripts/capture_session.rb
$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))
require "json"
require "memory_store"
require "embedder"

module CaptureSession
  DB_PATH = File.expand_path("../../db/memory.db", __FILE__).freeze

  def self.parse_hook_input(json_str)
    data = JSON.parse(json_str)
    cwd = data["cwd"] || ""
    project = File.basename(cwd)

    # transcript は配列。role/content 形式を想定
    # Step 1 の probe 結果に合わせてこのロジックを調整すること
    transcript = data["transcript"] || []
    lines = transcript.map do |msg|
      role = msg["role"] || msg["type"] || "unknown"
      content = msg["content"].is_a?(String) ? msg["content"] : msg["content"].to_s
      "[#{role}] #{content}"
    end
    content = lines.join("\n")

    { content: content, project: project, session_id: data["session_id"] }
  end

  def self.run(json_str, store: nil)
    parsed = parse_hook_input(json_str)
    return if parsed[:content].strip.empty?

    store ||= MemoryStore.new(DB_PATH)
    store.store(
      content: parsed[:content],
      source: "claude_code",
      project: parsed[:project],
      tags: ["session", parsed[:session_id]].compact
    )
  rescue => e
    warn "capture_session error: #{e.message}"
  end
end

if __FILE__ == $0
  input = $stdin.read
  CaptureSession.run(input)
end
```

- [ ] **Step 5: テストが通ることを確認する**

```bash
bundle exec ruby test/test_capture_session.rb
```

Expected: `4 tests, 5 assertions, 0 failures, 0 errors`

- [ ] **Step 6: コミットする**

```bash
git add scripts/capture_session.rb test/test_capture_session.rb
git commit -m "feat: add capture_session Stop hook handler"
```

---

## Task 10: ingest_directory.rb (TDD)

**Files:**
- Create: `scripts/ingest_directory.rb`
- Create: `test/test_ingest_directory.rb`

- [ ] **Step 1: テストを書く**

```ruby
# test/test_ingest_directory.rb
require_relative "test_helper"
require_relative "../scripts/ingest_directory"
require "tmpdir"

class TestIngestDirectory < Test::Unit::TestCase
  def setup
    @store = MemoryStore.new(":memory:", embedder: StubEmbedder.new)
    @tmpdir = Dir.mktmpdir
  end

  def teardown
    @store.close
    FileUtils.rm_rf(@tmpdir)
  end

  def test_ingests_markdown_files
    File.write(File.join(@tmpdir, "note.md"), "# Zettelkasten\nノート管理の手法")
    File.write(File.join(@tmpdir, "idea.txt"), "アイデアのメモ")
    IngestDirectory.run(directory: @tmpdir, source: "obsidian", store: @store)
    count = @store.db.execute("SELECT COUNT(*) as c FROM memories").first["c"]
    assert_equal 2, count
  end

  def test_skips_non_target_extensions
    File.write(File.join(@tmpdir, "image.png"), "binary")
    File.write(File.join(@tmpdir, "note.md"), "マークダウン")
    IngestDirectory.run(directory: @tmpdir, source: "obsidian", store: @store)
    count = @store.db.execute("SELECT COUNT(*) as c FROM memories").first["c"]
    assert_equal 1, count, ".png はスキップされること"
  end

  def test_recurses_into_subdirectories
    subdir = File.join(@tmpdir, "subdir")
    Dir.mkdir(subdir)
    File.write(File.join(subdir, "deep.md"), "深いノート")
    IngestDirectory.run(directory: @tmpdir, source: "obsidian", store: @store)
    count = @store.db.execute("SELECT COUNT(*) as c FROM memories").first["c"]
    assert_equal 1, count
  end

  def test_idempotent_second_run_does_not_duplicate
    File.write(File.join(@tmpdir, "note.md"), "同じ内容")
    IngestDirectory.run(directory: @tmpdir, source: "obsidian", store: @store)
    IngestDirectory.run(directory: @tmpdir, source: "obsidian", store: @store)
    count = @store.db.execute("SELECT COUNT(*) as c FROM memories").first["c"]
    assert_equal 1, count, "2回実行しても重複しない"
  end

  def test_sets_source_and_project
    File.write(File.join(@tmpdir, "note.md"), "プロジェクトテスト")
    IngestDirectory.run(directory: @tmpdir, source: "obsidian", project: "myvault", store: @store)
    row = @store.db.execute("SELECT source, project FROM memories").first
    assert_equal "obsidian", row["source"]
    assert_equal "myvault", row["project"]
  end
end
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
bundle exec ruby test/test_ingest_directory.rb
```

Expected: `LoadError` または `NameError`

- [ ] **Step 3: ingest_directory.rb を実装する**

```ruby
# scripts/ingest_directory.rb
$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))
require "memory_store"
require "embedder"
require "optparse"

module IngestDirectory
  DB_PATH = File.expand_path("../../db/memory.db", __FILE__).freeze
  DEFAULT_EXTENSIONS = %w[.md .txt .rb .yaml .yml].freeze

  def self.run(directory:, source:, project: nil, extensions: DEFAULT_EXTENSIONS, store: nil)
    store ||= MemoryStore.new(DB_PATH)
    files = Dir.glob(File.join(directory, "**", "*"))
              .select { |f| File.file?(f) && extensions.include?(File.extname(f).downcase) }

    files.each do |path|
      content = File.read(path, encoding: "utf-8")
      next if content.strip.empty?
      store.store(
        content: content,
        source: source,
        project: project || File.basename(directory),
        tags: [File.extname(path).delete(".")]
      )
      warn "ingested: #{path}"
    rescue => e
      warn "skip #{path}: #{e.message}"
    end
  end
end

if __FILE__ == $0
  options = { source: "obsidian", extensions: IngestDirectory::DEFAULT_EXTENSIONS }
  OptionParser.new do |opts|
    opts.banner = "Usage: ingest_directory.rb <directory> [options]"
    opts.on("--source SOURCE", "source 値（デフォルト: obsidian）") { |v| options[:source] = v }
    opts.on("--project PROJECT", "project 名") { |v| options[:project] = v }
    opts.on("--ext EXTS", "カンマ区切り拡張子（例: md,txt）") { |v| options[:extensions] = v.split(",").map { |e| e.start_with?(".") ? e : ".#{e}" } }
  end.parse!

  directory = ARGV.shift
  abort "Usage: ingest_directory.rb <directory> [--source SOURCE] [--project PROJECT]" unless directory
  abort "Directory not found: #{directory}" unless File.directory?(directory)

  IngestDirectory.run(directory: directory, **options)
end
```

- [ ] **Step 4: テストが通ることを確認する**

```bash
bundle exec ruby test/test_ingest_directory.rb
```

Expected: `5 tests, 6 assertions, 0 failures, 0 errors`

- [ ] **Step 5: コミットする**

```bash
git add scripts/ingest_directory.rb test/test_ingest_directory.rb
git commit -m "feat: add IngestDirectory bulk ingestion CLI with idempotency"
```

---

## Task 11: rebuild_embeddings.rb

テスト対象は主に MemoryStore と Embedder で既カバー済み。スモークテストのみ。

**Files:**
- Create: `scripts/rebuild_embeddings.rb`

- [ ] **Step 1: rebuild_embeddings.rb を作成する**

```ruby
# scripts/rebuild_embeddings.rb
$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))
require "memory_store"
require "embedder"

DB_PATH = File.expand_path("../../db/memory.db", __FILE__).freeze

store = MemoryStore.new(DB_PATH)
embedder = Embedder.new

rows = store.db.execute("SELECT id, content FROM memories ORDER BY id")
total = rows.size
warn "再ベクトル化対象: #{total} 件"

store.db.execute("DELETE FROM memories_vec")

rows.each_with_index do |row, i|
  embedding = embedder.embed(row["content"])
  blob = embedding.pack("f*")
  store.db.execute(
    "INSERT INTO memories_vec(memory_id, embedding) VALUES (?, ?)",
    [row["id"], blob]
  )
  warn "  [#{i + 1}/#{total}] id=#{row['id']}"
end

warn "完了"
```

- [ ] **Step 2: スモークテスト（DB が存在しない場合に graceful に終了することを確認）**

```bash
bundle exec ruby scripts/rebuild_embeddings.rb 2>&1 | head -5
```

Expected: DB が存在しない場合は `SQLite3::Exception` または `0 件` で終了する（クラッシュしない）

- [ ] **Step 3: コミットする**

```bash
git add scripts/rebuild_embeddings.rb
git commit -m "feat: add rebuild_embeddings script for model migration"
```

---

## Task 12: Claude Code 統合

**Files:**
- Create/Modify: `.claude/settings.json`
- Create: `.claude/skills/memory-maintenance.md`

- [ ] **Step 1: .claude/settings.json を作成する**

```json
{
  "hooks": {
    "Stop": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "bundle exec ruby /Users/bash/dev/src/github.com/bash0C7/long-term-memory/scripts/capture_session.rb"
      }]
    }]
  },
  "mcpServers": {
    "long-term-memory": {
      "command": "bundle",
      "args": ["exec", "ruby", "scripts/mcp_server.rb"],
      "cwd": "/Users/bash/dev/src/github.com/bash0C7/long-term-memory"
    }
  }
}
```

- [ ] **Step 2: memory-maintenance スキルを作成する**

```markdown
<!-- .claude/skills/memory-maintenance.md -->
---
name: memory-maintenance
description: 長期記憶 DB のメンテナンスを行う。list/delete/stats/ingest/rebuild を扱う。
---

# Memory Maintenance

長期記憶 DB (`db/memory.db`) のメンテナンスを行う。

## できること

- **一覧・検索**: `list_memories` ツールで最近の記憶を確認
- **削除**: `delete_memory(id)` で不要な記憶を削除
- **統計**: `memory_stats` で DB の状態を確認
- **一括取り込み**: `ingest_directory.rb` でディレクトリを取り込む
- **再ベクトル化**: `rebuild_embeddings.rb` でモデル変更後に再生成

## 使い方

### DB 統計を確認
MCP ツール `memory_stats` を呼ぶ。

### 特定 source の記憶を一覧
MCP ツール `list_memories` を `scope: "obsidian"` 等で呼ぶ。

### ディレクトリを取り込む
```bash
! bundle exec ruby scripts/ingest_directory.rb <path> --source obsidian --project <name>
```

### 不要な記憶を削除
`list_memories` で ID を確認し、`delete_memory(id)` を呼ぶ。

### 埋め込みを再生成（モデル変更後）
```bash
! bundle exec ruby scripts/rebuild_embeddings.rb
```
```

- [ ] **Step 3: 全テストが通ることを確認する**

```bash
bundle exec ruby -e "Dir['test/test_*.rb'].each { |f| require_relative f }"
```

Expected: 全テストが 0 failures, 0 errors

- [ ] **Step 4: コミットする**

```bash
git add .claude/settings.json .claude/skills/memory-maintenance.md
git commit -m "feat: add Claude Code integration (Stop hook + MCP server + maintenance skill)"
```

---

## Task 13: 全体スモークテスト

- [ ] **Step 1: DB ディレクトリを作成する**

```bash
mkdir -p db
```

- [ ] **Step 2: MCP サーバーが起動することを確認する**

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | bundle exec ruby scripts/mcp_server.rb
```

Expected: `search_memory`, `store_memory`, `list_memories`, `delete_memory`, `memory_stats` の 5 ツールが JSON で返ってくる

- [ ] **Step 3: ingest_directory.rb のスモークテスト**

```bash
bundle exec ruby scripts/ingest_directory.rb docs --source test_ingest --project smoke_test 2>&1
```

Expected: `ingested: docs/...` が出力され、エラーなく完了する

- [ ] **Step 4: capture_session.rb のスモークテスト**

```bash
echo '{"session_id":"test","cwd":"/tmp","transcript":[{"role":"user","content":"スモークテスト"},{"role":"assistant","content":"OK"}]}' | bundle exec ruby scripts/capture_session.rb
```

Expected: エラーなく完了する

- [ ] **Step 5: 最終コミット**

```bash
git add -A
git commit -m "chore: smoke test complete - long-term memory system ready"
```
