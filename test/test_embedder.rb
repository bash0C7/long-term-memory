require "test/unit"
require_relative "../lib/embedder"

class TestEmbedder < Test::Unit::TestCase
  def setup
    @embedder = Embedder.new
  end

  def test_embed_returns_float_array
    result = @embedder.embed("テスト文章です")
    assert_instance_of Array, result
    assert_equal Embedder::VECTOR_SIZE, result.size
    assert result.all? { |v| v.is_a?(Float) }, "全要素が Float であること"
  end

  def test_embed_different_texts_give_different_vectors
    v1 = @embedder.embed("りんご")
    v2 = @embedder.embed("コンピュータサイエンス")
    assert v1 != v2, "異なるテキストは異なるベクトルになること"
  end

  def test_vector_is_normalized
    v = @embedder.embed("正規化テスト")
    norm = Math.sqrt(v.sum { |x| x * x })
    assert_in_delta 1.0, norm, 0.01, "normalize: true なので L2ノルムが1に近いこと"
  end
end
