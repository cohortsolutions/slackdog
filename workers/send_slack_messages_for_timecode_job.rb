require 'date'
require './papertrail'
require './services/slack_service'

require './workers/worker_base'

class SendSlackMessagesForTimecodeJob < WorkerBase
  MAX_BUFFER_SECONDS = 1
  MIN_BUFFER_SECONDS = 35
  SECONDS_IN_DAY = 24 * 60 * 60

  def perform(error_code, timestamp, reply_to)
    origin = DateTime.parse(timestamp)
    max = origin + (MAX_BUFFER_SECONDS / SECONDS_IN_DAY.to_f)
    min = origin - (MIN_BUFFER_SECONDS / SECONDS_IN_DAY.to_f)

    events = Papertrail.compile(min, max)
    send_messages(events, reply_to)
  end

  private

  def send_messages(events, envelope_data)
    attachments = []
    current_request_group = []

    events.group_by(&:app).each do |app, es|
      event_pool = es.to_a
      while event_pool.any?
        current = event_pool.shift

        if current.request
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
    end

    if current_request_group.any?
      group_request_events(current_request_group, attachments)
      current_request_group.clear
    end

    # debug_pool = events.select(&:debug_info)
    # build_debug_info_attachments(debug_pool, attachments) if debug_pool.any?

    return if attachments.empty?
    send_message(attachments, envelope_data)

    attachments
  end

  def request_event_text(event, show_ip: false)
    text = ''
    request = event.request

    if request['path']
      path = request['path'].split('?', 2).first
      path = "#{path[0..4]}...#{path[-35..-1]}" if path.size > 43 # 5 + 35 + 3 (for ...)
      text << "`[#{request['method']}]` #{path}"
    end

    redirected = request['redirected_to']
    redirection_prompt = if filter_chain_redirected_by = request['filter_chain_redirected_by']
      "_redirected by #{filter_chain_redirected_by}_"
    elsif redirected
      '_redirected_'
    end

    if redirection_prompt
      margin = [redirection_prompt.size, 35].min
      text << " *->* <#{redirected}|#{redirection_prompt.ljust(margin)}>"
    end

    if show_ip && ip = event.request['ip']
      text << " (#{ip})"
    end

    text
  end

  def group_request_events(events, attachments)
    result = []
    events.
      group_by { |e| e.request['ip'] }.
      each do |ip, es|
        es.each_with_index do |e, i|
          result << request_event_text(e, show_ip: i == 0)
        end
      end

    attachments << {
      'text' => result.join("\n"),
      'mrkdwn_in' => %w{text}
    } unless result.empty?
  end

  def build_exception_attachment(event, attachments)
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

  # def build_debug_info_attachments(events, attachments)
  #   fields = []
  #
  #   dynos = event.debug_info['dynos']
  #   addons = event.debug_info['addons']
  #   memory = event.debug_info['memory']
  #
  #   if cpu_log = dynos && dynos.detect { |l| l['fields'].key?('load_avg_1m') }
  #     meta = cpu_log['fields']
  #     fields << {
  #       'title' => 'Server Load',
  #       'short' => true,
  #       'value' => [
  #         meta['load_avg_1m'],
  #         meta['load_avg_5m'],
  #         meta['load_avg_15m']
  #       ].join(' ')
  #     }
  #   end if dynos
  #
  #   if ram_log = dynos && dynos.detect { |l| l['fields'].key?('memory_quota') }
  #     meta = ram_log['fields']
  #     fields << {
  #       'title' => 'Memory Usage',
  #       'short' => true,
  #       'value' => "#{meta['memory_total']} / #{meta['memory_quota']}"
  #     }
  #   end
  #
  #   if db_size_log = addons && addons.detect { |l| l['fields'].key?('db_size') }
  #     meta = db_size_log['fields']
  #
  #     fields << {
  #       'title' => 'Database size',
  #       'short' => true,
  #       'value' => "#{meta['db_size']} (#{meta['tables']} tables)"
  #     }
  #
  #     fields << {
  #       'title' => 'Database connections',
  #       'short' => true,
  #       'value' => "#{meta['active-connections']} active. #{meta['waiting-connections']} waiting."
  #     }
  #
  #     fields << {
  #       'title' => 'Database memory',
  #       'short' => true,
  #       'value' => "#{meta['memory-total']} available. #{meta['memory-free']} free."
  #     }
  #   end
  #
  #   attachments << {}.tap do |attachment|
  #     attachment['mrkdwn_in'] = %w{pretext fields}
  #     attachment['fields'] = fields
  #     attachment['pretext'] = "*#{event.app}* > #{event.process}"
  #   end
  # end

  def backtrace_lines_from(backtrace)
    return nil if backtrace.empty?

    max_allowed_length = 50
    max_file_length = backtrace.map { |t| t['file'].size }.max
    file_path_margin = [max_file_length, max_allowed_length].min + 2

    internal_file_prefix = ['app'].freeze
    stripped_prefixes = ['app'].freeze
    ignored_prefixes = ['lib'].freeze

    result = []
    ignored_count = 0
    backtrace.each do |trace|
      parts = trace['file'].split('/').reject(&:empty?)
      prefix = parts[0]

      if ignored_prefixes.include?(prefix)
        ignored_count += 1
        next
      end

      if ignored_count > 0
        result << "[+#{ignored_count} omitted]"
        ignored_count = 0
      end

      parts.shift if stripped_prefixes.include?(prefix)
      filepath = parts.join('/')[0..max_allowed_length]

      parts = []
      parts << '* ' if internal_file_prefix.include?(prefix)
      parts << filepath.ljust(file_path_margin)
      line_number = trace['line'].rjust(4)

      result << "#{parts.join}:#{line_number} in #{trace['method']}"
    end

    "```\n#{result.join("\n")}\n```"
  end

  def send_message(attachments, envelope_data)
    SlackService.post_reply(envelope_data['channel'], envelope_data['ts'], attachments)
  end
end
