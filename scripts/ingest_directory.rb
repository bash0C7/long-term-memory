$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))
require "memory_store"
require "embedder"
require "optparse"

module IngestDirectory
  DB_PATH = File.expand_path("../../db/memory.db", __FILE__).freeze
  DEFAULT_EXTENSIONS = %w[.md .txt .rb .yaml .yml].freeze

  def self.run(directory:, source:, project: nil, extensions: DEFAULT_EXTENSIONS, store: nil)
    store ||= MemoryStore.new(DB_PATH)
    files = Dir.glob(File.join(directory, "**", "*"))
              .select { |f| File.file?(f) && extensions.include?(File.extname(f).downcase) }

    files.each do |path|
      begin
        content = File.read(path, encoding: "utf-8")
        next if content.strip.empty?
        store.store(
          content: content,
          source: source,
          project: project || File.basename(directory),
          tags: [File.extname(path).delete(".")]
        )
        warn "ingested: #{path}"
      rescue => e
        warn "skip #{path}: #{e.message}"
      end
    end
  end
end

if __FILE__ == $0
  options = { source: "obsidian", extensions: IngestDirectory::DEFAULT_EXTENSIONS }
  OptionParser.new do |opts|
    opts.banner = "Usage: ingest_directory.rb <directory> [options]"
    opts.on("--source SOURCE", "source 値（デフォルト: obsidian）") { |v| options[:source] = v }
    opts.on("--project PROJECT", "project 名") { |v| options[:project] = v }
    opts.on("--ext EXTS", "カンマ区切り拡張子（例: md,txt）") { |v| options[:extensions] = v.split(",").map { |e| e.start_with?(".") ? e : ".#{e}" } }
  end.parse!

  directory = ARGV.shift
  abort "Usage: ingest_directory.rb <directory> [--source SOURCE] [--project PROJECT]" unless directory
  abort "Directory not found: #{directory}" unless File.directory?(directory)

  IngestDirectory.run(directory: directory, **options)
end
