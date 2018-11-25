require 'date'
require './papertrail'
require './services/slack_service'

class Slack
  PAYLOAD_WHITELIST = %w(url_verification event_callback).freeze
  EVENT_WHITELIST = %w(message).freeze
  SCAN_SECONDS = 1

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
      s = event['text']
      _, error_code, timestamp = */Error Code: ([\d]{3}) - ([\d]{14})/.match(s)
      return if error_code.nil? || timestamp.nil?

      origin = DateTime.parse(timestamp)
      buffer = SCAN_SECONDS / 24.0 / 60.0 / 60.0
      max = origin + buffer
      min = origin - buffer

      events = Papertrail.compile(min, max)
      # events_with_code = events.select { |e| e.response && e.response[:code] == error_code }

      reply_to = event.slice('channel', 'ts')
      # if events_with_code.any?
        # send_messages(events_with_code, reply_to)
      # else
        send_messages(events, reply_to)
      # end
    end

    private

    def send_messages(events, envelope_data)
      attachments = []
      event_pool = events.to_a
      current_request_group = []

      while event_pool.any?
        current = event_pool.shift

        if current.request || current.response
          if current.exception
            group_request_events(current_request_group, attachments)
            current_request_group.clear

            build_exception_attachment(current, attachments)
          else
            current_request_group << current
          end
        elsif current.active_job
          if current_request_group.any?
            group_request_events(current_request_group, attachments)
            current_request_group.clear
          end

          build_active_job_attachment(current, attachments)
        end
      end

      if current_request_group.any?
        group_request_events(current_request_group, attachments)
        current_request_group.clear
      end

      # debug_pool = events.select(&:debug_info)
      # build_debug_info_attachments(debug_pool, attachments) if debug_pool.any?

      return if attachments.empty?
      send_message(attachments, envelope_data)
    end

    def request_event_text(event)
      text = ''

      if event.request
        path = event.request['path'].split('?', 2).first
        path = "#{path[0, 35]}...#{path[-5, 5]}" if path.size > 40

        text += "`[#{event.request['method']}]` #{path}"
      end

      if response = event.response
        redirected = response['redirected_to']
        if filter_chain_redirect = response['filter_chain_redirected']
          text << " [#{filter_chain_redirect}] *->* <#{redirected}|_redirected_>"
        elsif redirected
          text << " [#{response['code']}] *->* <#{redirected}|_redirected_>"
        end
      end

      if exception = event.exception
        text += if event.exception['subtype']
          "\n*#{event.exception['subtype']}* #{event.exception['message']}"
        else
          "\n*#{event.exception['message']}*"
        end
      end

      text
    end

    def group_request_events(events, attachments)
      result = events.flat_map { |e| request_event_text(e) }.join("\n")
      attachments << {
        'text' => result,
        'mrkdwn_in' => %w{text}
      } unless result.empty?
    end

    def build_exception_attachment(event, attachments)
      fallback = if event.exception['subtype']
        "[#{event.app}] *#{event.exception['subtype']}* '#{event.exception['message']}'."
      else
        "[#{event.app}] #{event.exception['message']}"
      end

      text = [
        request_event_text(event),
        backtrace_lines_from(event.exception['backtrace'])
      ]

      attachments << {
        'color' => 'danger',
        'fallback' => fallback,
        'mrkdwn_in' => %w{text},
        'text' => text.join("\n")
      }
    end

    def build_active_job_attachment(event, attachments)
      exception, error_message = if error = event.active_job['error']
        [error['exception'], error['message']]
      end

      text_lines = []
      text_lines << "*#{exception}* #{error_message}" if exception
      text_lines << backtrace_lines_from(event.active_job['backtrace']) if event.active_job['backtrace']

      fields = []

      if event.active_job['job']
        fields << {
          'title' => 'Job',
          'value' => event.active_job['job'],
          'short' => true
        }
      end

      if event.active_job['id']
        fields << {
          'title' => 'Job ID',
          'value' => event.active_job['id'][0...8],
          'short' => true
        }
      end

      if event.active_job['state']
        fields << {
          'title' => 'Status',
          'value' => event.active_job['state'],
          'short' => true
        }
      end

      fields << {
        'title' => 'Server',
        'value' => "#{event.app}:#{event.process}",
        'short' => true
      }

      attachments << {}.tap do |attachment|
        if error_message
          attachment['color'] = 'danger'
          attachment['fallback'] = "[#{event.app}] *#{event.active_job['job']}* '#{error_message}'."
        end

        attachment['mrkdwn_in'] = %w{text}
        attachment['text'] = text_lines.join("\n") if text_lines.any?
        attachment['fields'] = fields
      end
    end

    def build_debug_info_attachments(events, attachments)
      fields = []

      dynos = event.debug_info['dynos']
      addons = event.debug_info['addons']
      memory = event.debug_info['memory']

      if cpu_log = dynos && dynos.detect { |l| l['fields'].key?('load_avg_1m') }
        meta = cpu_log['fields']
        fields << {
          'title' => 'Server Load',
          'short' => true,
          'value' => [
            meta['load_avg_1m'],
            meta['load_avg_5m'],
            meta['load_avg_15m']
          ].join(' ')
        }
      end if dynos

      if ram_log = dynos && dynos.detect { |l| l['fields'].key?('memory_quota') }
        meta = ram_log['fields']
        fields << {
          'title' => 'Memory Usage',
          'short' => true,
          'value' => "#{meta['memory_total']} / #{meta['memory_quota']}"
        }
      end

      if db_size_log = addons && addons.detect { |l| l['fields'].key?('db_size') }
        meta = db_size_log['fields']

        fields << {
          'title' => 'Database size',
          'short' => true,
          'value' => "#{meta['db_size']} (#{meta['tables']} tables)"
        }

        fields << {
          'title' => 'Database connections',
          'short' => true,
          'value' => "#{meta['active-connections']} active. #{meta['waiting-connections']} waiting."
        }

        fields << {
          'title' => 'Database memory',
          'short' => true,
          'value' => "#{meta['memory-total']} available. #{meta['memory-free']} free."
        }
      end

      attachments << {}.tap do |attachment|
        attachment['mrkdwn_in'] = %w{pretext fields}
        attachment['fields'] = fields
        attachment['pretext'] = "*#{event.app}* > #{event.process}"
      end
    end

    def backtrace_lines_from(backtrace)
      max_file_length = backtrace.map { |t| t['file'].size }.max
      file_path_margin = [max_file_length, 50].min + 2

      result = backtrace.map do |trace|
        internal_file = trace['file'].start_with?('app/') || trace['file'].start_with?('/app/')
        filepath = ''
        filepath += internal_file ? '* ' : '  '
        filepath += trace['file'][0..50]

        "#{filepath.ljust(file_path_margin)}:#{trace['line'].rjust(4)} in #{trace['method']}"
      end.join("\n")

      "```\n#{result}\n```"
    end

    def send_message(attachments, envelope_data)
      SlackService.post_reply(envelope_data['channel'], envelope_data['ts'], attachments)
    end
  end
end
