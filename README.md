# long-term-memory

Claude Code / Claude Desktop のやりとりを SQLite + ベクトル DB に長期保存し、MCP ツール経由で検索・参照できるようにするシステム。

**特徴:**
- Ruby 製
- SQLite FTS5（trigram）+ sqlite-vec による日本語対応ハイブリッド検索
- RRF融合 + 時間減衰スコアリング
- 日本語特化埋め込みモデル `mochiya98/ruri-v3-310m-onnx`（ONNX, 768次元）
- MCP サーバー（3ツール: 書き込み専用）で Claude Code / Claude Desktop から保存・削除・統計操作
- 読み取りは **chiebukuro-mcp** に `memory.db` を登録して使う（推奨: DB名 `long_term_memory`）
- Claude Code PreToolUse(Skill) hook でスキル呼び出し前に関連記憶を自動注入
- 複数 Mac 間の記憶を iCloud Drive 経由で同期（NDJSON dump/merge）

---

## 要件

- Ruby 4.0.1+
- Bundler

---

## セットアップ

新しい Mac または `git pull` 後に呼び出す:

```
/long-term-memory-register
```

gems インストール・テスト・PreToolUse(Skill) hook の `~/.claude/settings.local.json` へのマージ・Claude Desktop MCP 登録をすべてカバーする。

---

## 保存ポリシー

long-term-memory は **hook による自動キャプチャを行わない**。保存は MCP ツール（`long_term_memory_store`）経由で明示的に行う方針。ノイズを溜め込むより、残すべき記憶を意識的に選ぶ。

過去には Stop hook（セッション自動保存）、PostToolUse hook（ツール操作キャプチャ）、PreToolUse hook（スキル名で記憶を事前検索）を備えていたが、いずれも削除済み。セッション保存が必要なら [claude-session-saver-mcp](https://github.com/bash0C7/claude-session-saver-mcp) を使う。

---

## Claude Code MCP サーバー設定

`.claude/settings.json` に設定済み。MCP ツールが Claude Code から利用できる。

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

再起動後に以下の3ツール（書き込み専用）が使えるようになる:

| ツール名 | 説明 |
|---|---|
| `long_term_memory_store` | 記憶を手動保存 |
| `long_term_memory_delete` | 指定 ID の記憶を削除 |
| `long_term_memory_stats` | DB の統計情報 |

**読み取り（検索・一覧・取得）は chiebukuro-mcp を使う。**
`memory.db` を chiebukuro-mcp の `chiebukuro.json` に登録することで、
`chiebukuro_query_<db名>` / `chiebukuro_semantic_search_<db名>` ツールが自動生成される。
推奨 DB 名: `long_term_memory`（→ `chiebukuro_query_long_term_memory` 等）

---

## 複数 Mac 間の同期

iCloud Drive を経由した分散記憶スタイルの同期（各 Mac が独自の記憶を持ち、相互に取り込む）。

```
# 各 Mac でそれぞれ dump
/long-term-memory-dump

# 全台 dump 完了後、各 Mac でそれぞれ sync
/long-term-memory-sync
```

- dump 先: `~/Library/Mobile Documents/com~apple~CloudDocs/chiebukuro-mcp/dump/long-term-memory/`
- dump: `{hostname}_{timestamp}.ndjson` 形式で iCloud Drive へ書き出し
- sync: iCloud Drive 上の各ホスト最新ファイルを取り込み（`content_hash` による冪等処理で重複スキップ）
- 自 Mac 分を再取り込みしても安全（ゼロからの再構築に対応）

---

## 初回 Obsidian vault 取り込み

```bash
bundle exec ruby scripts/ingest_directory.rb ~/Documents/ObsidianVault \
  --source obsidian \
  --project my-vault
```

詳細は `/long-term-memory-ingest-vault` スキルを参照。

---

## skills（メンテナンス用スキル）

Claude Code のチャットでスキルを呼び出してメンテナンス操作を実行できる。
すべて `long-term-memory-` prefix 付き（タブ補完対応）。

| スキル | 用途 |
|---|---|
| `/long-term-memory-maintenance` | 何をしたいか伝えると適切なスキルに誘導（オーケストレーター） |
| `/long-term-memory-register` | 新 Mac セットアップ — gems・MCP 登録 |
| `/long-term-memory-stats` | 統計・健全性チェック・チューニング確認 |
| `/long-term-memory-search` | FTS5 + ベクトル + RRF スコア付き検索 |
| `/long-term-memory-cleanup` | 不要記憶の特定・削除ワークフロー |
| `/long-term-memory-backup` | バックアップ・リストア・古いバックアップ整理 |
| `/long-term-memory-ingest-vault` | ディレクトリ一括取り込み（Obsidian vault・コードリポジトリ等） |
| `/long-term-memory-rebuild-embeddings` | モデル変更後の全件再ベクトル化 |
| `/long-term-memory-migrate` | DB スキーマのマイグレーション |
| `/long-term-memory-dump` | 複数Mac同期用 — iCloud へ NDJSON dump |
| `/long-term-memory-sync` | 複数Mac同期用 — iCloud dump を取り込み |

---

## ディレクトリ構成

```
long-term-memory/
├── lib/
│   ├── embedder.rb             # informers ONNX 埋め込み（ruri-v3-310m-onnx, 768次元）
│   └── memory_store.rb         # SQLite DB 操作（FTS5 + sqlite-vec + ハイブリッド検索）
├── scripts/
│   ├── start_mcp.sh            # Claude Desktop / Claude Code 起動用シェルスクリプト
│   ├── mcp_server.rb           # MCP サーバー（3ツール: Store/Delete/Stats）
│   ├── ingest_directory.rb     # ディレクトリ一括取り込み CLI
│   ├── rebuild_embeddings.rb   # 全レコード再ベクトル化
│   ├── dump_memories.rb        # DB を iCloud へ NDJSON export（複数Mac同期用）
│   ├── merge_memories.rb       # iCloud dump を DB へ取り込み（複数Mac同期用）
│   └── analyze_memories.rb     # コサイン類似度で類似・重複記憶を検出
├── test/
│   ├── test_helper.rb
│   ├── test_memory_store.rb
│   ├── test_mcp_server.rb
│   ├── test_ingest_directory.rb
│   ├── test_rebuild_embeddings.rb
│   ├── test_dump_memories.rb
│   ├── test_merge_memories.rb
│   ├── test_analyze_memories.rb
│   ├── test_embedder.rb
│   └── test_search.rb
├── db/
│   └── .gitkeep                # memory.db は .gitignore 対象
├── .claude/
│   ├── settings.json           # Claude Code MCP サーバー設定
│   └── skills/                 # メンテナンス用スキル群（ディレクトリ形式）
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
