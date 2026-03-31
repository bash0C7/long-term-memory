# long-term-memory

Claude Code / Claude Desktop のやりとりを SQLite + ベクトル DB に長期保存し、MCP ツール経由で検索・参照できるようにするシステム。

**特徴:**
- フルRuby（Python不使用）
- SQLite FTS5（trigram）+ sqlite-vec による日本語対応ハイブリッド検索
- RRF融合 + 時間減衰スコアリング
- 日本語特化埋め込みモデル `mochiya98/ruri-v3-310m-onnx`（ONNX, 768次元）
- MCP サーバー（5ツール）で Claude Code / Claude Desktop から透過的に利用
- Claude Code Stop hook でセッションを自動キャプチャ

---

## 要件

- Ruby 4.0.1+
- Bundler

---

## セットアップ

### 1. gems インストール

```bash
cd /path/to/long-term-memory
bundle install
```

### 2. DB ディレクトリ確認

```bash
ls db/   # .gitkeep があればOK
```

DB ファイル（`db/memory.db`）は初回アクセス時に自動生成される。

### 3. テスト実行（確認）

```bash
bundle exec ruby test/test_memory_store.rb
bundle exec ruby test/test_mcp_server.rb
bundle exec ruby test/test_capture_session.rb
bundle exec ruby test/test_ingest_directory.rb
bundle exec ruby test/test_rebuild_embeddings.rb
```

---

## Claude Code Stop hook 設定

セッション終了時に自動で記憶を保存する。`.claude/settings.json` に設定済み。

```json
{
  "hooks": {
    "Stop": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "cd /path/to/long-term-memory && bundle exec ruby scripts/capture_session.rb"
      }]
    }]
  }
}
```

**注意:** `cwd` のパスをこのリポジトリの実際のパスに合わせること。

---

## Claude Desktop MCP サーバー設定

`~/Library/Application Support/Claude/claude_desktop_config.json` に追加:

```json
{
  "mcpServers": {
    "long-term-memory": {
      "command": "bundle",
      "args": ["exec", "ruby", "scripts/mcp_server.rb"],
      "cwd": "/path/to/long-term-memory"
    }
  }
}
```

再起動後に以下の5ツールが使えるようになる:

| ツール名 | 説明 |
|---|---|
| `search_memory_tool` | ハイブリッド検索（FTS5 + ベクトル + RRF） |
| `store_memory_tool` | 記憶を手動保存（Claude Desktop 用） |
| `list_memories_tool` | 最近の記憶を一覧表示 |
| `delete_memory_tool` | 指定 ID の記憶を削除 |
| `memory_stats_tool` | DB の統計情報 |

---

## 初回 Obsidian vault 取り込み

過去のノートを一括インポートする:

```bash
bundle exec ruby scripts/ingest_directory.rb ~/Documents/ObsidianVault \
  --source obsidian \
  --project my-vault
```

詳細は `.claude/skills/ingest-vault.md` を参照。

---

## skills（サブエージェント）一覧

Claude Code のチャットで `/memory-*` スキルを呼び出してメンテナンス操作を実行できる。

### `ingest-vault`
ディレクトリの一括取り込み。Obsidian vault・コードリポジトリなどのテキストファイルを DB に保存する。

```
/ingest-vault
```

### `memory-search`
長期記憶を検索する。FTS5 + ベクトル + RRF スコア付きで結果を確認する。

```
/memory-search
```

### `memory-cleanup`
不要な記憶を特定して削除する。source 別・project 別の一覧表示 → 削除のワークフロー。

```
/memory-cleanup
```

### `memory-backup`
DB のバックアップ作成・リストア・古いバックアップの整理。

```
/memory-backup
```

### `rebuild-embeddings`
埋め込みモデル変更後に全レコードのベクトルを再構築する。

```
/rebuild-embeddings
```

### `memory-stats`
DB の統計・健全性チェック・検索スコアのチューニング確認。

```
/memory-stats
```

### `memory-maintenance`
上記すべての操作をカバーするリファレンス。個別スキルがない操作はここを参照。

```
/memory-maintenance
```

---

## ディレクトリ構成

```
long-term-memory/
├── lib/
│   ├── embedder.rb        # informers ONNX 埋め込み（ruri-v3-310m-onnx, 768次元）
│   └── memory_store.rb    # SQLite DB 操作（FTS5 + sqlite-vec + ハイブリッド検索）
├── scripts/
│   ├── mcp_server.rb      # MCP サーバー（5ツール）
│   ├── capture_session.rb # Claude Code Stop hook ハンドラ
│   ├── ingest_directory.rb# ディレクトリ一括取り込み CLI
│   └── rebuild_embeddings.rb # 全レコード再ベクトル化
├── test/
│   ├── test_helper.rb
│   ├── test_memory_store.rb
│   ├── test_mcp_server.rb
│   ├── test_capture_session.rb
│   ├── test_ingest_directory.rb
│   └── test_rebuild_embeddings.rb
├── db/
│   └── .gitkeep           # memory.db はgitignore対象
├── .claude/
│   ├── settings.json      # Stop hook + MCP サーバー設定
│   └── skills/            # メンテナンス用スキル
└── Gemfile
```

---

## 検索の仕組み

1. **FTS5 trigram** でクエリに部分一致するレコードを取得（日本語2文字以上に対応）
2. **sqlite-vec** でクエリの埋め込みに近いベクトルを取得
3. **RRF（Reciprocal Rank Fusion）** で両結果を融合: `score = Σ 1/(60 + rank + 1)`
4. **時間減衰** を適用: `score × 0.5^(age_days / 30)`（30日で半減）
5. スコア降順でソートして返す
