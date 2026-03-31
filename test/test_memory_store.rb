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
    count = @store.db.execute("SELECT COUNT(*) as c FROM memories").first["c"]
    assert_equal 1, count
  end
end
