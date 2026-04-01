# scripts/skill_context.rb
# PreToolUse hook — Skill ツール呼び出し前に long-term-memory を検索してコンテキストを注入する。
# スキル名（例: "dotfiles-status"）をそのまま検索クエリとして使うことで、
# スキルファイル名プリフィクスと記憶の紐付けを統一する。
$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))
require "json"
require "memory_store"

# ONNX モデルロードを回避する軽量スタブ。FTS5 検索で十分なため vec0 は不使用。
class NullEmbedder
  VECTOR_SIZE = 768
  def embed(_text)
    [0.0] * VECTOR_SIZE
  end
end

module SkillContext
  DB_PATH = File.expand_path("../../db/memory.db", __FILE__).freeze

  def self.run(json_str, store: nil)
    data = JSON.parse(json_str)
    return unless data["tool_name"] == "Skill"

    skill_name = (data["tool_input"] || {})["skill"].to_s.strip
    return if skill_name.empty?

    store ||= MemoryStore.new(DB_PATH, embedder: NullEmbedder.new)
    results = store.search(query: skill_name, limit: 5)
    return if results.empty?

    format_output(skill_name, results)
  rescue => e
    warn "skill_context error: #{e.message}"
    nil
  end

  def self.format_output(skill_name, results)
    lines = ["## long-term-memory: #{skill_name} (#{results.size}件)"]
    results.each do |r|
      date = r["created_at"].to_s[0, 10]
      lines << "- [#{date}] #{r["summary"]}"
    end
    lines.join("\n")
  end
end

if __FILE__ == $0
  input = $stdin.read
  output = SkillContext.run(input)
  puts output if output
end
