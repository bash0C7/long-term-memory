# Long-Term Memory System Design

**Date:** 2026-03-31  
**Status:** Approved

## Overview

Claude Code および Claude Desktop のやりとりを SQLite + ベクトル検索で長期記憶化するシステム。
単一の SQLite DB にメタデータでドメイン管理し、MCP サーバー経由で検索・保存を提供する。

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Claude Code (Hook: Stop)                           │
│    → scripts/capture_session.rb                     │
│        → 会話サマリ + メタデータ → memory.db        │
└─────────────────────────────────────────────────────┘
                        ↓ write
┌─────────────────────────────────────────────────────┐
│  memory.db (SQLite)                                 │
│    ├── memories (本文 + メタデータ)                  │
│    ├── memories_fts (FTS5 仮想テーブル)              │
│    └── memories_vec (sqlite-vec 仮想テーブル)        │
└─────────────────────────────────────────────────────┘
                        ↑ read/write
┌─────────────────────────────────────────────────────┐
│  MCP Server (scripts/mcp_server.rb)                 │
│    ├── search_memory(query, scope?, project?, limit?)│
│    └── store_memory(content, source, project?, tags?)│
└─────────────────────────────────────────────────────┘
         ↑                          ↑
  Claude Code                Claude Desktop
  (search_memory)            (search_memory + store_memory)
```

### コンポーネント職責

| コンポーネント | 責務 |
|---|---|
| `scripts/capture_session.rb` | Claude Code Stop hook から呼ばれ、会話を memory.db に書き込む |
| `scripts/mcp_server.rb` | MCP stdio サーバー。search/store ツールを公開 |
| `lib/embedder.rb` | informers gem (ONNX) でテキスト→float ベクトル変換（ruri-v3-310m） |
| `lib/memory_store.rb` | DB 読み書きロジック。FTS5 + sqlite-vec + RRF 融合 |
| `db/memory.db` | 全記憶の保存先（1 ファイル、gitignore） |

---

## Technology Stack

| 項目 | 選択 | 理由 |
|---|---|---|
| 言語 | Ruby 4.0.1 | 指定 |
| DB | SQLite3 | 軽量・シングルファイル・FTS5・sqlite-vec 対応 |
| ベクトル検索 | sqlite-vec extension | SQLite 内でベクトル類似検索 |
| 全文検索 | SQLite FTS5 | sqlite3 gem 内蔵 |
| 埋め込み生成 | informers gem (ONNX) + `cl-nagoya/ruri-v3-310m` | Python 不要・ローカル・日本語特化・sui-memory でも採用実績あり |
| MCP | modelcontextprotocol/ruby-sdk (`mcp` gem) | 公式 SDK |
| テスト | test-unit gem (xUnit スタイル) | 指定 |
| 依存管理 | Bundler | プロジェクト配下で管理 |

**Python 完全禁止。シェルスクリプトは OK。**

---

## Schema

```sql
-- 本体テーブル
CREATE TABLE memories (
  id          INTEGER PRIMARY KEY,
  content     TEXT    NOT NULL,
  source      TEXT    NOT NULL,   -- 'claude_code' | 'claude_desktop' | 'obsidian'
  project     TEXT,               -- リポジトリパスまたは名前（省略可）
  tags        TEXT,               -- JSON 配列文字列 例: '["ruby","mcp","設計"]'
  created_at  TEXT    NOT NULL    -- ISO8601 例: '2026-03-31T13:00:00+09:00'
);

-- 全文検索（FTS5）
CREATE VIRTUAL TABLE memories_fts USING fts5(
  content,
  tags,
  content='memories',
  content_rowid='id'
);

