$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))
require "json"
require "memory_store"

module MergeMemories
  DUMP_DIR = File.expand_path("~/Library/Mobile Documents/com~apple~CloudDocs/chiebukuro-mcp/dump/long-term-memory").freeze
  DB_PATH  = File.expand_path("../../db/memory.db", __FILE__).freeze

  def self.run(dump_dir: DUMP_DIR, db_path: DB_PATH, store: nil)
    own_store = store.nil?
    store   ||= MemoryStore.new(db_path)

    files = Dir.glob(File.join(dump_dir, "*.ndjson"))
    groups = files.group_by { |f| File.basename(f, ".ndjson").sub(/_\d{8}T\d{6}\z/, "") }

    total_imported = 0
    total_skipped  = 0

    groups.each do |hostname, group_files|
      latest = group_files.sort.last
      $stdout.puts "reading: #{File.basename(latest)} (#{hostname})"

      before     = store.stats[:total]
      line_count = 0

      File.foreach(latest) do |line|
        line = line.strip
        next if line.empty?
        record = JSON.parse(line)
        store.store(
          content: record["content"],
          source:  record["source"],
          project: record["project"],
          tags:    record["tags"]
        )
        line_count += 1
      rescue => e
        $stderr.puts "skip line: #{e.message}"
      end

      after    = store.stats[:total]
      imported = after - before
      skipped  = line_count - imported

      $stdout.puts "  imported: #{imported}, skipped: #{skipped}"
      total_imported += imported
      total_skipped  += skipped
    end

    $stdout.puts "total: imported=#{total_imported}, skipped=#{total_skipped}"
    store.close if own_store
    { imported: total_imported, skipped: total_skipped }
  end
end

if __FILE__ == $0
  dump_dir = ARGV.shift || MergeMemories::DUMP_DIR
  MergeMemories.run(dump_dir: dump_dir)
end
