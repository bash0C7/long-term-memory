# long-term-memory

Claude Code / Claude Desktop のやりとりを SQLite + ベクトル DB に長期保存し、MCP ツール経由で検索・参照できるようにするシステム。

**特徴:**
- Ruby 製
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
cd /Users/bash/dev/src/github.com/bash0C7/long-term-memory
bundle install
```

### 2. DB ディレクトリ確認

`db/.gitkeep` が存在すれば OK。`db/memory.db` は初回アクセス時に自動生成される。

### 3. テスト実行（動作確認）

```bash
bundle exec ruby test/test_memory_store.rb
bundle exec ruby test/test_mcp_server.rb
bundle exec ruby test/test_capture_session.rb
bundle exec ruby test/test_ingest_directory.rb
bundle exec ruby test/test_rebuild_embeddings.rb
```

---

## Claude Code Stop hook

`.claude/settings.json` に設定済み。セッション終了時に自動でキャプチャされる。

```json
{
  "hooks": {
    "Stop": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "cd /Users/bash/dev/src/github.com/bash0C7/long-term-memory && bundle exec ruby scripts/capture_session.rb"
      }]
    }]
  }
}
```

---

## Claude Desktop MCP サーバー設定

`~/Library/Application Support/Claude/claude_desktop_config.json` に追加済み:

```json
{
  "mcpServers": {
    "long-term-memory": {
      "command": "/Users/bash/dev/src/github.com/bash0C7/long-term-memory/scripts/start_mcp.sh"
    }
  }
}
```

`scripts/start_mcp.sh` で rbenv の絶対パスを使い PATH 依存を回避している。

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

```bash
bundle exec ruby scripts/ingest_directory.rb ~/Documents/ObsidianVault \
  --source obsidian \
  --project my-vault
```

詳細は `.claude/skills/ingest-vault.md` を参照。

---

## skills（メンテナンス用サブエージェント）

Claude Code のチャットでスキルを呼び出してメンテナンス操作を実行できる。

| スキル | 用途 |
|---|---|
| `/ingest-vault` | ディレクトリ一括取り込み（Obsidian vault・コードリポジトリ等） |
| `/memory-search` | FTS5 + ベクトル + RRF スコア付き検索 |
| `/memory-cleanup` | 不要記憶の特定・削除ワークフロー |
| `/memory-backup` | バックアップ・リストア・古いバックアップ整理 |
| `/rebuild-embeddings` | モデル変更後の全件再ベクトル化 |
| `/memory-stats` | 統計・健全性チェック・チューニング確認 |
| `/memory-maintenance` | 上記すべてのリファレンス |

---

## ディレクトリ構成

```
long-term-memory/
├── lib/
│   ├── embedder.rb             # informers ONNX 埋め込み（ruri-v3-310m-onnx, 768次元）
│   └── memory_store.rb         # SQLite DB 操作（FTS5 + sqlite-vec + ハイブリッド検索）
├── scripts/
│   ├── start_mcp.sh            # Claude Desktop 起動用シェルスクリプト
│   ├── mcp_server.rb           # MCP サーバー（5ツール）
│   ├── capture_session.rb      # Claude Code Stop hook ハンドラ
│   ├── ingest_directory.rb     # ディレクトリ一括取り込み CLI
│   └── rebuild_embeddings.rb   # 全レコード再ベクトル化
├── test/
│   ├── test_helper.rb
│   ├── test_memory_store.rb
│   ├── test_mcp_server.rb
│   ├── test_capture_session.rb
│   ├── test_ingest_directory.rb
│   └── test_rebuild_embeddings.rb
├── db/
│   └── .gitkeep                # memory.db は .gitignore 対象
├── .claude/
│   ├── settings.json           # Stop hook + MCP サーバー設定
│   └── skills/                 # メンテナンス用スキル群
└── Gemfile
```

---

## 検索の仕組み

1. **FTS5 trigram** でクエリに部分一致するレコードを取得（日本語3文字以上に対応）
2. **sqlite-vec** でクエリの埋め込みに近いベクトルを取得
3. **RRF（Reciprocal Rank Fusion）** で両結果を融合: `score = Σ 1/(60 + rank + 1)`
4. **時間減衰** を適用: `score × 0.5^(age_days / 30)`（30日で半減）
5. スコア降順でソートして返す

---

## 謝辞

sqlite-vec を使ったハイブリッド検索の実装にあたり、以下の記事を参考にしました。

- [sqlite-vec で作る全文検索×ベクトル検索ハイブリッドシステム](https://zenn.dev/noprogllama/articles/7c24b2c2410213) — noprogllama

---

## License

[MIT License](LICENSE) © 2026 Toshiaki "bash" KOSHIBA
