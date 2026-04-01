# long-term-memory ブラッシュアップ Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** MCPツールに summary/keywords を追加してレスポンスサイズを削減し、ツール名を `long_term_memory_` プレフィックスに統一して、全文取得ツールを追加する。

**Architecture:** `KeywordExtractor` モジュールが summary/keywords 生成を担当し `MemoryStore#store` が保存時に自動呼び出す。ベクトルは `summary + keywords` テキストで生成して意味検索精度を向上させ、FTS5 は全文のまま維持してハイブリッド検索の差別化を保つ。MCP ツールの Ruby クラス名を CamelCase リネームし mcp gem の自動変換で `long_term_memory_*` ツール名を生成する（`StringUtils.handle_from_class_name` が snake_case 変換する）。

**Tech Stack:** Ruby 4.0.1, SQLite3, sqlite-vec (FTS5 trigram + vec0 768次元), mcp gem 0.10.0, test-unit

---

## ファイル構成

| ファイル | 変更種別 | 責務 |
|---|---|---|
| `lib/keyword_extractor.rb` | 新規作成 | summary(先頭200文字)・keywords(TF上位6語)生成 |
| `lib/memory_store.rb` | 変更 | スキーマにsummary/keywords追加、store/search/list/get変更 |
| `scripts/mcp_server.rb` | 変更 | ツール名リネーム・LongTermMemoryGet追加 |
| `scripts/migrate_add_summary_keywords.rb` | 新規作成 | 既存レコードへのsummary/keywords付与（一回限り手動実行） |
| `.claude/skills/long-term-memory-migrate.md` | 新規作成 | マイグレーション手順skill |
| `test/test_keyword_extractor.rb` | 新規作成 | KeywordExtractor単体テスト |
| `test/test_memory_store.rb` | 変更 | summary/keywords検証・get検証追加 |
| `test/test_mcp_server.rb` | 変更 | ツール名変更に追従・Getツールテスト追加 |

---

### Task 1: KeywordExtractor モジュール

**Files:**
- Create: `lib/keyword_extractor.rb`
- Create: `test/test_keyword_extractor.rb`

- [ ] **Step 1: テストファイルを作成（Red）**

```ruby
# test/test_keyword_extractor.rb
require_relative "test_helper"
require_relative "../lib/keyword_extractor"

class TestKeywordExtractor < Test::Unit::TestCase
  def test_extract_returns_array_of_strings
    keywords = KeywordExtractor.extract("Ruby programming language")
    assert_instance_of Array, keywords
    assert keywords.all? { |k| k.is_a?(String) }
  end

  def test_extract_returns_at_most_6_keywords
    text = "Ruby blocks procs lambdas closures iterators methods objects classes modules inheritance"
    keywords = KeywordExtractor.extract(text)
    assert keywords.length <= 6
  end

  def test_extract_english_keywords_present
    text = "Ruby blocks and procs and lambdas are important in Ruby programming"
    keywords = KeywordExtractor.extract(text)
    assert keywords.include?("Ruby") || keywords.include?("ruby")
  end

  def test_extract_filters_english_stop_words
    text = "the a an is are was were be been for in on at to of and or but not"
    keywords = KeywordExtractor.extract(text)
    stop = %w[the a an is are was were be been for in on at to of and or but not]
    assert keywords.none? { |k| stop.include?(k.downcase) }
  end

  def test_extract_japanese_keywords
    text = "RubyのブロックはProcとlambdaの違いを理解することが重要です"
    keywords = KeywordExtractor.extract(text)
    assert keywords.length >= 1
    has_cjk = keywords.any? { |k| k.match?(/[ぁ-んァ-ヶ一-龥]/) }
    has_ascii = keywords.any? { |k| k.match?(/Ruby|Proc|lambda/i) }
    assert has_cjk || has_ascii
  end

  def test_extract_removes_urls
    text = "Check https://example.com/path for more Ruby information about blocks and procs"
    keywords = KeywordExtractor.extract(text)
    assert keywords.none? { |k| k.include?("http") }
    assert keywords.none? { |k| k.include?("example.com") }
  end

  def test_summarize_returns_full_text_when_short
    text = "short text"
    assert_equal "short text", KeywordExtractor.summarize(text)
  end

  def test_summarize_truncates_at_200_chars
    text = "a" * 300
    assert_equal 200, KeywordExtractor.summarize(text).length
  end

  def test_summarize_exactly_200_chars
    text = "b" * 200
    assert_equal text, KeywordExtractor.summarize(text)
  end

  def test_extract_empty_text_returns_empty_array
    assert_equal [], KeywordExtractor.extract("")
  end
end
```

