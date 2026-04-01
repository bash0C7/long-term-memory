# lib/keyword_extractor.rb
module KeywordExtractor
  SUMMARY_LENGTH = 200
  MAX_KEYWORDS   = 6

  ENGLISH_STOP_WORDS = %w[
    a an the is are was were be been being have has had do does did
    will would could should may might shall can for in on at to of
    and or but not with from by about as into through during
    this that these those it its we they he she you i me my
    what which who whom where when why how all each every more most
    other some such no nor so yet both either neither once here there
  ].freeze

  JAPANESE_STOP_WORDS = %w[
    する こと もの ため なる ある いる れる られ てい につ いて
    とし てに より おい にお けるに また さら ただ なお
    です ます した ない して いう から まで よる よう
  ].freeze

  STOP_WORDS = (ENGLISH_STOP_WORDS + JAPANESE_STOP_WORDS).map(&:downcase).to_set.freeze

  def self.summarize(text)
    text.to_s[0, SUMMARY_LENGTH] || ""
  end

  def self.extract(text)
    cleaned  = clean(text.to_s)
    tokens   = tokenize(cleaned)
    filtered = filter(tokens)
    score(filtered).first(MAX_KEYWORDS)
  end

  def self.clean(text)
    text
      .gsub(%r{https?://\S+}, " ")
      .gsub(/[「」『』【】〔〕（）\(\)\[\]\{\}<>]/, " ")
      .gsub(/[、。，．！？!?\r\n]/, " ")
      .gsub(/\s+/, " ")
      .strip
  end

  def self.tokenize(text)
    tokens = []
    text.scan(/[a-zA-Z][a-zA-Z0-9_]*/).each do |word|
      tokens << word if word.length >= 2
    end
    text.scan(/[\p{Hiragana}\p{Katakana}\p{Han}]+/).each do |run|
      run.chars.each_cons(2) { |a, b| tokens << (a + b) }
    end
    tokens
  end

  def self.filter(tokens)
    tokens.reject { |t| STOP_WORDS.include?(t.downcase) }
          .reject { |t| t.length < 2 }
  end

  def self.score(tokens)
    freq     = Hash.new(0)
    case_map = {}
    tokens.each do |t|
      key = t.downcase
      freq[key] += 1
      case_map[key] ||= t
    end
    freq.sort_by { |_, count| -count }.map { |key, _| case_map[key] }
  end

  private_class_method :clean, :tokenize, :filter, :score
end
