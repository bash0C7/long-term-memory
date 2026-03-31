require "sqlite3"
require "sqlite_vec"
require "json"
require "digest"
require "time"
require_relative "embedder"

class MemoryStore
  attr_reader :db

  def initialize(db_path, embedder: nil)
    @db = SQLite3::Database.new(db_path)
    @db.results_as_hash = true
    @db.busy_timeout = 5000
    @embedder = embedder || Embedder.new
    setup_extensions
    setup_pragmas
    create_schema
  end

  def close
    @db.close
  end

  private

  def setup_extensions
    @db.enable_load_extension(true)
    SqliteVec.load(@db)
    @db.enable_load_extension(false)
  end

  def setup_pragmas
    @db.execute("PRAGMA journal_mode=WAL")
    @db.execute("PRAGMA synchronous=NORMAL")
  end

  def create_schema
    @db.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS memories (
        id           INTEGER PRIMARY KEY,
        content      TEXT    NOT NULL,
        source       TEXT    NOT NULL,
        project      TEXT,
        tags         TEXT,
        content_hash TEXT,
        created_at   TEXT    NOT NULL
      )
    SQL

    @db.execute(<<~SQL)
      CREATE UNIQUE INDEX IF NOT EXISTS uix_content_hash
        ON memories(content_hash)
        WHERE content_hash IS NOT NULL
    SQL

    @db.execute(<<~SQL)
      CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
        content,
        tags,
        content='memories',
        content_rowid='id'
      )
    SQL

    vector_size = @embedder.class::VECTOR_SIZE
    @db.execute(<<~SQL)
      CREATE VIRTUAL TABLE IF NOT EXISTS memories_vec USING vec0(
        memory_id INTEGER PRIMARY KEY,
        embedding FLOAT[#{vector_size}]
      )
    SQL

    @db.execute(<<~SQL)
      CREATE TRIGGER IF NOT EXISTS memories_ai
        AFTER INSERT ON memories BEGIN
          INSERT INTO memories_fts(rowid, content, tags)
            VALUES (new.id, new.content, COALESCE(new.tags, ''));
        END
    SQL

    @db.execute(<<~SQL)
      CREATE TRIGGER IF NOT EXISTS memories_ad
        AFTER DELETE ON memories BEGIN
          INSERT INTO memories_fts(memories_fts, rowid, content, tags)
            VALUES ('delete', old.id, old.content, COALESCE(old.tags, ''));
        END
    SQL
  end
end
