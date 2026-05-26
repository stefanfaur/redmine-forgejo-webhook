module ForgejoWebhook
  class NoteBuilder
    MAX_BYTES = 60_000
    TRUNCATE_MARKER = "\n> … [truncated]"
    URL_SAFE_CHARS = %r{\A[A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]+\z}.freeze
    MARKDOWN_FORMATTERS = %w[markdown common_mark].freeze

    def initialize(message, commit_data, attribution)
      @message = message.to_s
      @commit_data = commit_data || {}
      @attribution = attribution
    end

    def call
      result = build_unbounded
      result.bytesize > MAX_BYTES ? truncate(result) : result
    end

    def build_unbounded
      preamble = build_preamble
      blockquote_content = blockquote_present? ? "\n#{blockquote}" : ""
      preamble + blockquote_content
    end

    private

    def build_preamble
      lines = []
      lines << header_line
      lines << "\n#{@attribution}" if @attribution.present?
      lines.join
    end

    def header_line
      sha = (@commit_data['sha'] || @commit_data['id']).to_s
      return 'Commit referenced this issue' if sha.empty?

      short_sha = sha[0..7]
      url = safe_url

      if markdown_formatter?
        if url
          "Commit referenced this issue: [`#{short_sha}`](<#{url}>)"
        else
          "Commit referenced this issue: `#{short_sha}`"
        end
      else
        if url
          "Commit referenced this issue: \"@#{short_sha}@\":#{url}"
        else
          "Commit referenced this issue: @#{short_sha}@"
        end
      end
    end

    def markdown_formatter?
      MARKDOWN_FORMATTERS.include?(Setting.text_formatting.to_s)
    end

    def safe_url
      raw_url = @commit_data['url'].to_s
      return nil if raw_url.empty?

      begin
        uri = URI.parse(raw_url)
      rescue URI::InvalidURIError
        return nil
      end

      return nil unless uri.scheme && %w[http https].include?(uri.scheme)
      return nil unless raw_url.match?(URL_SAFE_CHARS)

      raw_url
    end

    def body
      @message.strip
    end

    def blockquote_present?
      body.present?
    end

    def blockquote
      "\n" + body.each_line.map { |l| "> #{l.chomp}" }.join("\n")
    end

    def truncate(note)
      preamble = build_preamble
      preamble_bytes = preamble.bytesize

      if preamble_bytes >= MAX_BYTES
        budget = MAX_BYTES - TRUNCATE_MARKER.bytesize
        sliced = note.byteslice(0, budget).force_encoding('UTF-8').scrub('')
        return sliced + TRUNCATE_MARKER
      end

      blockquote_budget = MAX_BYTES - preamble_bytes - TRUNCATE_MARKER.bytesize
      blockquote_content = blockquote_present? ? "\n#{blockquote}" : ""

      if blockquote_content.bytesize <= blockquote_budget
        note
      else
        sliced_blockquote = blockquote_content.byteslice(0, blockquote_budget)
                                              .force_encoding('UTF-8')
                                              .scrub('')
        preamble + sliced_blockquote + TRUNCATE_MARKER
      end
    end
  end
end
