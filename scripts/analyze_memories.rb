$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))
require "sqlite3"
require "sqlite_vec"
require "optparse"
require "memory_store"

module AnalyzeMemories
  DB_PATH = File.expand_path("../../db/memory.db", __FILE__).freeze

  def self.cosine(a, b)
    dot = 0.0
    a.each_with_index { |v, i| dot += v * b[i] }
    na = Math.sqrt(a.sum { |v| v * v })
    nb = Math.sqrt(b.sum { |v| v * v })
    dot / (na * nb + 1e-10)
  end

  def self.find_groups(db, threshold: 0.95, limit: 30)
    t0 = Time.now

    rows = db.execute(<<~SQL)
      SELECT mv.memory_id, mv.embedding, m.content, m.source, m.created_at
      FROM memories_vec mv
      JOIN memories m ON m.id = mv.memory_id
    SQL
    items = rows.map do |r|
      {
        id:         r["memory_id"],
        vec:        r["embedding"].unpack("f*"),
        content:    r["content"],
        source:     r["source"],
        created_at: r["created_at"]
      }
    end

    # Union-Find
    parent = items.each_with_index.to_h { |_, i| [i, i] }
    max_sim = Hash.new(0.0)

    find = ->(x) {
      parent[x] = find.call(parent[x]) unless parent[x] == x
      parent[x]
    }
    union = ->(x, y) { parent[find.call(x)] = find.call(y) }

    items.each_with_index do |a, i|
      items[(i + 1)..].each_with_index do |b, j|
        sim = cosine(a[:vec], b[:vec])
        if sim >= threshold
          ri, rj = find.call(i), find.call(i + 1 + j)
          key = [ri, rj].sort.join("-")
          max_sim[key] = [max_sim[key], sim].max
          union.call(i, i + 1 + j)
        end
      end
    end

    # グループ化
    components = Hash.new { |h, k| h[k] = [] }
    items.each_with_index { |item, i| components[find.call(i)] << item }

    groups = components
      .values
      .select { |g| g.size >= 2 }
      .map do |members|
        indices = members.map { |m| items.index { |it| it[:id] == m[:id] } }
        sims = []
        indices.combination(2) do |ii, jj|
          sims << cosine(items[ii][:vec], items[jj][:vec])
        end
        { members: members, max_sim: sims.max || 0.0 }
      end
      .sort_by { |g| -g[:max_sim] }
      .first(limit)

    elapsed_ms = ((Time.now - t0) * 1000).round
    { total: items.size, groups: groups, elapsed_ms: elapsed_ms }
  end

  def self.run(db_path: DB_PATH, threshold: 0.95, limit: 30)
    db = SQLite3::Database.new(db_path)
    db.results_as_hash = true
    db.enable_load_extension(true)
    SqliteVec.load(db)
    db.enable_load_extension(false)

    begin
      result = find_groups(db, threshold: threshold, limit: limit)
      print_report(result, threshold: threshold)
    ensure
      db.close
    end
  end

  def self.print_report(result, threshold:)
    puts "=== 記憶類似分析 (threshold=#{threshold}, #{result[:total]}件) ==="
    puts "分析時間: #{result[:elapsed_ms]}ms"
    puts

    if result[:groups].empty?
      puts "類似グループなし (threshold=#{threshold})"
      return
    end

    puts "類似グループ: #{result[:groups].size}グループ"
    puts

    result[:groups].each_with_index do |group, idx|
      puts "─── グループ #{idx + 1} (#{group[:members].size}件, 最高sim=#{group[:max_sim].round(4)}) ───"
      group[:members].each do |m|
        snippet = m[:content].gsub(/\s+/, " ").strip[0, 80]
        puts "  [#{m[:id]}] #{m[:source]} | #{m[:created_at]}"
        puts "    #{snippet}..."
      end
      puts
    end

    puts "─" * 60
    puts "注意: 矛盾・重複の最終判断はこのセッションでClaudeに見せてください"
    puts "削除: bundle exec ruby -e \"require_relative 'lib/memory_store'; s=MemoryStore.new('db/memory.db'); s.delete(ID); s.close\""
  end
end

if __FILE__ == $0
  options = { threshold: 0.95, limit: 30 }
  OptionParser.new do |opts|
    opts.banner = "Usage: analyze_memories.rb [options]"
    opts.on("--threshold FLOAT", Float, "類似度しきい値 (default: 0.95)") { |v| options[:threshold] = v }
    opts.on("--limit N", Integer, "表示グループ数上限 (default: 30)") { |v| options[:limit] = v }
  end.parse!

  AnalyzeMemories.run(**options)
end
