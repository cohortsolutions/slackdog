require './formatters/request_attachment_formatter'
require './processors/exception_message_processor'

class ExceptionAttachmentFormatter < RequestAttachmentFormatter
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

    processed = ExceptionMessageProcessor.process(event.app, exception)

    text = [
      fallback,
      backtrace_lines_from(exception['backtrace']),
      request_event_text(show_ip: true)
    ].compact

    {
      'color' => 'danger',
      'fallback' => fallback,
      'mrkdwn_in' => ['pretext', 'text'],
      'pretext' => if processed
        r = processed[:message]

        if processed[:context]
          r += "\n```\n#{processed[:context]}\n```"
        end

        r
      end,
      'text' => text.join("\n")
    }
  end
end
