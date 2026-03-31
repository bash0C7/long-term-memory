# scripts/capture_session.rb
$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))
require "json"
require "memory_store"
require "embedder"

module CaptureSession
  DB_PATH = File.expand_path("../../db/memory.db", __FILE__).freeze

  def self.parse_hook_input(json_str)
    data = JSON.parse(json_str)
    cwd = data["cwd"] || ""
    project = File.basename(cwd)
    {
      session_id: data["session_id"],
      cwd: cwd,
      project: project,
      transcript_path: data["transcript_path"]
    }
  end

  def self.read_transcript(transcript_path)
    return [] unless transcript_path && File.exist?(transcript_path)
    File.readlines(transcript_path, chomp: true)
      .reject(&:empty?)
      .map { |line| JSON.parse(line) rescue nil }
      .compact
  rescue => e
    warn "capture_session: failed to read transcript: #{e.message}"
    []
  end

  def self.build_content(messages)
    messages.map do |msg|
      role = msg["role"] || "unknown"
      content = msg["content"].is_a?(String) ? msg["content"] : msg["content"].to_s
      "[#{role}] #{content}"
    end.join("\n")
  end

  def self.run(json_str, store: nil)
    parsed = parse_hook_input(json_str)
    messages = read_transcript(parsed[:transcript_path])
    return if messages.empty?

    content = build_content(messages)
    return if content.strip.empty?

    store ||= MemoryStore.new(DB_PATH)
    store.store(
      content: content,
      source: "claude_code",
      project: parsed[:project],
      tags: ["session", parsed[:session_id]].compact
    )
  rescue => e
    warn "capture_session error: #{e.message}"
  end
end

if __FILE__ == $0
  input = $stdin.read
  CaptureSession.run(input)
end
