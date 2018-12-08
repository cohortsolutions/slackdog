class AttachmentFormatter
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

    max_file_length = backtrace.map { |t| t['file'].size }.max
    file_path_margin = [max_file_length, BACKTRACE_MAX_LENGTH].min + 2

    result = []
    ignored_count = 0
    backtrace.each do |trace|
      parts = trace['file'].split('/').reject(&:empty?)
      prefix = parts[0]

      if IGNORED_PREFIXES.include?(prefix)
        ignored_count += 1
        next
      end

      if ignored_count > 0
        result << "[+#{ignored_count} omitted]"
        ignored_count = 0
      end

      parts.shift if STRIPPED_PREFIXES.include?(prefix)
      filepath = parts.join('/')[0..BACKTRACE_MAX_LENGTH]

      parts = []
      parts << '* ' if INTERNAL_FILE_PREFIX.include?(prefix)
      parts << filepath.ljust(file_path_margin)
      line_number = trace['line'].rjust(4)

      result << "#{parts.join}:#{line_number} in #{trace['method']}"
    end

    "```\n#{result.join("\n")}\n```"
  end
end
