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
    assert_nothing_raised { @store.db.execute("SELECT memory_id FROM memories_vec LIMIT 1") }
  end
end

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
    assert_instance_of Integer, id2, "冪等パスでも Integer が返ること"
    count = @store.db.execute("SELECT COUNT(*) as c FROM memories").first["c"]
    assert_equal 1, count
  end

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
end

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
