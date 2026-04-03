require_relative "test_helper"
require_relative "../scripts/capture_tool_use"

class TestCaptureToolUse < Test::Unit::TestCase
  def setup
    @store = MemoryStore.new(":memory:", embedder: StubEmbedder.new)
  end

  def teardown
    @store.close
  end

  def test_stores_substantial_edit
    input = JSON.generate({
      "tool_name" => "Edit",
      "tool_input" => {
        "file_path" => "lib/foo.rb",
        "old_string" => "def old_method\n  # old implementation with many lines of code here for the feature\nend",
        "new_string"  => "def new_method\n  # new implementation with many lines of code here refactored cleanly\nend"
      },
      "tool_response" => "ok",
      "cwd" => "/home/user/myproject"
    })
    CaptureToolUse.run(input, store: @store)
    assert_equal 1, @store.stats[:total], "十分な長さのEditは保存される"
  end

  def test_skips_trivial_edit
    input = JSON.generate({
      "tool_name" => "Edit",
      "tool_input" => {
        "file_path" => "lib/foo.rb",
        "old_string" => "test",
        "new_string"  => "test2"
      },
      "tool_response" => "ok",
      "cwd" => "/home/user/myproject"
    })
    CaptureToolUse.run(input, store: @store)
    assert_equal 0, @store.stats[:total], "短すぎるEditはスキップされる"
  end

  def test_stores_substantial_write
    long_content = "# Module\n" + ("x" * 300)
    input = JSON.generate({
      "tool_name" => "Write",
      "tool_input" => {
        "file_path" => "lib/new.rb",
        "content" => long_content
      },
      "tool_response" => "ok",
      "cwd" => "/home/user/myproject"
    })
    CaptureToolUse.run(input, store: @store)
    assert_equal 1, @store.stats[:total], "十分な長さのWriteは保存される"
  end

  def test_skips_trivial_write
    input = JSON.generate({
      "tool_name" => "Write",
      "tool_input" => {
        "file_path" => "lib/new.rb",
        "content" => "short"
      },
      "tool_response" => "ok",
      "cwd" => "/home/user/myproject"
    })
    CaptureToolUse.run(input, store: @store)
    assert_equal 0, @store.stats[:total], "短すぎるWriteはスキップされる"
  end

  def test_stores_websearch
    input = JSON.generate({
      "tool_name" => "WebSearch",
      "tool_input" => { "query" => "Ruby sqlite3 gem" },
      "tool_response" => "Result: " + ("x" * 300),
      "cwd" => "/home/user/myproject"
    })
    CaptureToolUse.run(input, store: @store)
    assert_equal 1, @store.stats[:total]
  end

  def test_skips_non_curl_bash
    input = JSON.generate({
      "tool_name" => "Bash",
      "tool_input" => { "command" => "ls -la" },
      "tool_response" => "total 8\ndrwxr-xr-x 2 user user 4096 Jan 1 00:00 .\n",
      "cwd" => "/home/user/myproject"
    })
    CaptureToolUse.run(input, store: @store)
    assert_equal 0, @store.stats[:total], "curl/wget以外のBashはスキップ"
  end
end
