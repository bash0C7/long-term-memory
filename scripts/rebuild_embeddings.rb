$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))
require "memory_store"
require "embedder"

module RebuildEmbeddings
  DB_PATH = File.expand_path("../../db/memory.db", __FILE__).freeze

  def self.run(store: nil, embedder: nil, &on_progress)
    store ||= MemoryStore.new(DB_PATH)
    embedder ||= Embedder.new

    rows = store.db.execute("SELECT id, content FROM memories ORDER BY id")
    rows.each do |row|
      id = row["id"]
      content = row["content"]
      embedding = embedder.embed(content)
      blob = embedding.pack("f*")
      store.db.execute("DELETE FROM memories_vec WHERE memory_id = ?", [id])
      store.db.execute(
        "INSERT INTO memories_vec(memory_id, embedding) VALUES (?, ?)",
        [id, blob]
      )
      on_progress&.call("rebuilt embedding: id=#{id}")
    end
  end
end

if __FILE__ == $0
  RebuildEmbeddings.run { |msg| warn msg }
end
