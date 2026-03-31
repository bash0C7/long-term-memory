require_relative "test_helper"
require_relative "../scripts/rebuild_embeddings"

class TestRebuildEmbeddings < Test::Unit::TestCase
  def setup
    @embedder = StubEmbedder.new
    @store = MemoryStore.new(":memory:", embedder: @embedder)
    @store.store(content: "Rubyのメモリ管理", source: "claude_code")
    @store.store(content: "Obsidianのノート術", source: "obsidian")
  end

  def teardown
    @store.close
  end

  def test_rebuild_updates_all_embeddings
    RebuildEmbeddings.run(store: @store, embedder: @embedder)
    count = @store.db.execute("SELECT COUNT(*) as c FROM memories_vec").first["c"]
    assert_equal 2, count
  end

  def test_rebuild_replaces_existing_vectors
    id = @store.db.execute("SELECT id FROM memories LIMIT 1").first["id"]
    old_blob = @store.db.execute("SELECT embedding FROM memories_vec WHERE memory_id = ?", [id]).first["embedding"]

    # alter the stored vector to a known bad value
    zeros = Array.new(StubEmbedder::VECTOR_SIZE, 0.0).pack("f*")
    @store.db.execute("UPDATE memories_vec SET embedding = ? WHERE memory_id = ?", [zeros, id])

    RebuildEmbeddings.run(store: @store, embedder: @embedder)

    new_blob = @store.db.execute("SELECT embedding FROM memories_vec WHERE memory_id = ?", [id]).first["embedding"]
    assert_equal old_blob, new_blob, "embedding should be restored to correct value"
  end

  def test_rebuild_reports_progress
    messages = []
    RebuildEmbeddings.run(store: @store, embedder: @embedder) { |msg| messages << msg }
    assert_equal 2, messages.size, "should emit one message per record"
    assert messages.all? { |m| m.is_a?(String) }
  end
end
