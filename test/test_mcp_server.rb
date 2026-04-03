require_relative "test_helper"
require_relative "../scripts/mcp_server"

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
