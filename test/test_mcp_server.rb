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