- [ ] **Step 2: テストを実行して失敗を確認**

```bash
bundle exec ruby -Itest test/test_keyword_extractor.rb
```

期待: `NameError: uninitialized constant KeywordExtractor`

- [ ] **Step 3: KeywordExtractor を実装**

```ruby
# lib/keyword_extractor.rb
module KeywordExtractor
  SUMMARY_LENGTH = 200
  MAX_KEYWORDS   = 6

  ENGLISH_STOP_WORDS = %w[
    a an the is are was were be been being have has had do does did
    will would could should may might shall can for in on at to of
    and or but not with from by about as into through during
    this that these those it its we they he she you i me my
    what which who whom where when why how all each every more most
    other some such no nor so yet both either neither once here there
  ].freeze

  JAPANESE_STOP_WORDS = %w[
    する こと もの ため なる ある いる れる られ てい につ いて
    とし てに より おい にお けるに また さら ただ なお
    です ます した ない して いう から まで よる よう
  ].freeze

  def self.summarize(text)
    text.to_s[0, SUMMARY_LENGTH] || ""
  end

  def self.extract(text)
    cleaned = clean(text.to_s)
    tokens  = tokenize(cleaned)
    filtered = filter(tokens)
    score(filtered).first(MAX_KEYWORDS)
  end

  def self.clean(text)
    text
      .gsub(%r{https?://\S+}, " ")
      .gsub(/[「」『』【】〔〕（）\(\)\[\]\{\}<>]/, " ")
      .gsub(/[、。，．！？!?\r\n]/, " ")
      .gsub(/\s+/, " ")
      .strip
  end

  def self.tokenize(text)
    tokens = []
    text.scan(/[a-zA-Z][a-zA-Z0-9_]*/).each do |word|
      tokens << word if word.length >= 2
    end
    text.scan(/[ぁ-んァ-ヶ一-龥]+/).each do |run|
      run.chars.each_cons(2) { |a, b| tokens << (a + b) }
    end
    tokens
  end

  def self.filter(tokens)
    stop = (ENGLISH_STOP_WORDS + JAPANESE_STOP_WORDS).map(&:downcase).to_set
    tokens.reject { |t| stop.include?(t.downcase) }
          .reject { |t| t.length < 2 }
  end

  def self.score(tokens)
    freq     = Hash.new(0)
    case_map = {}
    tokens.each do |t|
      key = t.downcase
      freq[key] += 1
      case_map[key] ||= t
    end
    freq.sort_by { |_, count| -count }.map { |key, _| case_map[key] }
  end

  private_class_method :clean, :tokenize, :filter, :score
end
```

- [ ] **Step 4: テストを実行して全て通ることを確認**

```bash
bundle exec ruby -Itest test/test_keyword_extractor.rb
```

期待: 全テスト PASS

- [ ] **Step 5: コミット**

```bash
git add lib/keyword_extractor.rb test/test_keyword_extractor.rb
git commit -m "feat: add KeywordExtractor module for summary and keyword extraction"
```

---

### Task 2: MemoryStore スキーマ + store 変更

**Files:**
- Modify: `lib/memory_store.rb`
- Modify: `test/test_memory_store.rb`

- [ ] **Step 1: テストを追加（Red）**

