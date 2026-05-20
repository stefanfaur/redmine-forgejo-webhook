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
      case Setting.text_formatting
      when 'textile'
        textile_blockquote(body)
      else
        markdown_blockquote(body)
      end
    end

    def textile_blockquote(text)
      "\nbq.. #{text}\n\np. \n"
    end

    def markdown_blockquote(text)
      "\n" + text.each_line.map { |l| "> #{l.chomp}" }.join("\n")
    end

    def truncate(note)
      budget = MAX_BYTES - TRUNCATE_MARKER.bytesize
      sliced = note.byteslice(0, budget).force_encoding('UTF-8').scrub('')
      sliced + TRUNCATE_MARKER
    end
  end
end
