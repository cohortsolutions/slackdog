require './formatters/attachment_formatter'

class ActiveJobAttachmentFormatter < AttachmentFormatter
  def to_payload
    active_job = event.active_job
    return unless active_job

    exception, error_message = if error = active_job['error']
      [error['exception'], error['message']]
    end

    text_lines = []
    text_lines << "*#{exception}* #{error_message}" if exception
    text_lines << backtrace_lines_from(active_job['backtrace']) if active_job['backtrace']

    fields = []

    if active_job['job']
      fields << {
        'title' => 'Job',
        'value' => active_job['job'],
        'short' => true
      }
    end

    if active_job['id']
      fields << {
        'title' => 'Job ID',
        'value' => active_job['id'][0...8],
        'short' => true
      }
    end

    if active_job['state']
      fields << {
        'title' => 'Status',
        'value' => active_job['state'],
        'short' => true
      }
    end

    fields << {
      'title' => 'Server',
      'value' => "#{event.app}:#{event.process}",
      'short' => true
    }

    {}.tap do |attachment|
      if error_message
        attachment['color'] = 'danger'
        attachment['fallback'] = "[#{event.app}] *#{active_job['job']}* '#{error_message}'."
      end

      attachment['mrkdwn_in'] = ['text']
      attachment['text'] = text_lines.join("\n") if text_lines.any?
      attachment['fields'] = fields
    end
  end
end
