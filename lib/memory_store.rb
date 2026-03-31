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

  def store(content:, source:, project: nil, tags: nil)
    content_hash = Digest::SHA256.hexdigest(content)

    # 冪等: 同じ content_hash が既にあればその id を返す
    existing = @db.execute(
      "SELECT id FROM memories WHERE content_hash = ?", [content_hash]
    ).first
    return existing["id"] if existing

    tags_json = tags ? JSON.generate(tags) : nil
    created_at = Time.now.iso8601

    @db.execute(
      "INSERT INTO memories (content, source, project, tags, content_hash, created_at) VALUES (?, ?, ?, ?, ?, ?)",
      [content, source, project, tags_json, content_hash, created_at]
    )
    id = @db.last_insert_row_id

    embedding = @embedder.embed(content)
    embedding_blob = embedding.pack("f*")
    @db.execute(
      "INSERT INTO memories_vec(memory_id, embedding) VALUES (?, ?)",
      [id, embedding_blob]
    )

    id
  end

  def search(query:, scope: nil, project: nil, limit: 5)
    conditions = []
    condition_params = []
    if scope
      conditions << "m.source = ?"
      condition_params << scope
    end
    if project
      conditions << "m.project = ?"
      condition_params << project
    end
    where_clause = conditions.empty? ? "" : "AND #{conditions.join(' AND ')}"

    # FTS5 検索
    fts_rows = begin
      @db.execute(<<~SQL, [query] + condition_params + [limit * 2])
        SELECT m.id, m.content, m.source, m.project, m.tags, m.created_at
        FROM memories m
        JOIN memories_fts ON memories_fts.rowid = m.id
        WHERE memories_fts MATCH ? #{where_clause}
        ORDER BY rank
        LIMIT ?
      SQL
    rescue SQLite3::Exception
      []
    end

    # ベクトル検索
    query_blob = @embedder.embed(query).pack("f*")
    vec_rows = begin
      if conditions.empty?
        @db.execute(
          "SELECT mv.memory_id, mv.distance FROM memories_vec mv ORDER BY mv.embedding <-> ? LIMIT ?",
          [query_blob, limit * 2]
        )
      else
        @db.execute(
          "SELECT mv.memory_id, mv.distance FROM memories_vec mv JOIN memories m ON m.id = mv.memory_id WHERE 1=1 #{where_clause} ORDER BY mv.embedding <-> ? LIMIT ?",
          condition_params + [query_blob, limit * 2]
        )
      end
    rescue SQLite3::Exception
      []
    end

    # RRF 融合
    k = 60
    scores = Hash.new(0.0)

    fts_rows.each_with_index do |row, rank|
      id = row["id"] || row[0]
      scores[id] += 1.0 / (k + rank + 1)
    end

    vec_rows.each_with_index do |row, rank|
      id = row["memory_id"] || row[0]
      scores[id] += 1.0 / (k + rank + 1)
    end

    return [] if scores.empty?

    # 時間減衰をかけてスコア確定
    all_ids = scores.keys
    placeholders = all_ids.map { "?" }.join(",")
    meta_rows = @db.execute(
      "SELECT id, content, source, project, tags, created_at FROM memories WHERE id IN (#{placeholders})",
      all_ids
    )
    meta_by_id = meta_rows.each_with_object({}) { |r, h| h[r["id"]] = r }

    scored = scores.map do |id, rrf|
      row = meta_by_id[id]
      next unless row
      age_days = (Time.now - Time.parse(row["created_at"])).abs / 86400.0
      decay = 0.5 ** (age_days / 30.0)
      row.merge("score" => rrf * decay)
    end.compact

    scored.sort_by { |r| -r["score"] }.first(limit)
  end

  def list(scope: nil, project: nil, limit: 20)
    conditions = []
    params = []
    if scope
      conditions << "source = ?"
      params << scope
    end
    if project
      conditions << "project = ?"
      params << project
    end
    where = conditions.empty? ? "" : "WHERE #{conditions.join(' AND ')}"
    params << limit
    @db.execute("SELECT id, content, source, project, tags, created_at FROM memories #{where} ORDER BY created_at DESC LIMIT ?", params)
  end

  def delete(id)
    @db.transaction do
      @db.execute("DELETE FROM memories_vec WHERE memory_id = ?", [id])
      @db.execute("DELETE FROM memories WHERE id = ?", [id])
    end
  end

  def stats
    total = @db.execute("SELECT COUNT(*) as c FROM memories").first["c"]
    by_source = @db.execute("SELECT source, COUNT(*) as c FROM memories GROUP BY source")
      .each_with_object({}) { |r, h| h[r["source"]] = r["c"] }
    oldest = @db.execute("SELECT MIN(created_at) as t FROM memories").first["t"]
    newest = @db.execute("SELECT MAX(created_at) as t FROM memories").first["t"]
    { total: total, by_source: by_source, oldest_at: oldest, newest_at: newest }
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
        content_rowid='id',
        tokenize='trigram'
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
