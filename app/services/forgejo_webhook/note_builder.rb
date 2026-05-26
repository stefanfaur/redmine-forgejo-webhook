module ForgejoWebhook
  class NoteBuilder
    MAX_BYTES = 60_000
    TRUNCATE_MARKER = "\n> … [truncated]"

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
      lines = []
      lines << header_line
      lines << "\n#{url}" if url.present?
      lines << "\n#{@attribution}" if @attribution.present?
      lines << "\n#{blockquote}" if blockquote_present?
      lines.join
    end

    private

    def header_line
      sha = (@commit_data['sha'] || @commit_data['id']).to_s
      if sha.empty?
        'Commit referenced this issue'
      else
        "Commit referenced this issue: @#{sha[0..7]}@"
      end
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

      raw_url
    end

    def url
      @commit_data['url'].to_s
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
      budget = MAX_BYTES - TRUNCATE_MARKER.bytesize
      sliced = note.byteslice(0, budget).force_encoding('UTF-8').scrub('')
      sliced + TRUNCATE_MARKER
    end
  end
end
