---
name: long-term-memory-search
description: 長期記憶 DB をハイブリッド検索（FTS5 + ベクトル + RRF + 時間減衰）で照会する
---

# 長期記憶検索

FTS5 全文検索 + ベクトル検索を RRF で融合し、時間減衰スコアで並べ替えて返す。

## 基本検索

```bash
cd /Users/bash/dev/src/github.com/bash0C7/long-term-memory
bundle exec ruby -e "
require_relative 'lib/memory_store'
s = MemoryStore.new('db/memory.db')
s.search(query: 'QUERY_HERE', limit: 10).each do |r|
  puts \"[#{r['id']}] score=#{r['score'].round(4)} source=#{r['source']} project=#{r['project']}\"
  puts \"  #{r['content'][0, 120]}\"
  puts
end
s.close
"
```

## source で絞り込む

```bash
bundle exec ruby -e "
require_relative 'lib/memory_store'
s = MemoryStore.new('db/memory.db')
s.search(query: 'QUERY_HERE', scope: 'obsidian', limit: 5).each do |r|
  puts \"[#{r['id']}] #{r['content'][0, 120]}\"
end
s.close
"
```

## project で絞り込む

```bash
bundle exec ruby -e "
require_relative 'lib/memory_store'
s = MemoryStore.new('db/memory.db')
s.search(query: 'QUERY_HERE', project: 'my-vault', limit: 5).each do |r|
  puts \"[#{r['id']}] #{r['content'][0, 120]}\"
end
s.close
"
```

## 検索のコツ

- **日本語**: 3文字以上のフレーズが FTS5 trigram にヒットしやすい
- **scope ワード**: `obsidian`・`claude_code` などをクエリに含めると暗黙の絞り込みになる
- **プロジェクト名**: クエリにプロジェクト名を入れると関連記憶が浮上しやすい
- **score**: 0.01 以上が有意なヒット目安。0.001 以下は弱い関連

## MCP ツール経由（Claude Desktop / Claude Code）

Claude Desktop や Claude Code の MCP サーバー経由でも同じ検索が使える:
- ツール名: `search_memory_tool`
- パラメータ: `query`, `scope`（省略可）, `project`（省略可）, `limit`（省略可）
