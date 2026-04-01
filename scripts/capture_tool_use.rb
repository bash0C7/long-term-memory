# scripts/capture_tool_use.rb
# PostToolUse hook で呼ばれ、価値の高いツール操作を長期記憶に保存する
$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))
require "json"
require "memory_store"
require "embedder"

module CaptureToolUse
  DB_PATH = File.expand_path("../../db/memory.db", __FILE__).freeze
  CURL_PATTERN = /\b(curl|wget)\b/
  MAX_CONTENT_LENGTH = 4000

  def self.run(json_str, store: nil)
    data = JSON.parse(json_str)
    tool_name   = data["tool_name"]
    tool_input  = data["tool_input"] || {}
    tool_response = data["tool_response"]
    cwd     = data["cwd"] || ""
    project = File.basename(cwd)

    content = build_content(tool_name, tool_input, tool_response)
    return unless content

    store ||= MemoryStore.new(DB_PATH)
    store.store(
      content: content,
      source: "claude_code",
      project: project,
      tags: ["tool_use", tool_name.downcase]
    )
  rescue => e
    warn "capture_tool_use error: #{e.message}"
  end

  def self.build_content(tool_name, tool_input, tool_response)
    case tool_name
    when "Edit"
      file_path = tool_input["file_path"]
      old_str   = tool_input["old_string"].to_s
      new_str   = tool_input["new_string"].to_s
      "[Edit] #{file_path}\n--- before ---\n#{old_str}\n--- after ---\n#{new_str}"
    when "Write"
      file_path = tool_input["file_path"]
      "[Write] #{file_path}\n#{tool_input["content"].to_s}"
    when "Bash"
      command = tool_input["command"].to_s
      return nil unless command.match?(CURL_PATTERN)
      output = extract_text(tool_response).slice(0, MAX_CONTENT_LENGTH)
      "[Bash] #{command}\n#{output}"
    when "WebFetch"
      url    = tool_input["url"]
      prompt = tool_input["prompt"]
      output = extract_text(tool_response).slice(0, MAX_CONTENT_LENGTH)
      "[WebFetch] #{url}\nprompt: #{prompt}\n#{output}"
    when "WebSearch"
      query  = tool_input["query"]
      output = extract_text(tool_response).slice(0, MAX_CONTENT_LENGTH)
      "[WebSearch] #{query}\n#{output}"
    end
  end

  def self.extract_text(response)
    case response
    when String then response
    when Hash
      response["output"] || response["content"] || response["text"] || response.to_s
    when Array
      response.map { |r|
        r.is_a?(Hash) ? (r["text"] || r["content"] || r.to_s) : r.to_s
      }.join("\n")
    else
      response.to_s
    end
  end
end

if __FILE__ == $0
  input = $stdin.read
  CaptureToolUse.run(input)
end
