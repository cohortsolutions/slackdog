require './formatters/request_attachment_formatter'
require './processors/exception_message_processor'

class ExceptionAttachmentFormatter < RequestAttachmentFormatter
  def to_payload
    exception = event.exception
    return unless exception

    exception_message = if exception['subtype']
      "`[#{event.app}]` *#{exception['subtype']}* '#{exception['message']}'."
    else
      "`[#{event.app}]` *#{exception['type']}* '#{exception['message']}'"
    end

    if router_error = exception['router_error']
      exception_message << " (#{router_error})"
    end

    processed = ExceptionMessageProcessor.process(event.app, exception)

    text = [
      exception_message,
      request_event_text(show_ip: true),
      backtrace_lines_from(exception['backtrace']),
    ].compact

    {
      'color' => 'danger',
      'fallback' => exception_message,
      'mrkdwn_in' => ['pretext', 'text'],
      'pretext' => if processed
        r = processed[:message]

        if processed[:code_context]
          filename = processed[:code_context][:file].to_s.split('/').last
          line_number = processed[:code_context][:line]
          line_of_code = processed[:code_context][:focus]
          r += "\n```\n# #{filename}:#{line_number}\n#{line_of_code}\n```"
        end

        r
      end,
      'text' => text.join("\n")
    }
  end
end
