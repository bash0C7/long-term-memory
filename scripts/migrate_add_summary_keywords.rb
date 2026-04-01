# scripts/migrate_add_summary_keywords.rb
# 既存DBに summary/keywords カラムを追加し全レコードを処理する。一度だけ手動実行。
$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))
require "sqlite3"
require "sqlite_vec"
require "json"
require "keyword_extractor"
require "embedder"

DB_PATH = File.expand_path("../../db/memory.db", __FILE__).freeze

unless File.exist?(DB_PATH)
  puts "DB not found: #{DB_PATH}"
  exit 1
end

db = SQLite3::Database.new(DB_PATH)
db.results_as_hash = true
db.enable_load_extension(true)
SqliteVec.load(db)
db.enable_load_extension(false)

%w[summary keywords].each do |col|
  begin
    db.execute("ALTER TABLE memories ADD COLUMN #{col} TEXT")
    puts "Added column: #{col}"
  rescue SQLite3::Exception => e
    puts "Column '#{col}' already exists (#{e.message})"
  end
end

total = db.execute("SELECT COUNT(*) as c FROM memories").first["c"]
puts "Processing #{total} records..."

embedder  = Embedder.new
processed = 0
offset    = 0
batch_size = 100

while offset < total
  rows = db.execute("SELECT id, content FROM memories LIMIT ? OFFSET ?", [batch_size, offset])
  break if rows.empty?

  rows.each do |row|
    id      = row["id"]
    content = row["content"]

    summary       = KeywordExtractor.summarize(content)
    keywords      = KeywordExtractor.extract(content)
    keywords_json = JSON.generate(keywords)

    db.execute("UPDATE memories SET summary = ?, keywords = ? WHERE id = ?", [summary, keywords_json, id])

    embed_text     = "#{summary} #{keywords.join(' ')}"
    embedding      = embedder.embed(embed_text)
    embedding_blob = embedding.pack("f*")
    db.execute("DELETE FROM memories_vec WHERE memory_id = ?", [id])
    db.execute("INSERT INTO memories_vec(memory_id, embedding) VALUES (?, ?)", [id, embedding_blob])

    processed += 1
    print "." if (processed % 10).zero?
  end

  offset += batch_size
end

puts "\nDone! Processed #{processed} / #{total} records."
