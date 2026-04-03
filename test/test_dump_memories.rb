require_relative "test_helper"
require_relative "../scripts/dump_memories"
require "tmpdir"
require "fileutils"
require "socket"
require "tempfile"

class TestDumpMemories < Test::Unit::TestCase
  def setup
    @tmpdb_path = File.join(Dir.tmpdir, "test_dump_#{$$}.db")
    @store = MemoryStore.new(@tmpdb_path, embedder: StubEmbedder.new)
    @dump_dir = Dir.mktmpdir
  end

  def teardown
    @store.close
    File.unlink(@tmpdb_path) if File.exist?(@tmpdb_path)
    FileUtils.rm_rf(@dump_dir)
  end

  def test_creates_ndjson_file_with_correct_name
    @store.store(content: "テスト記憶", source: "test", project: "proj")
    out_path = DumpMemories.run(db_path: @tmpdb_path, dump_dir: @dump_dir)
    hostname = Socket.gethostname
    assert File.exist?(out_path)
    assert_match(/\A#{Regexp.escape(hostname)}_\d{8}T\d{6}\.ndjson\z/, File.basename(out_path))
  end

  def test_dumps_all_records_as_ndjson
    @store.store(content: "記憶1", source: "session", project: "proj")
    @store.store(content: "記憶2", source: "hook",    project: nil)
    out_path = DumpMemories.run(db_path: @tmpdb_path, dump_dir: @dump_dir)
    lines = File.readlines(out_path).map { |l| JSON.parse(l) }
    assert_equal 2, lines.size
    contents = lines.map { |l| l["content"] }
    assert_include contents, "記憶1"
    assert_include contents, "記憶2"
  end

  def test_dumps_all_required_fields
    @store.store(content: "フィールドテスト", source: "session", project: "myproj", tags: ["ruby"])
    out_path = DumpMemories.run(db_path: @tmpdb_path, dump_dir: @dump_dir)
    record = JSON.parse(File.readlines(out_path).first)
    assert_equal "フィールドテスト", record["content"]
    assert_equal "session",          record["source"]
    assert_equal "myproj",           record["project"]
    assert_equal ["ruby"],           record["tags"]
    assert_not_nil                   record["created_at"]
  end

  def test_empty_db_creates_empty_file
    out_path = DumpMemories.run(db_path: @tmpdb_path, dump_dir: @dump_dir)
    assert File.exist?(out_path)
    assert_equal 0, File.readlines(out_path).size
  end

  def test_returns_output_file_path
    out_path = DumpMemories.run(db_path: @tmpdb_path, dump_dir: @dump_dir)
    assert_kind_of String, out_path
    assert out_path.end_with?(".ndjson")
  end
end