`test/test_memory_store.rb` の既存のどこかのクラス（`TestMemoryStoreBasicOperations` 等）に以下を追加:

```ruby
def test_store_generates_summary
  long_content = "RubyのブロックはProcとlambdaの違いを理解することが重要です。" * 5
  id = @store.store(content: long_content, source: "test")
  row = @store.db.execute("SELECT summary FROM memories WHERE id = ?", [id]).first
  assert_not_nil row["summary"]
  assert row["summary"].length <= 200
end

def test_store_generates_keywords
  id = @store.store(content: "Ruby blocks procs lambdas closures programming language", source: "test")
  row = @store.db.execute("SELECT keywords FROM memories WHERE id = ?", [id]).first
  assert_not_nil row["keywords"]
  keywords = JSON.parse(row["keywords"])
  assert_instance_of Array, keywords
  assert keywords.length >= 1
end
```

- [ ] **Step 2: テストを実行して失敗を確認**

```bash
bundle exec ruby -Itest test/test_memory_store.rb
```

期待: `SQLite3::Exception: table memories has no column named summary` 等

- [ ] **Step 3: memory_store.rb を変更**

先頭の `require` に追加（`require "time"` の後）:

```ruby
require_relative "keyword_extractor"
```

`create_schema` の `CREATE TABLE` を変更（`created_at TEXT NOT NULL` の後に2行追加）:

```ruby
    @db.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS memories (
        id           INTEGER PRIMARY KEY,
        content      TEXT    NOT NULL,
        source       TEXT    NOT NULL,
        project      TEXT,
        tags         TEXT,
        content_hash TEXT,
        created_at   TEXT    NOT NULL,
        summary      TEXT,
        keywords     TEXT
      )
    SQL
```

`store` メソッドを以下に置き換え（`content_hash` 生成の後に summary/keywords 生成、INSERT と embed_text を変更）:

```ruby
  def store(content:, source:, project: nil, tags: nil)
    content_hash = Digest::SHA256.hexdigest(content)

    existing = @db.execute(
      "SELECT id FROM memories WHERE content_hash = ?", [content_hash]
    ).first
    return existing["id"] if existing

    summary      = KeywordExtractor.summarize(content)
    keywords     = KeywordExtractor.extract(content)
    keywords_json = JSON.generate(keywords)
    tags_json    = tags ? JSON.generate(tags) : nil
    created_at   = Time.now.iso8601

    @db.execute(
      "INSERT INTO memories (content, source, project, tags, content_hash, created_at, summary, keywords) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
      [content, source, project, tags_json, content_hash, created_at, summary, keywords_json]
    )
    id = @db.last_insert_row_id

    embed_text     = "#{summary} #{keywords.join(' ')}"
    embedding      = @embedder.embed(embed_text)
    embedding_blob = embedding.pack("f*")
    @db.execute(
      "INSERT INTO memories_vec(memory_id, embedding) VALUES (?, ?)",
      [id, embedding_blob]
    )

    id
  end
```

- [ ] **Step 4: テストを実行して通ることを確認**

```bash
bundle exec ruby -Itest test/test_memory_store.rb
```

期待: 全テスト PASS

- [ ] **Step 5: コミット**

```bash
git add lib/memory_store.rb test/test_memory_store.rb
git commit -m "feat: add summary/keywords columns to memories, generate on store"
```

---

### Task 3: MemoryStore search / list / get 変更

**Files:**
- Modify: `lib/memory_store.rb`
- Modify: `test/test_memory_store.rb`

- [ ] **Step 1: テストを追加（Red）**

`test/test_memory_store.rb` に新しいテストクラスを追加:

