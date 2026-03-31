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
