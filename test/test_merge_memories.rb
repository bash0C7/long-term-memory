require_relative "test_helper"
require_relative "../scripts/merge_memories"
require "tmpdir"
require "fileutils"
require "json"

class TestMergeMemories < Test::Unit::TestCase
  def setup
    @store    = MemoryStore.new(":memory:", embedder: StubEmbedder.new)
    @dump_dir = Dir.mktmpdir
  end

  def teardown
    @store.close
    FileUtils.rm_rf(@dump_dir)
  end

  def write_ndjson(filename, records)
    File.open(File.join(@dump_dir, filename), "w") do |f|
      records.each { |r| f.puts JSON.generate(r) }
    end
  end

  def test_imports_records_from_single_ndjson
    write_ndjson("mac-a_20260403T120000.ndjson", [
      { "content" => "記憶A", "source" => "session", "project" => "proj", "tags" => nil, "created_at" => "2026-04-03T12:00:00+09:00" }
    ])
    result = MergeMemories.run(dump_dir: @dump_dir, store: @store)
    assert_equal 1, result[:imported]
    assert_equal 0, result[:skipped]
    assert_equal 1, @store.stats[:total]
  end

  def test_skips_duplicate_content_on_second_run
    write_ndjson("mac-a_20260403T120000.ndjson", [
      { "content" => "同じ記憶", "source" => "session", "project" => nil, "tags" => nil, "created_at" => "2026-04-03T12:00:00+09:00" }
    ])
    MergeMemories.run(dump_dir: @dump_dir, store: @store)
    result = MergeMemories.run(dump_dir: @dump_dir, store: @store)
    assert_equal 0, result[:imported]
    assert_equal 1, result[:skipped]
    assert_equal 1, @store.stats[:total]
  end

  def test_reads_only_latest_file_per_hostname
    write_ndjson("mac-a_20260403T100000.ndjson", [
      { "content" => "古い記憶", "source" => "session", "project" => nil, "tags" => nil, "created_at" => "2026-04-03T10:00:00+09:00" }
    ])
    write_ndjson("mac-a_20260403T120000.ndjson", [
      { "content" => "新しい記憶", "source" => "session", "project" => nil, "tags" => nil, "created_at" => "2026-04-03T12:00:00+09:00" }
    ])
    MergeMemories.run(dump_dir: @dump_dir, store: @store)
    assert_equal 1, @store.stats[:total], "最新ファイルのみ読まれること"
  end

  def test_merges_from_multiple_macs
    write_ndjson("mac-a_20260403T120000.ndjson", [
      { "content" => "Mac Aの記憶", "source" => "session", "project" => nil, "tags" => nil, "created_at" => "2026-04-03T12:00:00+09:00" }
    ])
    write_ndjson("mac-b_20260403T115500.ndjson", [
      { "content" => "Mac Bの記憶", "source" => "session", "project" => nil, "tags" => nil, "created_at" => "2026-04-03T11:55:00+09:00" }
    ])
    result = MergeMemories.run(dump_dir: @dump_dir, store: @store)
    assert_equal 2, result[:imported]
    assert_equal 2, @store.stats[:total]
  end

  def test_returns_zero_when_dump_dir_is_empty
    result = MergeMemories.run(dump_dir: @dump_dir, store: @store)
    assert_equal 0, result[:imported]
    assert_equal 0, result[:skipped]
  end

  def test_preserves_tags_on_import
    write_ndjson("mac-a_20260403T120000.ndjson", [
      { "content" => "タグ付き記憶テスト", "source" => "session", "project" => "p", "tags" => ["ruby", "test"], "created_at" => "2026-04-03T12:00:00+09:00" }
    ])
    MergeMemories.run(dump_dir: @dump_dir, store: @store)
    assert_equal 1, @store.stats[:total]
  end
end