-- ベクトル検索（sqlite-vec）
-- 次元数は ruri-v3-310m のロード時に確認して確定（1024 想定）
CREATE VIRTUAL TABLE memories_vec USING vec0(
  memory_id INTEGER PRIMARY KEY,
  embedding FLOAT[1024]
);
```

### メタデータ設計の意図

- `source` — 粗いドメイン分離。検索時に `scope:` パラメータとして機能
- `project` — リポジトリ・プロジェクト単位の絞り込み
- `tags` — 自由なキーワード。クエリ文中の scope ワードが FTS5 でここにヒットする

---

## Search Algorithm

1. **FTS5 全文検索** — query の語句でキーワードマッチ
2. **sqlite-vec ベクトル検索** — query を埋め込みベクトル化して近傍探索
3. **RRF 融合** — Reciprocal Rank Fusion で両結果をスコア統合
4. **時間減衰** — 30 日半減期で直近の記憶を優先
5. **scope/project フィルタ** — 指定があれば WHERE 句でフィルタ後に検索

```
rrf_score(doc) = Σ 1 / (k + rank_i(doc))   # k=60, i=fts5/vec の各ランク
time_decay(created_at) = 0.5 ** (age_days / 30.0)
final_score = rrf_score * time_decay
```

---

## MCP Tools

### `search_memory`

Claude Code / Claude Desktop から呼ぶ検索ツール。

| パラメータ | 型 | 必須 | 説明 |
|---|---|---|---|
| `query` | string | ✓ | 検索クエリ |
| `scope` | string | — | source 絞り込み: `claude_code` \| `claude_desktop` \| `obsidian` |
| `project` | string | — | プロジェクト名絞り込み |
| `limit` | integer | — | 最大件数（デフォルト 5） |

返却: 上位 N 件の `content`, `source`, `project`, `tags`, `created_at`, `score`

### `store_memory`

Claude Desktop からの手動保存ツール。

| パラメータ | 型 | 必須 | 説明 |
|---|---|---|---|
| `content` | string | ✓ | 保存するテキスト |
| `source` | string | ✓ | `claude_desktop` \| `obsidian` など |
| `project` | string | — | プロジェクト名 |
| `tags` | array[string] | — | タグ |

---

## Capture Mechanism (Claude Code)

Claude Code の **Stop hook** で `scripts/capture_session.rb` を呼び出す。

`.claude/settings.json`:
```json
{
  "hooks": {
    "Stop": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "bundle exec ruby /Users/bash/dev/src/github.com/bash0C7/long-term-memory/scripts/capture_session.rb"
      }]
    }]
  }
}
```

`capture_session.rb` は stdin から Claude Code が渡す JSON（会話サマリ・ツール使用履歴）を受け取り、`MemoryStore` 経由で DB に保存する。source は `claude_code`、project は `cwd` から取得。

**Stop hook の JSON 仕様はこのプロジェクト自身の `.claude/settings.json` に hook を設定して実験的に確認する。**

---

## Testing Strategy (TDD, test-unit xUnit)

### ファイル構成

```
test/
  test_helper.rb         # インメモリ DB 共通セットアップ
  test_embedder.rb       # Embedder 単体テスト
  test_memory_store.rb   # DB 読み書き・スキーマテスト
  test_search.rb         # FTS5/vec 検索・RRF ロジックテスト
  test_mcp_server.rb     # ツール呼び出し統合テスト
  test_capture_session.rb # Stop hook スクリプトテスト
```

### 原則

- **Red → Green → Refactor** の順で実装
- テストは `:memory:` SQLite を使用し、外部依存なし・高速
- `TestCase` サブクラス + `setup` / `teardown` で状態を分離
- Embedder は実際のモデルロードをスタブ化してユニットテストを高速に保つ
- 統合テストのみ実モデルを使用

---

## Directory Structure

```
long-term-memory/
├── .gitignore
├── Gemfile
├── Gemfile.lock
├── lib/
│   ├── embedder.rb          # informers ONNX ラッパー
│   └── memory_store.rb      # DB 読み書き・検索ロジック
├── scripts/
│   ├── mcp_server.rb        # MCP stdio サーバー
│   └── capture_session.rb   # Claude Code Stop hook エントリポイント
├── test/
│   ├── test_helper.rb
│   ├── test_embedder.rb
│   ├── test_memory_store.rb
│   ├── test_search.rb
│   ├── test_mcp_server.rb
│   └── test_capture_session.rb
├── db/                      # gitignore 対象
│   └── memory.db
└── docs/
    └── superpowers/
        └── specs/
            └── 2026-03-31-long-term-memory-design.md
```

---

## .gitignore

```
db/memory.db
db/*.db
```

---

## Gemfile (予定)

```ruby
source "https://rubygems.org"

ruby "4.0.1"

gem "sqlite3"
gem "sqlite-vec"          # 0.1.9.alpha.1
gem "mcp"
gem "informers"
gem "test-unit", group: :test
```

---

## Open Questions / Future Work

- `ruri-v3-310m` の実際のベクトル次元数を実装初期に確認し、`FLOAT[1024]` を確定させる
- Obsidian Vault の Markdown ファイルをバッチ取り込みするスクリプト（将来対応）
- sqlite-vec 0.1.9.alpha.1 はアルファ版。安定版リリース後に要バージョンアップ
