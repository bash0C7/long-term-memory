# test/test_capture_session.rb
require_relative "test_helper"
require_relative "../scripts/capture_session"

class TestCaptureSession < Test::Unit::TestCase
  def setup
    @store = MemoryStore.new(":memory:", embedder: StubEmbedder.new)
  end

  def teardown
    @store.close
  end

  def test_parse_extracts_cwd
    input = JSON.generate({
      "session_id" => "abc123",
      "cwd" => "/home/user/myproject",
      "transcript_path" => "/tmp/nonexistent.jsonl"
    })
    result = CaptureSession.parse_hook_input(input)
    assert_equal "/home/user/myproject", result[:cwd]
  end

  def test_parse_extracts_project_from_cwd
    input = JSON.generate({
      "session_id" => "abc123",
      "cwd" => "/home/user/myproject",
      "transcript_path" => "/tmp/nonexistent.jsonl"
    })
    result = CaptureSession.parse_hook_input(input)
    assert_equal "myproject", result[:project]
  end

  def test_run_stores_content_to_memory
    # Create a real tmpfile for transcript
    require "tempfile"
    transcript = Tempfile.new(["transcript", ".jsonl"])
    transcript.write(JSON.generate({ "role" => "user", "content" => "Rubyのテスト" }) + "\n")
    transcript.write(JSON.generate({ "role" => "assistant", "content" => "はい、テストです" }) + "\n")
    transcript.flush

    input = JSON.generate({
      "session_id" => "abc123",
      "cwd" => "/home/user/myproject",
      "transcript_path" => transcript.path
    })
    CaptureSession.run(input, store: @store)
    assert_equal 1, @store.stats[:total]
  ensure
    transcript.close
    transcript.unlink
  end

  def test_run_skips_empty_transcript
    require "tempfile"
    transcript = Tempfile.new(["empty", ".jsonl"])
    transcript.flush

    input = JSON.generate({
      "session_id" => "abc123",
      "cwd" => "/home/user/myproject",
      "transcript_path" => transcript.path
    })
    CaptureSession.run(input, store: @store)
    assert_equal 0, @store.stats[:total], "空の transcript は保存しない"
  ensure
    transcript.close
    transcript.unlink
  end

  def test_run_handles_missing_transcript_gracefully
    input = JSON.generate({
      "session_id" => "abc123",
      "cwd" => "/home/user/myproject",
      "transcript_path" => "/tmp/definitely_does_not_exist_xyz.jsonl"
    })
    # Should not raise
    assert_nothing_raised { CaptureSession.run(input, store: @store) }
  end
end
