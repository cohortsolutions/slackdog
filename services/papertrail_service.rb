require 'date'
require 'papertrail'
require 'chronic'

class PapertrailService
  STASHING_PATTERNS = %i(started job_start).freeze
  PATTERNS = {
    started: /Started (?<method>.+) \"(?<path>.+)\" for (?<ip>[\d]{1,3}\.[\d]{1,3}\.[\d]{1,3}\.[\d]{1,3})/,
    processing: /Processing by (?<controller>.+)#(?<action>.+) as/,
    csrf_fail: /Can't verify CSRF token authenticity/,
    filter_chain_redirect: /Filter chain halted as (?<method>[^\s]+) rendered or redirected/,
    redirected: /Redirected to (?<url>.*)/,
    completed: /Completed (?<code>[\d]{3}) (?<status>.+) in (?<duration>[\d\.\,]+)ms/,
    exception_trace: /(?<file>[^:\s]+):(?<line>[\d]+):in `(?<method>.+)'\z/,
    job_start: /\[ActiveJob\] \[(?<job>[^\]]+)\] \[(?<id>[^\]]+)\] Performing /,
    job_finish: /\[ActiveJob\] \[(?<job>[^\]]+)\] \[(?<id>[^\]]+)\] Performed /,
    job_error: /\[ActiveJob\] \[(?<job>[^\]]+)\] \[(?<id>[^\]]+)\] Error performing .* [\d\.]+ms: (?<exception>[^\s]+) \((?<message>.+)\):\z/,
    heroku_addon_info: /source=(?<source>[^\s]+) addon=(?<addon>[^\s]+) (?<info>((?:sample#[^\s]+=[^\s]+)\s?)*)\z/,
    heroku_dyno_info: /source=(?<source>[^\s]+) dyno=(?<dyno>[^\s]+) (?<info>((?:sample#[^\s]+=[^\s]+)\s?)*)\z/,
    heroku_memory_stat: /Process running mem=(?<ramUsed>.+)\((?<ramPercent>[\d\.]+)%\)/,
    heroku_router_info: /at=info method=(?<method>[^\s]+) path="(?<path>[^\"]+)" host=(?<host>[^\s]+) request_id=.* fwd="(?<ip>[^\"]+)" dyno=(?<dyno>[^\s]+) connect=\d+ms service=(?<duration>[\d\.\,]+)ms status=(?<code>[\d]+)/,
    heroku_router_error: /at=error code=(?<errorCode>[^\s]+) desc="(?<errorDescription>[^\"]+)" method=(?<method>[^\s]+) path="(?<path>[^\"]+)" host=(?<host>[^\s]+) request_id=.* fwd="(?<ip>[^\"]+)" dyno=(?<dyno>[^\s]+) connect=\d+ms service=(?<duration>[\d\.\,]+)ms status=(?<code>[\d]+)/,
    exception_start: /(?<exception>[^\s]+) \((?<message>.+)\):\z/m,
  }.freeze

  class LogLine
    attr_reader :time, :app, :process, :log

    def initialize(line)
      @time = line.received_at.to_datetime
      @app = line.data['source_name']
      @process = line.data['program']
      @log = line.data['message'].strip

      preprocess
    end

    private

    def preprocess
      if process == 'heroku/router'
        _, override_dyno = */dyno=([^\s]+)/.match(log)
        @process = "app/#{override_dyno}" if override_dyno
      end
    end
  end

  class RequestGroup
    class Line
      attr_reader :line, :type, :meta

      def initialize(line, type, meta)
        @line = line
        @type = type
        @meta = meta
      end
    end

    def lines
      @lines ||= []
    end

    def add_line(line, type, meta)
      lines << Line.new(line, type, meta)
    end
  end

  class Event
    attr_reader :app, :process

    def initialize(app, process, group)
      @app = app
      @process = process
      @group = group
    end

    def request
      @request ||= begin
        started = lines_for(:started).first
        controller = lines_for(:processing).first
        csrf_fail = lines_for(:csrf_fail).any?
        filter_chain_redirect = lines_for(:filter_chain_redirect).first
        redirected = lines_for(:redirected).first
        completed = lines_for(:completed).first
        router_info = lines_for(:heroku_router_info).first
        router_error = lines_for(:heroku_router_error).first
        return if started.nil? && controller.nil? && filter_chain_redirect.nil? && redirected.nil? && completed.nil?

        {'csrf_failed' => csrf_fail}.tap do |result|
          if started
            result.merge!(started.meta.slice('method', 'path', 'ip'))
            result['started_at'] = started.line.time
          end

          if controller
            result.merge!(controller.meta.slice('controller', 'action'))
          end

          if completed
            result.merge!(completed.meta.slice('code', 'status', 'duration'))
            result['completed_at'] = completed.line.time
          end

          if redirected
            result['redirected_to'] = redirected.meta['url']
          end

          if filter_chain_redirect
            result['filter_chain_redirected_by'] = filter_chain_redirect.meta['method']
          end

          if router_info
            %w(method path ip duration code host).each do |f|
              result[f] ||= router_info.meta[f]
            end
          end

          if router_error
            %w(method path ip duration code host).each do |f|
              result[f] ||= router_error.meta[f]
            end
          end
        end
      end
    end

    def exception
      @exception ||= begin
        line = lines_for(:exception_start).first
        router_error = lines_for(:heroku_router_error).first
        return unless line || router_error

        if line
          type = line.meta['exception']
          message = line.meta['message']
          match = /(?<subtype>.+): (?<innerMessage>.+)/.match(message)
          errored_at = line.line.time
        end

        if match
          details = match.named_captures
          subtype = details['subtype'].strip
          message = details['innerMessage'].strip
        end

        if router_error
          router_error_message = router_error.meta['errorDescription']
        end

        {
          'type' => type,
          'errored_at' => errored_at,
          'message' => message,
          'subtype' => subtype,
          'router_error' => router_error_message,
          'backtrace' => lines_for(:exception_trace).map do |trace|
            file_parts = trace.meta['file'].split('/').reject(&:empty?)
            trace.meta.slice('line', 'method').merge({
              'file_parts' => file_parts,
              'file' => file_parts.join('/'),
              'internal' => file_parts[0] == 'app'
            })
          end
        }
      end
    end

    def active_job
      @active_job ||= begin
        start_line = lines_for(:job_start).first
        finish_line = lines_for(:job_finish).first
        error_line = lines_for(:job_error).first
        return if start_line.nil? && finish_line.nil? && error_line.nil?

        backtrace = lines_for(:exception_trace)

        {
          'id' => (start_line && start_line.meta['id']) || (finish_line && finish_line.meta['id']) || (error_line && error_line.meta['id']),
          'job' => (start_line && start_line.meta['job']) || (finish_line && finish_line.meta['job']) || (error_line && error_line.meta['job']),
          'error' => error_line && error_line.meta.slice('exception', 'message'),
          'state' => if error_line
            'Errored'
          elsif finish_line
            'Finished'
          else
            'In Progress'
          end,
          'backtrace' => backtrace.any? && backtrace.map do |trace|
            trace.meta.slice('file', 'line', 'method')
          end
        }
      end
    end

    def debug_info
      @debug_info ||= begin
        dyno_lines = lines_for(:heroku_dyno_info)
        addon_lines = lines_for(:heroku_addon_info)
        memory_lines = lines_for(:heroku_addon_info)
        return if dyno_lines.empty? && addon_lines.empty? && memory_lines.empty?

        {}.tap do |result|
          result['dynos'] = dyno_lines.map do |line|
            {
              'server' => line.meta['source'],
              'fields' => line.meta['info'].scan(/sample#([^=]*)=([^\s]*)/).to_h
            }
          end if dyno_lines.any?

          result['addons'] = addon_lines.map do |line|
            {
              'server' => line.meta['source'],
              'fields' => line.meta['info'].scan(/sample#([^=]*)=([^\s]*)/).to_h
            }
          end if addon_lines.any?

          result['memory'] = memory_lines.map do |line|
            {
              'server' => process.split('/', 2).last,
              'fields' => {
                'ram_used' => line.meta['ramUsed'],
                'ram_percent' => line.meta['ramPercent']
              }
            }
          end if memory_lines.any?
        end
      end
    end

    def csrf_failed?
      lines_for(:csrf_fail).any?
    end

    private

    def lines_for(type)
      @group.lines.select { |line| line.type == type }
    end
  end

  class << self
    def compile(min, max)
      compile_from(log_lines_between(min, max))
    end

    def compile_from(log_lines)
      lines = log_lines.map { |line| LogLine.new(line) }

      [].tap do |events|
        new.process(lines) do |app, process, cache|
          cache.each do |group|
            events << Event.new(app, process, group)
          end
        end
      end
    end

    private

    def log_lines_between(min, max)
      [].tap do |results|
        connection.each_event('', {min_time: Chronic.parse(min.to_s), max_time: Chronic.parse(max.to_s)}) do |event|
          results << event
        end
      end
    end

    def connection
      @connection ||= begin
        Papertrail::Connection.new({
          configfile: nil,
          delay: 2,
          follow: false,
          token: ENV.fetch('PAPERTRAIL_API_TOKEN'),
          color: :program,
          force_color: false,
          json: true
        })
      end
    end
  end

  def process(lines, &block)
    lines.group_by { |l| [l.app, l.process] }.map do |(app, process), grouped_lines|
      cache = []
      unknown_stash = []

      @current_group = nil
      grouped_lines.each do |line|
        key, meta = pattern_match_for(line.log)

        if key == :unknown
          unknown_stash << line.log
          key, meta = pattern_match_for(unknown_stash.join("\n"))
          unknown_stash.clear unless key == :unknown
        else
          unknown_stash.clear
        end

        @current_group = nil if STASHING_PATTERNS.include?(key)
        current_group(cache).add_line(line, key, meta)
      end

      result = [app, process, cache]

      if block_given?
        yield result
      end

      result
    end
  end

  private

  def current_group(cache)
    @current_group ||= begin
      RequestGroup.new.tap do |result|
        cache << result
      end
    end
  end

  def pattern_match_for(log_line)
    PATTERNS.each do |key, pattern|
      match = pattern.match(log_line)
      next unless match

      return [key, match.named_captures]
    end

    [:unknown, {}]
  end
end
