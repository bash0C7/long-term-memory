require_relative "test_helper"
require_relative "../lib/keyword_extractor"

class TestKeywordExtractor < Test::Unit::TestCase
  def test_extract_returns_array_of_strings
    keywords = KeywordExtractor.extract("Ruby programming language")
    assert_instance_of Array, keywords
    assert keywords.all? { |k| k.is_a?(String) }
  end

  def test_extract_returns_at_most_6_keywords
    text = "Ruby blocks procs lambdas closures iterators methods objects classes modules inheritance"
    keywords = KeywordExtractor.extract(text)
    assert keywords.length <= 6
  end

  def test_extract_english_keywords_present
    text = "Ruby blocks and procs and lambdas are important in Ruby programming"
    keywords = KeywordExtractor.extract(text)
    assert keywords.include?("Ruby") || keywords.include?("ruby")
  end

  def test_extract_filters_english_stop_words
    text = "the a an is are was were be been for in on at to of and or but not"
    keywords = KeywordExtractor.extract(text)
    stop = %w[the a an is are was were be been for in on at to of and or but not]
    assert keywords.none? { |k| stop.include?(k.downcase) }
  end

  def test_extract_japanese_keywords
    text = "RubyのブロックはProcとlambdaの違いを理解することが重要です"
    keywords = KeywordExtractor.extract(text)
    assert keywords.length >= 1
    has_cjk = keywords.any? { |k| k.match?(/[ぁ-んァ-ヶ一-龥]/) }
    has_ascii = keywords.any? { |k| k.match?(/Ruby|Proc|lambda/i) }
    assert has_cjk || has_ascii
  end

  def test_extract_removes_urls
    text = "Check https://example.com/path for more Ruby information about blocks and procs"
    keywords = KeywordExtractor.extract(text)
    assert keywords.none? { |k| k.include?("http") }
    assert keywords.none? { |k| k.include?("example.com") }
  end

  def test_summarize_returns_full_text_when_short
    text = "short text"
    assert_equal "short text", KeywordExtractor.summarize(text)
  end

  def test_summarize_truncates_at_200_chars
    text = "a" * 300
    assert_equal 200, KeywordExtractor.summarize(text).length
  end

  def test_summarize_exactly_200_chars
    text = "b" * 200
    assert_equal text, KeywordExtractor.summarize(text)
  end

  def test_extract_empty_text_returns_empty_array
    assert_equal [], KeywordExtractor.extract("")
  end
end