```ruby
class TestMemoryStoreResponseFormat < Test::Unit::TestCase
  def setup
    @store = MemoryStore.new(":memory:", embedder: StubEmbedder.new)
    @store.store(content: "Ruby programming with blocks and lambdas closures", source: "claude_code", project: "proj1")
  end

  def teardown
    @store.close
  end

  def test_search_does_not_return_content
    results = @store.search(query: "Ruby")
    assert_instance_of Array, results
    results.each do |r|
      assert_false r.key?("content"), "search result must not include content key"
    end
  end

  def test_search_returns_summary_and_keywords
    results = @store.search(query: "Ruby")
    results.each do |r|
      assert r.key?("summary"), "search result must include summary"
      assert r.key?("keywords"), "search result must include keywords"
      assert_instance_of Array, r["keywords"]
    end
  end

  def test_list_does_not_return_content
    results = @store.list
    results.each do |r|
      assert_false r.key?("content"), "list result must not include content key"
    end
  end

  def test_list_returns_summary_and_keywords
    results = @store.list
    results.each do |r|
      assert r.key?("summary")
      assert r.key?("keywords")
      assert_instance_of Array, r["keywords"]
    end
  end

  def test_get_returns_full_content
    id = @store.store(content: "full content text for get test", source: "test")
    result = @store.get(id)
    assert_not_nil result
    assert_equal "full content text for get test", result["content"]
  end

  def test_get_returns_summary_and_keywords
    id = @store.store(content: "Ruby programming blocks closures", source: "test")
    result = @store.get(id)
    assert result.key?("summary")
    assert result.key?("keywords")
    assert_instance_of Array, result["keywords"]
  end

  def test_get_returns_nil_for_missing_id
    result = @store.get(99999)
    assert_nil result
  end
end
```

- [ ] **Step 2: テストを実行して失敗を確認**

```bash
bundle exec ruby -Itest test/test_memory_store.rb
```

期待: `NoMethodError: undefined method 'get'` 等

- [ ] **Step 3: search メソッドを置き換え**

`lib/memory_store.rb` の `search` メソッド全体を以下に置き換え:

```ruby
  def search(query:, scope: nil, project: nil, limit: 5)
    conditions = []
    condition_params = []
    if scope
      conditions << "m.source = ?"
      condition_params << scope
    end
    if project
      conditions << "m.project = ?"
      condition_params << project
    end
    where_clause = conditions.empty? ? "" : "AND #{conditions.join(' AND ')}"

    fts_ids = begin
      @db.execute(<<~SQL, [query] + condition_params + [limit * 2])
        SELECT m.id
        FROM memories m
        JOIN memories_fts ON memories_fts.rowid = m.id
        WHERE memories_fts MATCH ? #{where_clause}
        ORDER BY rank
        LIMIT ?
      SQL
    rescue SQLite3::Exception
      []
    end

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
          condition_params + [query_blob, limit * 2]
        )
      end
    rescue SQLite3::Exception
      []
    end

    k = 60
    scores = Hash.new(0.0)

    fts_ids.each_with_index do |row, rank|
      id = row["id"] || row[0]
      scores[id] += 1.0 / (k + rank + 1)
    end

    vec_rows.each_with_index do |row, rank|
      id = row["memory_id"] || row[0]
      scores[id] += 1.0 / (k + rank + 1)
    end

    return [] if scores.empty?

    all_ids      = scores.keys
    placeholders = all_ids.map { "?" }.join(",")
    meta_rows    = @db.execute(
      "SELECT id, summary, keywords, source, project, created_at FROM memories WHERE id IN (#{placeholders})",
      all_ids
    )
    meta_by_id = meta_rows.each_with_object({}) { |r, h| h[r["id"]] = r }

    scored = scores.map do |id, rrf|
      row = meta_by_id[id]
      next unless row
      age_days = (Time.now - Time.parse(row["created_at"])).abs / 86400.0
      decay    = 0.5 ** (age_days / 30.0)
      row.merge("score" => rrf * decay)
    end.compact

    scored.sort_by { |r| -r["score"] }.first(limit).map do |r|
      kw = begin
        r["keywords"] ? JSON.parse(r["keywords"]) : []
      rescue JSON::ParserError
        []
      end
      {
        "id"         => r["id"],
        "score"      => r["score"],
        "summary"    => r["summary"],
        "keywords"   => kw,
        "source"     => r["source"],
        "project"    => r["project"],
        "created_at" => r["created_at"]
      }
    end
  end
```

