# long-term-memory ブラッシュアップ設計書

Date: 2026-04-01

## 背景・課題

MCP経由で運用中に以下の問題が発生:

1. **トークン超過エラー**: `search`/`list` が全文コンテンツを返すため69,265文字を超えMCPエラーになる
2. **ツール名の識別困難**: `search_memory_tool` 等のツール名に `long_term_memory_` プレフィックスがなく、Claude が「長期記憶」ツールと認識しにくい

## 変更方針

### 1. DBスキーマ変更

`memories` テーブルに2カラム追加:

```sql
summary   TEXT  -- 全文の先頭200文字
keywords  TEXT  -- JSON配列: ["Ruby", "ブロック", "クロージャ", ...]
```

- `store` 時に自動生成
- 既存レコードはマイグレーションスクリプトで一括処理

### 2. キーワード抽出ロジック (`lib/keyword_extractor.rb`)

純Ruby実装（外部gem不要）:

- **前処理**: 記号・URL除去、日本語/英語トークン化
  - 英語: 空白分割 → 3文字以上 → ストップワード除去
  - 日本語: 漢字・ひらがな・カタカナの2文字n-gram
- **スコアリング**: 出現頻度（TF）× 文書内ユニーク率近似
- **出力**: 上位6キーワードをJSON配列で `keywords` カラムに保存
- `summary` は全文先頭200文字

### 3. ベクトル生成の変更

```ruby
# 変更前
embedding = embedder.embed(content)  # 全文

# 変更後
embed_text = "#{summary} #{keywords.join(' ')}"
embedding = embedder.embed(embed_text)  # summary + keywords
```

**FTS5は全文 `content` のまま維持**（ハイブリッド差別化）:
- FTS5 = 表記一致（固有名詞・コード・URL等）
- ベクトル = 意味・概念の近傍（表記ゆれ・同義語等）

### 4. ツール名リネーム

| 変更前 | 変更後 |
|---|---|
| `search_memory_tool` | `long_term_memory_search` |
| `store_memory_tool` | `long_term_memory_store` |
| `list_memories_tool` | `long_term_memory_list` |
| `delete_memory_tool` | `long_term_memory_delete` |
| `memory_stats_tool` | `long_term_memory_stats` |
| （新規） | `long_term_memory_get` |

Rubyクラス名も対応:
- `LongTermMemorySearch`, `LongTermMemoryStore`, `LongTermMemoryList`
- `LongTermMemoryDelete`, `LongTermMemoryStats`, `LongTermMemoryGet`

各ツールの description 冒頭に `【長期記憶】` を付与し、日本語でも確実に発動させる。

### 5. レスポンス形式変更

`search` / `list` はトークン節約のため `summary + keywords` を返す:

```json
[
  {
    "id": 63,
    "score": 0.016,
    "summary": "RubyのブロックはProcとlambdaの違いを理解することが...",
    "keywords": ["Ruby", "ブロック", "Proc", "lambda", "違い"],
    "source": "claude_code",
    "project": "my-app",
    "created_at": "2026-03-15T10:30:00+09:00"
  }
]
```

`content` 全文が必要な場合は `long_term_memory_get` で ID指定取得:

```json
{
  "id": 63,
  "content": "（全文）",
  "summary": "...",
  "keywords": [...],
  "source": "claude_code",
  "project": "my-app",
  "created_at": "..."
}
```

### 6. マイグレーション

`scripts/migrate_add_summary_keywords.rb`:
- `ALTER TABLE memories ADD COLUMN summary TEXT`
- `ALTER TABLE memories ADD COLUMN keywords TEXT`
- 全レコードを100件ずつバッチ処理してsummary/keywords生成
- `memories_vec` の embedding を `summary + keywords` で再生成・UPDATE
- **一度だけ手動実行**（自動実行なし）

### 7. メンテナンス skill 追加

`.claude/skills/long-term-memory-migrate.md`:
- マイグレーション手順
- 実行コマンド
- バックアップ・ロールバック手順

## ファイル変更一覧

| ファイル | 変更種別 |
|---|---|
| `lib/keyword_extractor.rb` | 新規作成 |
| `lib/memory_store.rb` | スキーマ追加・store/search/list変更 |
| `scripts/mcp_server.rb` | ツール名変更・Getツール追加 |
| `scripts/migrate_add_summary_keywords.rb` | 新規作成 |
| `.claude/skills/long-term-memory-migrate.md` | 新規作成 |
| `test/test_keyword_extractor.rb` | 新規作成 |
| `test/test_mcp_server.rb` | ツール名変更に追従 |
| `test/test_memory_store.rb` | summary/keywords検証追加 |

## テスト方針

- `KeywordExtractor` の単体テスト（英語・日本語・混在）
- `MemoryStore#store` で summary/keywords が生成されること
- `LongTermMemorySearch` のレスポンスに content が含まれないこと
- `LongTermMemoryGet` でcontent全文が取得できること
- マイグレーションスクリプトの実行後に既存レコードに summary/keywords が入ること
