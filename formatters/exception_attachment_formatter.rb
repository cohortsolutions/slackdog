require './formatters/request_attachment_formatter'

class ExceptionAttachmentFormatter < RequestAttachmentFormatter
  BACKTRACE_MAX_LENGTH = 50

  INTERNAL_FILE_PREFIX = ['app'].freeze
  STRIPPED_PREFIXES = ['app'].freeze
  IGNORED_PREFIXES = ['lib'].freeze

  def to_payload
    fallback = if event.exception['subtype']
      "[#{event.app}] *#{event.exception['subtype']}* '#{event.exception['message']}'."
    else
      "[#{event.app}] *#{event.exception['type']}* '#{event.exception['message']}'"
    end

    if router_error = event.exception['router_error']
      fallback << " (#{router_error})"
    end

    text = [
      request_event_text(event, show_ip: true),
      fallback,
      backtrace_lines_from(event.exception['backtrace'])
    ].compact

    {
      'color' => 'danger',
      'fallback' => fallback,
      'mrkdwn_in' => ['text'],
      'text' => text.join("\n")
    }
  end
end
