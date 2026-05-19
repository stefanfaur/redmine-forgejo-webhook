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
end
