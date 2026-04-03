$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))
require "json"
require "socket"
require "fileutils"
require "sqlite3"

module DumpMemories
  DUMP_DIR = File.expand_path("~/Library/Mobile Documents/com~apple~CloudDocs/chiebukuro-mcp/dump").freeze
  DB_PATH  = File.expand_path("../../db/memory.db", __FILE__).freeze

  def self.run(db_path: DB_PATH, dump_dir: DUMP_DIR)
    FileUtils.mkdir_p(dump_dir)
    hostname  = Socket.gethostname
    timestamp = Time.now.strftime("%Y%m%dT%H%M%S")
    out_path  = File.join(dump_dir, "#{hostname}_#{timestamp}.ndjson")

    db = SQLite3::Database.new(db_path)
    db.results_as_hash = true

    count = 0
    begin
      File.open(out_path, "w") do |f|
        db.execute("SELECT content, source, project, tags, created_at FROM memories ORDER BY id").each do |row|
          tags = begin
            row["tags"] ? JSON.parse(row["tags"]) : nil
          rescue JSON::ParserError
            nil
          end
          f.puts JSON.generate({
            "content"    => row["content"],
            "source"     => row["source"],
            "project"    => row["project"],
            "tags"       => tags,
            "created_at" => row["created_at"]
          })
          count += 1
        end
      end
    ensure
      db.close
    end

    $stdout.puts "dumped: #{out_path} (#{count} records)"
    out_path
  end
end

if __FILE__ == $0
  dump_dir = ARGV.shift || DumpMemories::DUMP_DIR
  DumpMemories.run(dump_dir: dump_dir)
end
