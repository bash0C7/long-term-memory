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
    results = @store.search(query: "Obsidian", scope: "obsidian")
    assert results.size > 0, "obsidian scope で結果が1件以上返ること"
    assert results.all? { |r| r["source"] == "obsidian" }, "scope フィルタが機能すること"
  end

  def test_search_project_filters
    results = @store.search(query: "Ruby", project: "myapp")
    assert results.all? { |r| r["project"] == "myapp" || r["project"].nil? }
    assert results.any? { |r| r["project"] == "myapp" }
  end

  def test_search_respects_limit
    @store.store(content: "SQLiteのWALモードについて", source: "claude_code")
    # now 2 records match "SQLite" — verify limit caps results
    unlimited = @store.search(query: "SQLite", limit: 10)
    assert unlimited.size >= 2, "limit なしなら2件以上ヒットすること"
    limited = @store.search(query: "SQLite", limit: 1)
    assert_equal 1, limited.size
  end

  def test_search_scores_are_positive
    results = @store.search(query: "Ruby")
    assert results.all? { |r| r["score"] > 0 }, "スコアは正の値"
  end
end
