require './workers/send_slack_messages_for_timecode_job'

class Slack
  PAYLOAD_WHITELIST = %w(url_verification event_callback).freeze
  EVENT_WHITELIST = %w(message).freeze

  class << self
    def process_incoming_payload(params)
      unless params['token'] == ENV['SLACK_TOKEN']
        puts "[WARNING] Not a valid Slack token"
        return
      end

      type = params['type']
      if PAYLOAD_WHITELIST.include?(type)
        self.send(type, params)
      else
        puts "[WARNING] Dropping Slack event '#{type}'"
      end
    end

    def url_verification(params)
      params['challenge']
    end

    def event_callback(params)
      event = params['event']
      event_type = event['type']
      if EVENT_WHITELIST.include?(event_type)
        send(event_type, event)
      else
        puts "[WARNING] Invalid event type '#{event_type}' recieved"
      end
    end

    def message(event)
      s = event['text']
      _, error_code, timestamp = */Error Code: ([\d]{3}) - ([\d]{14})/.match(s)
      return if error_code.nil? || timestamp.nil?

      reply_to = event.slice('channel', 'ts')
      SendSlackMessagesForTimecodeJob.perform_later(error_code, timestamp, reply_to)

      nil
    end
  end
end