- [ ] **Step 4: list メソッドを置き換え**

`lib/memory_store.rb` の `list` メソッド全体を以下に置き換え:

```ruby
  def list(scope: nil, project: nil, limit: 20)
    conditions = []
    params = []
    if scope
      conditions << "source = ?"
      params << scope
    end
    if project
      conditions << "project = ?"
      params << project
    end
    where = conditions.empty? ? "" : "WHERE #{conditions.join(' AND ')}"
    params << limit
    @db.execute(
      "SELECT id, summary, keywords, source, project, created_at FROM memories #{where} ORDER BY created_at DESC LIMIT ?",
      params
    ).map do |r|
      kw = begin
        r["keywords"] ? JSON.parse(r["keywords"]) : []
      rescue JSON::ParserError
        []
      end
      r.merge("keywords" => kw)
    end
  end
```

- [ ] **Step 5: get メソッドを追加**

`delete` メソッドの直後（`def stats` の前）に追加:

```ruby
  def get(id)
    row = @db.execute(
      "SELECT id, content, summary, keywords, source, project, tags, created_at FROM memories WHERE id = ?",
      [id]
    ).first
    return nil unless row
    kw = begin
      row["keywords"] ? JSON.parse(row["keywords"]) : []
    rescue JSON::ParserError
      []
    end
    row.merge("keywords" => kw)
  end
```

- [ ] **Step 6: テストを実行して通ることを確認**

```bash
bundle exec ruby -Itest test/test_memory_store.rb
```

期待: 全テスト PASS

- [ ] **Step 7: コミット**

```bash
git add lib/memory_store.rb test/test_memory_store.rb
git commit -m "feat: search/list return summary+keywords only, add get method for full content"
```

---

### Task 4: MCP サーバー ツール名変更 + Get ツール追加

**Files:**
- Modify: `scripts/mcp_server.rb`
- Modify: `test/test_mcp_server.rb`

- [ ] **Step 1: テストファイルを更新（Red）**

`test/test_mcp_server.rb` を以下に完全置き換え:

