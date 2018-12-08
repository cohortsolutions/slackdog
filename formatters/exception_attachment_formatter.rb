require './formatters/request_attachment_formatter'

class ExceptionAttachmentFormatter < RequestAttachmentFormatter
  BACKTRACE_MAX_LENGTH = 50

  INTERNAL_FILE_PREFIX = ['app'].freeze
  STRIPPED_PREFIXES = ['app'].freeze
  IGNORED_PREFIXES = ['lib'].freeze

  def to_payload
    exception = event.exception
    return unless exception

    fallback = if exception['subtype']
      "[#{event.app}] *#{exception['subtype']}* '#{exception['message']}'."
    else
      "[#{event.app}] *#{exception['type']}* '#{exception['message']}'"
    end

    if router_error = exception['router_error']
      fallback << " (#{router_error})"
    end

    text = [
      request_event_text(show_ip: true),
      fallback,
      backtrace_lines_from(exception['backtrace'])
    ].compact

    {
      'color' => 'danger',
      'fallback' => fallback,
      'mrkdwn_in' => ['text'],
      'text' => text.join("\n")
    }
  end
end
