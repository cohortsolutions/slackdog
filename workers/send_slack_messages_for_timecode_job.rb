require 'date'
require './papertrail'
require './services/slack_service'

require './workers/worker_base'

require './formatters/exception_attachment_formatter'
require './formatters/active_job_attachment_formatter'

class SendSlackMessagesForTimecodeJob < WorkerBase
  SECONDS_IN_DAY = 24 * 60 * 60
  MAX_BUFFER_SECONDS = 1 / SECONDS_IN_DAY.to_f
  ERROR_CODE_TIME_MAPPING = {
    '503' => 35,
    'default' => 1
  }.freeze

  def perform(error_code, timestamp, reply_to)
    origin = DateTime.parse(timestamp)
    min = origin - seconds_back_for(error_code)
    max = origin + MAX_BUFFER_SECONDS

    events = Papertrail.compile(min, max)
    formatted_events = format_events(events).select do |formatted|
      formatted.event.exception && formatted.event.request &&
        formatted.event.exception['errored_at'] == origin &&
        formatted.event.request['code'] == error_code
    end

    send_messages(formatted_events, reply_to)
  end

  private

  def seconds_back_for(error_code)
    (ERROR_CODE_TIME_MAPPING[error_code] || ERROR_CODE_TIME_MAPPING['default']) / SECONDS_IN_DAY.to_f
  end

  def format_events(events)
    events.map do |event|
      if event.exception
        ExceptionAttachmentFormatter.new(event)
      elsif event.active_job
        ActiveJobAttachmentFormatter.new(event)
      # elsif event.debug_info
      #   DebugAttachmentFormatter.new(event)
      elsif event.request
        RequestAttachmentFormatter.new(event)
      end
    end.compact
  end

  def send_messages(formatters, envelope_data)
    puts "send_messages called for #{formatters.size} messages"
    attachments = formatters.map(&:to_payload)
    send_message(attachments, envelope_data) unless attachments.empty?

    nil
  end

  def send_message(attachments, envelope_data)
    SlackService.post_reply(envelope_data['channel'], envelope_data['ts'], attachments)
  end
end
