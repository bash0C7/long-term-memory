# test/test_skill_context.rb
require_relative "test_helper"
require_relative "../scripts/skill_context"

class TestSkillContext < Test::Unit::TestCase
  def setup
    @store = MemoryStore.new(":memory:", embedder: StubEmbedder.new)
    @store.store(
      content: "dotfiles-status スキルで stow のシンボリックリンク状態を確認した。bundle パッケージが未適用だった。",
      source: "claude_code",
      project: "dotfiles",
      tags: ["dotfiles-status"]
    )
  end

  def teardown
    @store.close
  end

  def test_returns_nil_for_non_skill_tool
    input = JSON.generate({ "tool_name" => "Bash", "tool_input" => { "command" => "ls" } })
    assert_nil SkillContext.run(input, store: @store)
  end

  def test_returns_nil_when_tool_input_missing
    input = JSON.generate({ "tool_name" => "Skill" })
    assert_nil SkillContext.run(input, store: @store)
  end

  def test_returns_nil_when_skill_name_empty
    input = JSON.generate({ "tool_name" => "Skill", "tool_input" => { "skill" => "" } })
    assert_nil SkillContext.run(input, store: @store)
  end

  def test_searches_with_skill_name_and_returns_output
    # MemoryStore の FTS5 ハイフン問題と :memory: vec0 KNN 問題を回避するため
    # SkillContext の動作（クエリ転送・フォーマット）のみを検証するスタブを使う
    stub_store = Class.new do
      def search(query:, limit:)
        [{ "summary" => "dotfiles-status スキルでシンボリックリンクを確認", "created_at" => "2026-01-15T10:00:00+09:00" }]
      end
    end.new

    input = JSON.generate({ "tool_name" => "Skill", "tool_input" => { "skill" => "dotfiles-status" } })
    result = SkillContext.run(input, store: stub_store)
    assert_not_nil result
    assert_true result.include?("dotfiles-status")
  end

  def test_returns_nil_when_no_matching_memories
    input = JSON.generate({ "tool_name" => "Skill", "tool_input" => { "skill" => "zzz-no-match-xyz" } })
    assert_nil SkillContext.run(input, store: @store)
  end

  def test_format_output_includes_header_and_summary
    results = [
      { "summary" => "テスト用サマリ", "created_at" => "2026-03-15T10:00:00+09:00" }
    ]
    output = SkillContext.format_output("dotfiles-status", results)
    assert_true output.include?("long-term-memory: dotfiles-status")
    assert_true output.include?("2026-03-15")
    assert_true output.include?("テスト用サマリ")
  end

  def test_format_output_shows_result_count
    results = [
      { "summary" => "summary1", "created_at" => "2026-03-15T10:00:00+09:00" },
      { "summary" => "summary2", "created_at" => "2026-03-14T10:00:00+09:00" }
    ]
    output = SkillContext.format_output("dotfiles-add", results)
    assert_true output.include?("2件")
  end
end
