class AttachmentFormatter
  STRIPPED_PREFIXES = ['app'].freeze
  IGNORED_PREFIXES = ['lib'].freeze

  attr_reader :event

  def initialize(event)
    @event = event
  end

  def to_payload
    raise "`to_payload` has not been overridden for #{self.class.name}"
  end

  protected

  def backtrace_lines_from(backtrace)
    return if backtrace.empty?

    result = []
    ignored_count = 0
    backtrace.each do |trace|
      parts = trace['file_parts']
      prefix = parts[0]

      if IGNORED_PREFIXES.include?(prefix)
        ignored_count += 1
        next
      end

      parts.shift if STRIPPED_PREFIXES.include?(prefix)
      display_line = [parts.join('/'), trace['line']].join(':')
      next if display_line == result.last # don't print sequential duplicate lines (blocks in map for example)

      if ignored_count > 0
        result << "[+#{ignored_count} omitted]"
        ignored_count = 0
      end

      result << display_line
    end

    result << "[+#{ignored_count} omitted]" if ignored_count > 0
    "```\n#{result.join("\n")}\n```"
  end
end
