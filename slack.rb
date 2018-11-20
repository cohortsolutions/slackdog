require 'date'

class Slack
  PAYLOAD_WHITELIST = %w(url_verification event_callback).freeze
  EVENT_WHITELIST = %w(message).freeze
  SCAN_SECONDS = 3 # 30

  class << self
    def process_incoming_payload(params)
      puts "process_incoming_payload(#{params})"

      unless params['token'] == ENV['SLACK_TOKEN']
        puts "[WARNING] Not a valid token"
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
      puts "event_callback(#{params})"

      event = params['event']
      event_type = event['type']
      if EVENT_WHITELIST.include?(event_type)
        send(event_type, event)
      else
        puts "[WARNING] Invalid event type '#{event_type}' recieved"
      end
    end

    def message(event)
      # s = event['text']
      s = 'Error Code: 500 - 20181120150057'
      _, error_code, timestamp = */Error Code: ([\d]{3}) - ([\d]{14})/.match(s)
      return if error_code.nil? || timestamp.nil?

      max = DateTime.parse(timestamp)
      min = max - (SCAN_SECONDS / 24.0 / 60.0 / 60.0)
      result = `papertrail --min-time '#{min}' --max-time '#{max}'` # -- 'status=#{error_code}'`

      parser = /([a-zA-Z\s\d:]{15}) ([^\s]+) ([^:]+): (.*)/
      result.split("\n").each do |line|
        _, log_timestamp, log_app, log_process, log = *parser.match(line)
        raise "log_timestamp is nil for #{line}" if log_timestamp.nil?
        raise "log_app is nil for #{line}" if log_app.nil?
        raise "log_process is nil for #{line}" if log_process.nil?
        raise "log is nil for #{line}" if log.nil?

        puts [log_timestamp, log_app, log_process, log].inspect
        puts '+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+'
      end

      nil

      # Nov 21 01:00:56 cohortflow heroku/router: at=info method=POST path=\"/rules/simulate.json\" host=cohort.link request_id=e655fb4e-0aae-474a-b26f-eca1b74d0d0b fwd=\"190.0.32.202\" dyno=web.5 connect=1ms service=86ms status=500 bytes=290 protocol=https
      # Nov 21 01:00:57 errbit-cohortsolutions heroku/router: at=info method=POST path=\"/api/v3/projects/true/notices?key=222cfb37b3db9cada40a97310ba7fdb2\" host=errbit-cohortsolutions.herokuapp.com request_id=3a9af97a-8fcc-4fb5-b786-90819f9548d8 fwd=\"23.20.79.9\" dyno=web.1 connect=0ms service=239ms status=500 bytes=715 protocol=https
      # Nov 21 01:00:57 cohortflow heroku/router: at=info method=POST path=\"/rules/simulate.json\" host=cohort.link request_id=f5144db8-f003-4df6-8289-3c0964c94bf4 fwd=\"190.0.32.202\" dyno=web.4 connect=0ms service=231ms status=500 bytes=290 protocol=https
    end
  end
end