```ruby
require_relative "test_helper"
require_relative "../scripts/mcp_server"

class TestLongTermMemorySearch < Test::Unit::TestCase
  def setup
    @store = MemoryStore.new(":memory:", embedder: StubEmbedder.new)
    @store.store(content: "Rubyのブロックとプロック", source: "claude_code", tags: ["ruby"])
    @store.store(content: "ObsidianのPKM戦略", source: "obsidian")
  end

  def teardown
    @store.close
  end

  def test_search_returns_response
    response = LongTermMemorySearch.call(
      query: "Ruby",
      server_context: { memory_store: @store }
    )
    assert_instance_of MCP::Tool::Response, response
  end

  def test_search_result_has_summary_not_content
    response = LongTermMemorySearch.call(
      query: "Ruby",
      server_context: { memory_store: @store }
    )
    results = JSON.parse(response.content.first[:text])
    assert_instance_of Array, results
    results.each do |r|
      assert r.key?("summary"), "result must have summary"
      assert_false r.key?("content"), "result must not have content"
    end
  end

  def test_search_empty_query_returns_error
    response = LongTermMemorySearch.call(
      query: "",
      server_context: { memory_store: @store }
    )
    assert response.content.first[:text].include?("error") || response.error?
  end

  def test_tool_name_has_prefix
    assert_equal "long_term_memory_search", LongTermMemorySearch.tool_name
  end
end

class TestLongTermMemoryStore < Test::Unit::TestCase
  def setup
    @store = MemoryStore.new(":memory:", embedder: StubEmbedder.new)
  end

  def teardown
    @store.close
  end

  def test_store_saves_record
    response = LongTermMemoryStore.call(
      content: "新しい記憶",
      source: "claude_desktop",
      server_context: { memory_store: @store }
    )
    assert_instance_of MCP::Tool::Response, response
    count = @store.db.execute("SELECT COUNT(*) as c FROM memories").first["c"]
    assert_equal 1, count
  end

  def test_tool_name_has_prefix
    assert_equal "long_term_memory_store", LongTermMemoryStore.tool_name
  end
end

class TestLongTermMemoryGet < Test::Unit::TestCase
  def setup
    @store = MemoryStore.new(":memory:", embedder: StubEmbedder.new)
    @id = @store.store(content: "全文テスト用コンテンツ。Ruby programming blocks.", source: "claude_code")
  end

  def teardown
    @store.close
  end

  def test_get_returns_full_content
    response = LongTermMemoryGet.call(
      id: @id,
      server_context: { memory_store: @store }
    )
    assert_false response.error?
    result = JSON.parse(response.content.first[:text])
    assert_equal "全文テスト用コンテンツ。Ruby programming blocks.", result["content"]
  end

  def test_get_unknown_id_returns_error
    response = LongTermMemoryGet.call(
      id: 99999,
      server_context: { memory_store: @store }
    )
    assert response.error?
  end

  def test_tool_name_has_prefix
    assert_equal "long_term_memory_get", LongTermMemoryGet.tool_name
  end
end

class TestLongTermMemoryStats < Test::Unit::TestCase
  def setup
    @store = MemoryStore.new(":memory:", embedder: StubEmbedder.new)
    @store.store(content: "統計テスト", source: "claude_code")
  end

  def teardown
    @store.close
  end

  def test_stats_returns_counts
    response = LongTermMemoryStats.call(server_context: { memory_store: @store })
    text = response.content.first[:text]
    assert text.include?("1"), "総件数 1 が含まれること"
  end

  def test_tool_name_has_prefix
    assert_equal "long_term_memory_stats", LongTermMemoryStats.tool_name
  end
end
```

- [ ] **Step 2: テストを実行して失敗を確認**

```bash
bundle exec ruby -Itest test/test_mcp_server.rb
```

期待: `NameError: uninitialized constant LongTermMemorySearch`

- [ ] **Step 3: mcp_server.rb を完全置き換え**

