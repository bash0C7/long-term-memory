require_relative "test_helper"
require_relative "../scripts/ingest_directory"
require "tmpdir"
require "fileutils"

class TestIngestDirectory < Test::Unit::TestCase
  def setup
    @store = MemoryStore.new(":memory:", embedder: StubEmbedder.new)
    @tmpdir = Dir.mktmpdir
  end

  def teardown
    @store.close
    FileUtils.rm_rf(@tmpdir)
  end

  def test_ingests_markdown_files
    File.write(File.join(@tmpdir, "note.md"), "# Zettelkasten\nノート管理の手法")
    File.write(File.join(@tmpdir, "idea.txt"), "アイデアのメモ")
    IngestDirectory.run(directory: @tmpdir, source: "obsidian", store: @store)
    assert_equal 2, @store.stats[:total]
  end

  def test_skips_non_target_extensions
    File.write(File.join(@tmpdir, "image.png"), "binary")
    File.write(File.join(@tmpdir, "note.md"), "マークダウン")
    IngestDirectory.run(directory: @tmpdir, source: "obsidian", store: @store)
    assert_equal 1, @store.stats[:total], ".png はスキップされること"
  end

  def test_recurses_into_subdirectories
    subdir = File.join(@tmpdir, "subdir")
    Dir.mkdir(subdir)
    File.write(File.join(subdir, "deep.md"), "深いノート")
    IngestDirectory.run(directory: @tmpdir, source: "obsidian", store: @store)
    assert_equal 1, @store.stats[:total]
  end

  def test_idempotent_second_run_does_not_duplicate
    File.write(File.join(@tmpdir, "note.md"), "同じ内容")
    IngestDirectory.run(directory: @tmpdir, source: "obsidian", store: @store)
    IngestDirectory.run(directory: @tmpdir, source: "obsidian", store: @store)
    assert_equal 1, @store.stats[:total], "2回実行しても重複しない"
  end

  def test_sets_source_and_project
    File.write(File.join(@tmpdir, "note.md"), "プロジェクトテスト")
    IngestDirectory.run(directory: @tmpdir, source: "obsidian", project: "myvault", store: @store)
    results = @store.list
    assert_equal "obsidian", results.first["source"]
    assert_equal "myvault", results.first["project"]
  end
end
