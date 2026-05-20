require File.expand_path('../../../test_helper', __FILE__)

class ForgejoWebhook::NoteBuilderTest < ActiveSupport::TestCase
  def setup
    @prev_format = Setting.text_formatting
    Setting.text_formatting = 'markdown'
  end

  def teardown
    Setting.text_formatting = @prev_format
  end

  def test_renders_full_message_as_markdown_blockquote
    commit = { 'sha' => 'a1b2c3d4abcdef', 'url' => 'https://example.com/commit/a1b2c3d4' }
    message = "feat: add thing\n\nDetailed body.\nSecond line.\n"
    note = ForgejoWebhook::NoteBuilder.new(message, commit, 'Author: Jane <jane@x.com>').call

    assert_includes note, 'Commit referenced this issue: @a1b2c3d4@'
    assert_includes note, 'https://example.com/commit/a1b2c3d4'
    assert_includes note, 'Author: Jane <jane@x.com>'
    assert_includes note, "> feat: add thing"
    assert_includes note, "> Detailed body."
    assert_includes note, "> Second line."
    refute note.end_with?("> \n"), 'no trailing blockquote line'
  end

  def test_omits_blockquote_when_message_blank
    note = ForgejoWebhook::NoteBuilder.new('', { 'sha' => 'aaaaaaaa' }, 'Author: Jane').call

    assert_includes note, 'Commit referenced this issue: @aaaaaaaa@'
    assert_includes note, 'Author: Jane'
    refute_includes note, '>'
  end

  def test_omits_author_line_when_attribution_nil
    note = ForgejoWebhook::NoteBuilder.new('msg', { 'sha' => 'aaaaaaaa' }, nil).call
    refute_includes note, 'Author:'
  end

  def test_omits_url_line_when_missing
    note = ForgejoWebhook::NoteBuilder.new('msg', { 'sha' => 'aaaaaaaa' }, nil).call
    refute_includes note, 'http'
  end

  def test_omits_sha_in_header_when_missing
    note = ForgejoWebhook::NoteBuilder.new('msg', {}, nil).call
    assert_equal 'Commit referenced this issue', note.lines.first.chomp
  end

  def test_preserves_blank_lines_within_message_body
    message = "subject\n\nparagraph 2"
    note = ForgejoWebhook::NoteBuilder.new(message, { 'sha' => 'aaaaaaaa' }, nil).call
    assert_includes note.lines, "> \n", "blank line in body should render as a bare `> ` line"
    assert_includes note, "> subject"
    assert_includes note, "> paragraph 2"
  end

  def test_nests_existing_blockquote_markers_in_body
    message = "> quoted line\nrest"
    note = ForgejoWebhook::NoteBuilder.new(message, { 'sha' => 'aaaaaaaa' }, nil).call
    assert_includes note, "> > quoted line"
    assert_includes note, "> rest"
  end

  def test_uses_markdown_blockquote_regardless_of_text_formatting_setting
    Setting.text_formatting = 'textile'

    message = "feat: add\n\nBody line."
    note = ForgejoWebhook::NoteBuilder.new(message, { 'sha' => 'aaaaaaaa' }, nil).call

    refute_match(/bq\.\./, note, "no leftover textile 'bq..' marker in note source")
    refute_match(/(^|\n)p\. /, note, "no leftover textile 'p.' terminator in note source")
    assert_includes note, '> feat: add'
    assert_includes note, '> Body line.'
  end

  # Renders the generated note through Redmine's textile (RedCloth) formatter
  # and verifies no textile-style block markers leak as literal text in HTML.
  # Repros the original user bug: `bq..` / `p.` appearing verbatim in journal.
  def test_textile_render_does_not_leak_textile_block_markers
    Setting.text_formatting = 'textile'

    message = "[CR #5071]: test multiline comment\n\n" \
              "- first line after empty line\n" \
              "- second line\n" \
              "- some other info"
    commit = { 'sha' => '41981d11', 'url' => 'https://example.com/c/41981d11' }
    note = ForgejoWebhook::NoteBuilder.new(message, commit,
                                           'Author: sfaur <stefan.faur@irian.ro>').call

    html = Redmine::WikiFormatting.to_html('textile', note).to_s

    refute_match(/bq\.\./, html,
                 "raw 'bq..' marker must not appear in rendered HTML (got: #{html})")
    refute_match(/(^|>)\s*p\.\s*(<|$)/, html,
                 "raw 'p.' terminator must not appear in rendered HTML (got: #{html})")
    assert_includes html, '[CR #5071]: test multiline comment',
                    "body content must survive rendering (got: #{html})"
  end

  def test_markdown_render_produces_blockquote_element
    Setting.text_formatting = 'markdown'

    message = "feat: add thing\n\nDetailed body.\nSecond line."
    commit = { 'sha' => 'a1b2c3d4', 'url' => 'https://example.com/c/a1b2c3d4' }
    note = ForgejoWebhook::NoteBuilder.new(message, commit, 'Author: Jane <jane@x.com>').call

    html = Redmine::WikiFormatting.to_html(Setting.text_formatting, note).to_s

    assert_match(%r{<blockquote\b}, html,
                 "expected a <blockquote> element in rendered HTML (got: #{html})")
    refute_match(/^&gt; /, html,
                 "raw '> ' prefix must not appear in rendered HTML (got: #{html})")
  end

  def test_truncates_message_byte_safely_when_oversized
    Setting.text_formatting = 'markdown'
    giant = "x" * 70_000
    note = ForgejoWebhook::NoteBuilder.new(giant, { 'sha' => 'aaaaaaaa' }, 'Author: A').call

    assert_operator note.bytesize, :<=, 60_000
    assert_includes note, '… [truncated]'
    assert_includes note, 'Commit referenced this issue: @aaaaaaaa@'
    assert_includes note, 'Author: A'
  end

  def test_truncation_does_not_split_multibyte_codepoint
    Setting.text_formatting = 'markdown'
    # emoji is 4 bytes in utf8mb4; fill above the cap
    giant = ("\u{1F600}" * 20_000) # 80_000 bytes
    note = ForgejoWebhook::NoteBuilder.new(giant, { 'sha' => 'aaaaaaaa' }, nil).call

    assert_operator note.bytesize, :<=, 60_000
    assert_predicate note, :valid_encoding?
  end
end