```ruby
$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))
require "mcp"
require "json"
require "memory_store"
require "embedder"

DB_PATH = File.expand_path("../../db/memory.db", __FILE__).freeze

class LongTermMemorySearch < MCP::Tool
  description <<~DESC
    【長期記憶】ハイブリッド検索（FTS5全文一致 + ベクトル意味検索 + RRF融合）で長期記憶を照会する。
    query に scope ワード（"obsidian", "claude_code" など）やプロジェクト名を含めると絞り込みが効く。
    結果は summary と keywords を返す。全文が必要な場合は long_term_memory_get を使う。
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
      return MCP::Tool::Response.new([{ type: "text", text: '{"error":"query is required"}' }], error: true) if query.to_s.strip.empty?

      store   = server_context[:memory_store]
      results = store.search(query: query, scope: scope, project: project, limit: limit)
      MCP::Tool::Response.new([{ type: "text", text: JSON.pretty_generate(results) }])
    rescue => e
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate({ error: e.message }) }], error: true)
    end
  end
end

class LongTermMemoryStore < MCP::Tool
  description "【長期記憶】記憶を保存する（Claude Desktop からの手動保存用）。summary と keywords を自動生成する。"

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
      id    = store.store(content: content, source: source, project: project, tags: tags)
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate({ id: id, status: "stored" }) }])
    rescue => e
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate({ error: e.message }) }], error: true)
    end
  end
end

class LongTermMemoryList < MCP::Tool
  description "【長期記憶】最近の記憶を一覧表示する。summary と keywords を返す。"

  input_schema(
    properties: {
      scope:   { type: "string",  description: "source 絞り込み（省略可）" },
      project: { type: "string",  description: "プロジェクト絞り込み（省略可）" },
      limit:   { type: "integer", description: "最大件数（デフォルト 20）" }
    }
  )

  class << self
    def call(scope: nil, project: nil, limit: 20, server_context:)
      store   = server_context[:memory_store]
      results = store.list(scope: scope, project: project, limit: limit)
      MCP::Tool::Response.new([{ type: "text", text: JSON.pretty_generate(results) }])
    rescue => e
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate({ error: e.message }) }], error: true)
    end
  end
end

class LongTermMemoryGet < MCP::Tool
  description "【長期記憶】指定 ID の記憶を全文で取得する。search/list で見つけた ID を使い全文が必要な場合に使う。"

  input_schema(
    properties: {
      id: { type: "integer", description: "取得する記憶の ID" }
    },
    required: ["id"]
  )

  class << self
    def call(id:, server_context:)
      store  = server_context[:memory_store]
      result = store.get(id)
      if result.nil?
        return MCP::Tool::Response.new([{ type: "text", text: JSON.generate({ error: "not found: id=#{id}" }) }], error: true)
      end
      MCP::Tool::Response.new([{ type: "text", text: JSON.pretty_generate(result) }])
    rescue => e
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate({ error: e.message }) }], error: true)
    end
  end
end

class LongTermMemoryDelete < MCP::Tool
  description "【長期記憶】指定 ID の記憶を削除する"

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
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate({ error: e.message }) }], error: true)
    end
  end
end

class LongTermMemoryStats < MCP::Tool
  description "【長期記憶】記憶 DB の統計情報（総件数・source 別・最古/最新日時）を返す"

  input_schema(properties: {})

  class << self
    def call(server_context:)
      store = server_context[:memory_store]
      stats = store.stats
      MCP::Tool::Response.new([{ type: "text", text: JSON.pretty_generate(stats) }])
    rescue => e
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate({ error: e.message }) }], error: true)
    end
  end
end

if __FILE__ == $0
  store  = MemoryStore.new(DB_PATH)
  server = MCP::Server.new(
    name: "long-term-memory",
    version: "1.0.0",
    tools: [
      LongTermMemorySearch,
      LongTermMemoryStore,
      LongTermMemoryList,
      LongTermMemoryGet,
      LongTermMemoryDelete,
      LongTermMemoryStats
    ],
    server_context: { memory_store: store }
  )
  transport = MCP::Server::Transports::StdioTransport.new(server)
  transport.open
end
```

- [ ] **Step 4: テストを実行して通ることを確認**

```bash
bundle exec ruby -Itest test/test_mcp_server.rb
```

期待: 全テスト PASS

- [ ] **Step 5: 全テストを実行して既存テストが壊れていないことを確認**

```bash
bundle exec ruby -Itest test/test_keyword_extractor.rb test/test_memory_store.rb test/test_mcp_server.rb test/test_capture_session.rb test/test_ingest_directory.rb test/test_rebuild_embeddings.rb test/test_search.rb
```

期待: 全テスト PASS

- [ ] **Step 6: コミット**

```bash
git add scripts/mcp_server.rb test/test_mcp_server.rb
git commit -m "feat: rename MCP tools to long_term_memory_* prefix, add long_term_memory_get tool"
```

---

### Task 5: マイグレーションスクリプト

**Files:**
- Create: `scripts/migrate_add_summary_keywords.rb`

- [ ] **Step 1: スクリプトを作成**

