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

    assert_match %r{<a href="https://example\.com/commit/a1b2c3d4"[^>]*><code>a1b2c3d4</code></a>}, note,
                 "header must contain anchor wrapping SHA in code tag (got: #{note})"
    assert_includes note, 'Author: Jane <jane@x.com>'
    assert_includes note, "> feat: add thing"
    assert_includes note, "> Detailed body."
    assert_includes note, "> Second line."
    refute note.end_with?("> \n"), 'no trailing blockquote line'
  end

  def test_omits_blockquote_when_message_blank
    note = ForgejoWebhook::NoteBuilder.new('', { 'sha' => 'aaaaaaaa' }, 'Author: Jane').call

    assert_match %r{<code>aaaaaaaa</code>}, note,
                 "header must contain SHA in code tag (got: #{note})"
    refute_match %r{<a\b}, note,
                 "header must not contain anchor when URL is missing (got: #{note})"
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
    refute_match %r{<a\b}, note,
                 "header must not contain anchor tag when URL is missing (got: #{note})"
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
    assert_match %r{<code>aaaaaaaa</code>}, note,
                 "truncated note must preserve header with SHA in code tag (got: #{note})"
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

  def test_header_links_sha_when_url_present
    commit = { 'sha' => 'a1b2c3d4abcdef', 'url' => 'https://example.com/commit/a1b2c3d4' }
    message = "test message"
    note = ForgejoWebhook::NoteBuilder.new(message, commit, nil).call

    assert_match %r{<a href="https://example\.com/commit/a1b2c3d4"[^>]*><code>a1b2c3d4</code></a>}, note,
                 "header must contain anchor wrapping the short SHA in a code tag (got: #{note})"
  end

  def test_textile_render_produces_anchor_around_sha
    Setting.text_formatting = 'textile'

    commit = { 'sha' => 'a1b2c3d4abcdef', 'url' => 'https://example.com/commit/a1b2c3d4' }
    message = "commit message"
    note = ForgejoWebhook::NoteBuilder.new(message, commit, nil).call

    html = Redmine::WikiFormatting.to_html('textile', note).to_s
    fragment = Nokogiri::HTML.fragment(html)

    anchor = fragment.at_css('a')
    assert_not_nil anchor, "expected an anchor element in rendered HTML (got: #{html})"
    assert_equal 'https://example.com/commit/a1b2c3d4', anchor[:href],
                 "anchor href must match the commit URL (got: #{anchor[:href]})"

    code = anchor.at_css('code')
    assert_not_nil code, "expected a code element inside the anchor (got: #{html})"
    assert_equal 'a1b2c3d4', code.text,
                 "code text must be the short SHA (got: #{code.text})"
  end

  def test_markdown_render_produces_anchor_around_sha
    Setting.text_formatting = 'markdown'

    commit = { 'sha' => 'a1b2c3d4abcdef', 'url' => 'https://example.com/commit/a1b2c3d4' }
    message = "commit message"
    note = ForgejoWebhook::NoteBuilder.new(message, commit, nil).call

    html = Redmine::WikiFormatting.to_html('markdown', note).to_s
    fragment = Nokogiri::HTML.fragment(html)

    anchor = fragment.at_css('a')
    assert_not_nil anchor, "expected an anchor element in rendered HTML (got: #{html})"
    assert_equal 'https://example.com/commit/a1b2c3d4', anchor[:href],
                 "anchor href must match the commit URL (got: #{anchor[:href]})"

    code = anchor.at_css('code')
    assert_not_nil code, "expected a code element inside the anchor (got: #{html})"
    assert_equal 'a1b2c3d4', code.text,
                 "code text must be the short SHA (got: #{code.text})"
  end

  def test_header_renders_code_only_when_url_missing
    commit = { 'sha' => 'a1b2c3d4abcdef' }
    message = "test message"
    note = ForgejoWebhook::NoteBuilder.new(message, commit, nil).call

    assert_match %r{<code>a1b2c3d4</code>}, note,
                 "header must contain short SHA in code tag (got: #{note})"
    refute_match %r{<a\b}, note,
                 "header must not contain an anchor tag when URL is missing (got: #{note})"
  end

  def test_rejects_javascript_scheme_url
    commit = { 'sha' => 'a1b2c3d4abcdef', 'url' => 'javascript:alert(1)' }
    message = "test message"
    note = ForgejoWebhook::NoteBuilder.new(message, commit, nil).call

    assert_match %r{<code>a1b2c3d4</code>}, note,
                 "header must contain code tag even with unsafe URL (got: #{note})"
    refute_match %r{<a\b}, note,
                 "header must not contain an anchor for javascript: scheme (got: #{note})"

    ['textile', 'markdown'].each do |fmt|
      html = Redmine::WikiFormatting.to_html(fmt, note).to_s
      fragment = Nokogiri::HTML.fragment(html)
      javascript_anchors = fragment.css('a[href*="javascript:"]')
      assert_empty javascript_anchors,
                   "rendered HTML must not contain javascript: anchors in #{fmt} mode (got: #{html})"
    end
  end

  def test_rejects_data_scheme_url
    commit = { 'sha' => 'a1b2c3d4abcdef', 'url' => 'data:text/html,<script>alert(1)</script>' }
    message = "test message"
    note = ForgejoWebhook::NoteBuilder.new(message, commit, nil).call

    assert_match %r{<code>a1b2c3d4</code>}, note,
                 "header must contain code tag even with unsafe URL (got: #{note})"
    refute_match %r{<a\b}, note,
                 "header must not contain an anchor for data: scheme (got: #{note})"

    ['textile', 'markdown'].each do |fmt|
      html = Redmine::WikiFormatting.to_html(fmt, note).to_s
      fragment = Nokogiri::HTML.fragment(html)
      data_anchors = fragment.css('a[href*="data:"]')
      assert_empty data_anchors,
                   "rendered HTML must not contain data: anchors in #{fmt} mode (got: #{html})"
    end
  end

  def test_rejects_protocol_relative_url
    commit = { 'sha' => 'a1b2c3d4abcdef', 'url' => '//evil.example/x' }
    message = "test message"
    note = ForgejoWebhook::NoteBuilder.new(message, commit, nil).call

    assert_match %r{<code>a1b2c3d4</code>}, note,
                 "header must contain code tag even with unsafe URL (got: #{note})"
    refute_match %r{<a\b}, note,
                 "header must not contain an anchor for protocol-relative URL (got: #{note})"

    ['textile', 'markdown'].each do |fmt|
      html = Redmine::WikiFormatting.to_html(fmt, note).to_s
      fragment = Nokogiri::HTML.fragment(html)
      rel_anchors = fragment.css('a[href^="//"]')
      assert_empty rel_anchors,
                   "rendered HTML must not contain protocol-relative anchors in #{fmt} mode (got: #{html})"
    end
  end

  def test_html_escapes_url_attribute
    commit = { 'sha' => 'a1b2c3d4abcdef', 'url' => 'https://x.com/?a=1&b=2&c="evil' }
    message = "test message"
    note = ForgejoWebhook::NoteBuilder.new(message, commit, nil).call

    assert_match %r{&amp;}, note,
                 "raw note must contain escaped ampersands (got: #{note})"
    assert_match %r{&quot;}, note,
                 "raw note must contain escaped quotes (got: #{note})"

    fragment = Nokogiri::HTML.fragment(note)
    anchor = fragment.at_css('a')
    assert_not_nil anchor, "expected an anchor element (got: #{note})"
    assert_equal 'https://x.com/?a=1&b=2&c="evil', anchor[:href],
                 "anchor href must be unescaped to original URL after DOM parsing (got: #{anchor[:href]})"
  end

  def test_truncation_preserves_anchor_tag
    large_body = "x" * 70_000
    commit = { 'sha' => 'a1b2c3d4abcdef', 'url' => 'https://example.com/commit/a1b2c3d4' }
    note = ForgejoWebhook::NoteBuilder.new(large_body, commit, nil).call

    assert_operator note.bytesize, :<=, 60_000,
                    "note must not exceed 60 000 bytes (got: #{note.bytesize})"

    assert_includes note, '… [truncated]',
                    "note should contain truncation marker (got: #{note.slice(0..200)}...)"

    fragment = Nokogiri::HTML.fragment(note)
    anchors = fragment.css('a')
    assert_equal 1, anchors.length,
                 "note must contain exactly one anchor after truncation (got: #{anchors.length})"
    assert_equal 'https://example.com/commit/a1b2c3d4', anchors[0][:href],
                 "anchor href must match the commit URL (got: #{anchors[0][:href]})"
  end

  def test_omits_url_line_unconditionally
    commit = { 'sha' => 'a1b2c3d4abcdef', 'url' => 'https://example.com/commit/a1b2c3d4' }
    message = "test message"
    note = ForgejoWebhook::NoteBuilder.new(message, commit, nil).call

    url = 'https://example.com/commit/a1b2c3d4'
    count = note.scan(url).length
    assert_equal 1, count,
                 "URL must appear exactly once in the note (as href attribute), not as standalone line (got: #{count} occurrences)"
  end
end
