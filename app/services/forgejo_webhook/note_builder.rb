module ForgejoWebhook
  class NoteBuilder
    def initialize(message, commit_data, attribution)
      @message = message.to_s
      @commit_data = commit_data || {}
      @attribution = attribution
    end

    def call
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
      markdown_blockquote(body)
    end

    def markdown_blockquote(text)
      "\n" + text.each_line.map { |l| "> #{l.chomp}" }.join("\n")
    end
  end
end
