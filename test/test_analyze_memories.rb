require_relative "test_helper"
require_relative "../scripts/analyze_memories"

# 常に同一ベクトルを返す — 異なるコンテンツでも類似グループ検出テストに使う
class ConstantEmbedder
  VECTOR_SIZE = StubEmbedder::VECTOR_SIZE
  def embed(_text)
    [1.0] + [0.0] * (VECTOR_SIZE - 1)
  end
end

class TestAnalyzeMemories < Test::Unit::TestCase
  def setup
    @store = MemoryStore.new(":memory:", embedder: StubEmbedder.new)
    # 類似検出テスト用: 常に同一ベクトルを返すstore
    @sim_store = MemoryStore.new(":memory:", embedder: ConstantEmbedder.new)
  end

  def teardown
    @store.close
    @sim_store.close
  end

  def store_with_vec(content, source: "test", store: nil)
    (store || @store).store(content: content, source: source, project: "test")
  end

  def test_cosine_identical_vectors
    v = [1.0, 0.0, 0.0]
    assert_in_delta 1.0, AnalyzeMemories.cosine(v, v), 0.0001
  end

  def test_cosine_orthogonal_vectors
    a = [1.0, 0.0, 0.0]
    b = [0.0, 1.0, 0.0]
    assert_in_delta 0.0, AnalyzeMemories.cosine(a, b), 0.0001
  end

  def test_cosine_opposite_vectors
    a = [1.0, 0.0]
    b = [-1.0, 0.0]
    assert_in_delta(-1.0, AnalyzeMemories.cosine(a, b), 0.0001)
  end

  def test_find_groups_detects_similar_pair
    # ConstantEmbedder で2件 → cosine=1.0 → グループ化される
    store_with_vec("content alpha for similarity test", store: @sim_store)
    store_with_vec("content beta for similarity test", store: @sim_store)
    result = AnalyzeMemories.find_groups(@sim_store.db, threshold: 0.99)
    assert result[:groups].size >= 1, "同一ベクトルペアがグループ化されること"
  end

  def test_find_groups_ignores_dissimilar
    # StubEmbedder は異なるテキストで異なるベクトル → 類似なし
    store_with_vec("ruby programming language syntax")
    store_with_vec("cooking recipe tomato pasta dinner")
    result = AnalyzeMemories.find_groups(@store.db, threshold: 0.95)
    assert_equal 0, result[:groups].size, "無関係な記憶はグループ化されないこと"
  end

  def test_find_groups_returns_stats
    store_with_vec("test content one about ruby")
    store_with_vec("test content two about python")
    result = AnalyzeMemories.find_groups(@store.db, threshold: 0.95)
    assert result.key?(:total)
    assert result.key?(:groups)
    assert result.key?(:elapsed_ms)
  end

  def test_find_groups_groups_three_similar
    # ConstantEmbedder で3件異なるコンテンツ → cosine=1.0 → 1グループ
    store_with_vec("content one for three-way grouping test", store: @sim_store)
    store_with_vec("content two for three-way grouping test", store: @sim_store)
    store_with_vec("content three for three-way grouping test", store: @sim_store)
    result = AnalyzeMemories.find_groups(@sim_store.db, threshold: 0.99)
    assert result[:groups].any? { |g| g[:members].size >= 3 }, "3件が1グループにまとまること"
  end
end