```ruby
# scripts/migrate_add_summary_keywords.rb
# 既存DBに summary/keywords カラムを追加し全レコードを処理する。一度だけ手動実行。
$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))
require "sqlite3"
require "sqlite_vec"
require "json"
require "keyword_extractor"
require "embedder"

DB_PATH = File.expand_path("../../db/memory.db", __FILE__).freeze

unless File.exist?(DB_PATH)
  puts "DB not found: #{DB_PATH}"
  exit 1
end

db = SQLite3::Database.new(DB_PATH)
db.results_as_hash = true
db.enable_load_extension(true)
SqliteVec.load(db)
db.enable_load_extension(false)

%w[summary keywords].each do |col|
  begin
    db.execute("ALTER TABLE memories ADD COLUMN #{col} TEXT")
    puts "Added column: #{col}"
  rescue SQLite3::Exception => e
    puts "Column '#{col}' already exists (#{e.message})"
  end
end

total = db.execute("SELECT COUNT(*) as c FROM memories").first["c"]
puts "Processing #{total} records..."

embedder  = Embedder.new
processed = 0
offset    = 0
batch_size = 100

while offset < total
  rows = db.execute("SELECT id, content FROM memories LIMIT ? OFFSET ?", [batch_size, offset])
  break if rows.empty?

  rows.each do |row|
    id      = row["id"]
    content = row["content"]

    summary       = KeywordExtractor.summarize(content)
    keywords      = KeywordExtractor.extract(content)
    keywords_json = JSON.generate(keywords)

    db.execute("UPDATE memories SET summary = ?, keywords = ? WHERE id = ?", [summary, keywords_json, id])

    embed_text     = "#{summary} #{keywords.join(' ')}"
    embedding      = embedder.embed(embed_text)
    embedding_blob = embedding.pack("f*")
    db.execute("DELETE FROM memories_vec WHERE memory_id = ?", [id])
    db.execute("INSERT INTO memories_vec(memory_id, embedding) VALUES (?, ?)", [id, embedding_blob])

    processed += 1
    print "." if (processed % 10).zero?
  end

  offset += batch_size
end

puts "\nDone! Processed #{processed} / #{total} records."
```

- [ ] **Step 2: 構文確認**

```bash
bundle exec ruby -c scripts/migrate_add_summary_keywords.rb
```

期待: `Syntax OK`

- [ ] **Step 3: コミット**

```bash
git add scripts/migrate_add_summary_keywords.rb
git commit -m "feat: add migration script for summary/keywords columns and embedding rebuild"
```

---

### Task 6: メンテナンス skill 追加

**Files:**
- Create: `.claude/skills/long-term-memory-migrate.md`

- [ ] **Step 1: skill ファイルを作成**

ファイルパス: `.claude/skills/long-term-memory-migrate.md`

内容:
```
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
```

- [ ] **Step 2: コミット**

```bash
git add .claude/skills/long-term-memory-migrate.md
git commit -m "feat: add long-term-memory-migrate maintenance skill"
```

---

### Task 7: 全テスト実行 + マイグレーション実行

- [ ] **Step 1: 全テストスイートを実行**

```bash
bundle exec ruby -Itest test/test_keyword_extractor.rb test/test_memory_store.rb test/test_mcp_server.rb test/test_capture_session.rb test/test_ingest_directory.rb test/test_rebuild_embeddings.rb test/test_search.rb
```

期待: 全テスト PASS（`test_embedder.rb` は実モデルロードのため除外）

- [ ] **Step 2: DBが存在する場合はバックアップ後マイグレーション実行**

```bash
ls db/memory.db && cp db/memory.db "db/memory.db.bak.$(date +%Y%m%d_%H%M%S)" && bundle exec ruby scripts/migrate_add_summary_keywords.rb
```

- [ ] **Step 3: マイグレーション後の動作確認**

```bash
bundle exec ruby -e "
\$LOAD_PATH.unshift('lib')
require 'memory_store'
class StubEmbedder
  VECTOR_SIZE = 768
  def embed(t); [0.0] * 768; end
end
store = MemoryStore.new('db/memory.db', embedder: StubEmbedder.new)
puts store.stats.inspect
results = store.list(limit: 2)
require 'json'
puts JSON.pretty_generate(results)
"
```

期待: `summary` と `keywords` が含まれる結果が表示される

- [ ] **Step 4: 最終コミット（未コミットの変更があれば）**

```bash
git status
git add -p
git commit -m "chore: complete long-term-memory brushup - summary/keywords, tool rename, get tool"
```
