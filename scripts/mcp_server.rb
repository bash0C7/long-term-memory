$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))
require "mcp"
require "json"
require "memory_store"
require "embedder"

DB_PATH = File.expand_path("../../db/memory.db", __FILE__).freeze

class LongTermMemoryStore < MCP::Tool
  description "【専用ツール: long-term-memory / 長期記憶 / LongMemory / LongTermMemory と明示的に指定された場合のみ使用すること。一般的な記憶保存・永続記憶には使わない。】記憶を長期記憶DBに保存する（Claude Desktop からの手動保存用）。summary と keywords を自動生成する。"

  input_schema(
    properties: {
      content: { type: "string", description: "保存するテキスト" },
      source:  { type: "string", description: "claude_desktop | obsidian など" },
      project: { type: "string", description: "プロジェクト名（省略可）" },
      tags:    { type: "array", items: { type: "string" }, description: "タグ（省略可）" }
    },
    required: ["content", "source"]
  )

  class << self
    def call(content:, source:, project: nil, tags: nil, server_context:)
      store = server_context[:memory_store]
      id    = store.store(content: content, source: source, project: project, tags: tags)
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate({ id: id, status: "stored" }) }])
    rescue => e
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate({ error: e.message }) }], error: true)
    end
  end
end

class LongTermMemoryDelete < MCP::Tool
  description "【専用ツール: long-term-memory / 長期記憶 / LongMemory / LongTermMemory と明示的に指定された場合のみ使用すること。】指定 ID の長期記憶を削除する"

  input_schema(
    properties: {
      id: { type: "integer", description: "削除する記憶の ID" }
    },
    required: ["id"]
  )

  class << self
    def call(id:, server_context:)
      store = server_context[:memory_store]
      store.delete(id)
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate({ id: id, status: "deleted" }) }])
    rescue => e
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate({ error: e.message }) }], error: true)
    end
  end
end

class LongTermMemoryStats < MCP::Tool
  description "【専用ツール: long-term-memory / 長期記憶 / LongMemory / LongTermMemory と明示的に指定された場合のみ使用すること。】長期記憶 DB の統計情報（総件数・source 別・最古/最新日時）を返す"

  input_schema(properties: {})

  class << self
    def call(server_context:)
      store = server_context[:memory_store]
      stats = store.stats
      MCP::Tool::Response.new([{ type: "text", text: JSON.pretty_generate(stats) }])
    rescue => e
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate({ error: e.message }) }], error: true)
    end
  end
end

if __FILE__ == $0
  store  = MemoryStore.new(DB_PATH)
  server = MCP::Server.new(
    name:    "long-term-memory",
    version: "1.0.0",
    tools:   [
      LongTermMemoryStore,
      LongTermMemoryDelete,
      LongTermMemoryStats
    ],
    server_context: { memory_store: store }
  )
  transport = MCP::Server::Transports::StdioTransport.new(server)
  transport.open
end
