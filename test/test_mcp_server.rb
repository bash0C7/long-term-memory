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
