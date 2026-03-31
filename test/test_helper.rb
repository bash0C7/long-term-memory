require "test/unit"
require "sqlite3"
require "sqlite_vec"
require_relative "../lib/embedder"
require_relative "../lib/memory_store"

# テスト用スタブ埋め込み器。モデルロードを省いて高速化する
class StubEmbedder
  VECTOR_SIZE = Embedder::VECTOR_SIZE

  def embed(text)
    # テキストのハッシュ値から決定論的なベクトルを生成
    seed = text.each_char.each_with_index.sum { |c, i| c.ord * (i + 1) }
    Array.new(VECTOR_SIZE) { |i| Math.sin(seed + i) }
  end
end
