require 'date'
require './papertrail'
require './services/slack_service'

require './workers/worker_base'

require './formatters/exception_attachment_formatter'
require './formatters/active_job_attachment_formatter'

class SendSlackMessagesForTimecodeJob < WorkerBase
  SECONDS_IN_DAY = 24 * 60 * 60
  MAX_BUFFER_SECONDS = 1 / SECONDS_IN_DAY.to_f
  MIN_BUFFER_SECONDS = 35 / SECONDS_IN_DAY.to_f

  def perform(error_code, timestamp, reply_to)
    origin = DateTime.parse(timestamp)
    min = origin - MIN_BUFFER_SECONDS
    max = origin + MAX_BUFFER_SECONDS

    events = Papertrail.compile(min, max)
    timelines = build_timelines(events)
    send_messages(timelines, reply_to)
  end

  private

  def build_timelines(events)
    events.group_by(&:app).map do |app, grouped|
      timeline = []
      current_request_group = []

      grouped.each do |event|
        if !event.request || !event.exception
          current_request_group << event
          next
        end

        if current_request_group.any?
          timeline << [:request_group, current_request_group]
          current_request_group.clear
        end

        if event.exception
          timeline << ExceptionAttachmentFormatter.new(event)
        elsif event.active_job
          timeline << ActiveJobAttachmentFormatter.new(event)
        # elsif event.debug_info
        #   timeline << [:debug, event]
        end
      end

      if current_request_group.any?
        timeline << [:request_group, current_request_group]
      end

      [app, timeline]
    end.to_h
  end

  def send_messages(timelines, envelope_data)
    timelines.each do |app, timeline|
      attachments = []

      timeline.each do |formatter, event|
        next unless formatter.is_a?(AttachmentFormatter)
        attachments << formatter.to_payload
      end

      next if attachments.empty?
      send_message(attachments, envelope_data)
    end

    nil
  end

  def send_message(attachments, envelope_data)
    SlackService.post_reply(envelope_data['channel'], envelope_data['ts'], attachments)
  end
end
