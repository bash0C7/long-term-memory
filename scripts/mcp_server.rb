$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))
require "mcp"
require "json"
require "memory_store"
require "embedder"

DB_PATH = File.expand_path("../../db/memory.db", __FILE__).freeze

class SearchMemoryTool < MCP::Tool
  description <<~DESC
    長期記憶をハイブリッド検索（FTS5+ベクトル+RRF）で照会する。
    query に scope ワード（"obsidian", "claude_code" など）や
    プロジェクト名を含めると絞り込みが効く。
  DESC

  input_schema(
    properties: {
      query:   { type: "string",  description: "検索クエリ" },
      scope:   { type: "string",  description: "source 絞り込み: claude_code | claude_desktop | obsidian" },
      project: { type: "string",  description: "プロジェクト名絞り込み" },
      limit:   { type: "integer", description: "最大件数（デフォルト 5）" }
    },
    required: ["query"]
  )

  class << self
    def call(query:, scope: nil, project: nil, limit: 5, server_context:)
      return MCP::Tool::Response.new([{ type: "text", text: '{"error":"query is required"}' }], error: true) if query.to_s.strip.empty?

      store = server_context[:memory_store]
      results = store.search(query: query, scope: scope, project: project, limit: limit)
      MCP::Tool::Response.new([{ type: "text", text: JSON.pretty_generate(results) }])
    rescue => e
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate({ error: e.message }) }], error: true)
    end
  end
end

class StoreMemoryTool < MCP::Tool
  description "記憶を保存する（Claude Desktop からの手動保存用）"

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
      id = store.store(content: content, source: source, project: project, tags: tags)
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate({ id: id, status: "stored" }) }])
    rescue => e
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate({ error: e.message }) }], error: true)
    end
  end
end

class ListMemoriesTool < MCP::Tool
  description "最近の記憶を一覧表示する"

  input_schema(
    properties: {
      scope:   { type: "string",  description: "source 絞り込み（省略可）" },
      project: { type: "string",  description: "プロジェクト絞り込み（省略可）" },
      limit:   { type: "integer", description: "最大件数（デフォルト 20）" }
    }
  )

  class << self
    def call(scope: nil, project: nil, limit: 20, server_context:)
      store = server_context[:memory_store]
      results = store.list(scope: scope, project: project, limit: limit)
      MCP::Tool::Response.new([{ type: "text", text: JSON.pretty_generate(results) }])
    rescue => e
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate({ error: e.message }) }], error: true)
    end
  end
end

class DeleteMemoryTool < MCP::Tool
  description "指定 ID の記憶を削除する"

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

class MemoryStatsTool < MCP::Tool
  description "記憶 DB の統計情報（総件数・source 別・最古/最新日時）を返す"

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

# エントリポイント（直接実行時のみ起動）
if __FILE__ == $0
  store = MemoryStore.new(DB_PATH)
  server = MCP::Server.new(
    name: "long-term-memory",
    version: "1.0.0",
    tools: [SearchMemoryTool, StoreMemoryTool, ListMemoriesTool, DeleteMemoryTool, MemoryStatsTool],
    server_context: { memory_store: store }
  )
  transport = MCP::Server::Transports::StdioTransport.new(server)
  transport.open
end
