class Papertrail
  STASHING_PATTERNS = %i(started job_start).freeze
  PATTERNS = {
    started: /Started (?<method>.+) \"(?<path>.+)\" for (?<ip>[\d]{1,3}\.[\d]{1,3}\.[\d]{1,3}\.[\d]{1,3})/,
    processing: /Processing by (?<controller>.+)#(?<action>.+) as/,
    csrf_fail: /Can't verify CSRF token authenticity/,
    filter_chain_redirect: /Filter chain halted as (?<method>[^\s]+) rendered or redirected/,
    redirected: /Redirected to (?<url>.*)/,
    completed: /Completed (?<code>[\d]{3}) (?<status>.+) in (?<duration>[\d\.]+)ms/,
    exception_trace: /\s*(?<file>[^:]+):(?<line>[\d]+):in `(?<method>.+)'\z/,
    job_start: /\[ActiveJob\] \[(?<job>[^\]]+)\] \[(?<id>[^\]]+)\] Performing /,
    job_finish: /\[ActiveJob\] \[(?<job>[^\]]+)\] \[(?<id>[^\]]+)\] Performed /,
    job_error: /\[ActiveJob\] \[(?<job>[^\]]+)\] \[(?<id>[^\]]+)\] Error performing .* [\d\.]+ms: (?<exception>[^\s]+) \((?<message>.+)\):\z/,
    heroku_addon_info: /source=(?<source>[^\s]+) addon=(?<addon>[^\s]+) (?<info>((?:sample#[^\s]+=[^\s]+)\s?)*)\z/,
    heroku_dyno_info: /source=(?<source>[^\s]+) dyno=(?<dyno>[^\s]+) (?<info>((?:sample#[^\s]+=[^\s]+)\s?)*)\z/,
    heroku_memory_stat: /Process running mem=(?<ramUsed>.+)\((?<ramPercent>[\d\.]+)%\)/,
    exception_start: /(?<exception>[^\s]+) \((?<message>.+)\):\z/m,
  }.freeze

  class LogLine
    PARSER = /([a-zA-Z\s\d:]{15}) ([^\s]+) ([^:]+): (.*)/

    attr_reader :time, :app, :process, :log

    def initialize(line)
      _, timestamp, app, process, log = *PARSER.match(line)

      raise "`timestamp` is nil for '#{line}'" if timestamp.nil?
      raise "`app` is nil for '#{line}'" if app.nil?
      raise "`process` is nil for '#{line}'" if process.nil?
      raise "`log` is nil for '#{line}'" if log.nil?

      @time = DateTime.parse(timestamp)
      @app = app
      @process = process
      @log = log
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
        line = lines_for(:started).first
        controller_line = lines_for(:processing).first
        return if line.nil? && controller_line.nil?

        result = {}
        result.merge!(line.meta.slice('method', 'path', 'ip')) if line
        result.merge!(controller_line.meta.slice('controller', 'action')) if controller_line

        result
      end
    end

    def response
      @response ||= begin
        csrf_fail = lines_for(:csrf_fail).any?
        filter_chain_redirect = lines_for(:filter_chain_redirect).first
        redirected = lines_for(:redirected).first
        completed = lines_for(:completed).first
        return if filter_chain_redirect.nil? && redirected.nil? && completed.nil?

        {'csrf_failed' => csrf_fail}.tap do |result|
          if completed
            args = completed.
              meta.
              slice('code', 'status', 'duration')

            result.merge!(args)
          end

          if redirected
            result['redirected_to'] = redirected.meta['url']
          end

          if filter_chain_redirect
            result['filter_chain_redirected'] = filter_chain_redirect.meta['method']
          end
        end
      end
    end

    def exception
      @exception ||= begin
        line = lines_for(:exception_start).first
        return unless line

        message = line.meta['message']
        match = /(?<subtype>.+): (?<innerMessage>.+)/.match(message)

        if match
          details = match.named_captures
          subtype = details['subtype'].strip
          message = details['innerMessage'].strip
        end

        {
          'type' => line.meta['exception'],
          'message' => message,
          'subtype' => subtype,
          'backtrace' => lines_for(:exception_trace).map do |trace|
            trace.meta.slice('file', 'line', 'method')
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
      lines = log_lines_between(min, max).map do |line|
        LogLine.new(line)
      end

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
      result = `papertrail --min-time '#{min}' --max-time '#{max}'`
      result.split("\n").tap do |result|
        puts ''
        puts ''
        puts ''
        puts result
        puts ''
        puts ''
      end
    end
  end

  def process(lines, &block)
    lines.group_by { |l| [l.app, l.process] }.map do |(app, process), lines|
      cache = []
      unknown_stash = []

      lines.each do |line|
        key, meta = pattern_match_for(line.log)

        if key == :unknown
          unknown_stash << line.log
          key, meta = pattern_match_for(unknown_stash.join("\n"))
          unknown_stash.clear unless key == :unknown
        else
          unknown_stash.clear
        end

        stashing = STASHING_PATTERNS.include?(key)
        current_group(cache, stash: stashing).add_line(line, key, meta)
      end

      result = [app, process, cache]

      if block_given?
        yield result
      end

      result
    end
  end

  private

  def current_group(cache, stash: false)
    @current_group = nil if stash

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






















  # Nov 21 06:07:41 cohort-deploy app/web.1: Completed 200 OK in 141ms (Views: 0.5ms | ActiveRecord: 122.7ms)

  # Nov 21 06:07:41 cohortpay-transact app/web.3:   Rendered virtual_accounts/show.json.jbuilder (65.9ms)
  # Nov 21 06:07:41 cohortpay-transact app/web.3: Completed 200 OK in 228ms (Views: 61.7ms | ActiveRecord: 55.9ms)

  # Nov 21 06:07:42 cohortflow-demo heroku/worker.1: source=worker.1 dyno=heroku.51869768.e66a7e16-4e74-4f5d-8f1a-7510be35763b sample#load_avg_1m=0.00 sample#load_avg_5m=0.00 sample#load_avg_15m=0.00

  # Nov 21 06:07:42 oshca-web heroku/router: at=info method=GET path="/api/policies/card_quote.json?values%5Badults%5D=1&values%5Bchildren%5D=0&values%5Bstart%5D=2018-12-01&values%5Bfinish%5D=2020-12-01" host=studenthealth.nz request_id=07bdb49a-79dc-4d5f-a149-8ca8d86b3c12 fwd="200.118.114.77, 10.186.91.179,54.160.131.4" dyno=web.1 connect=0ms service=292ms status=304 bytes=419 protocol=https

  # Nov 21 06:07:42 cohortpay-demo app/web.1: Started POST "/admin/users/identity_push.json" for 54.205.86.120 at 2018-11-20 20:07:41 +0000
  # Nov 21 06:07:42 cohortpay-demo app/web.1: Processing by Admin::UsersController#identity_push as JSON
  # Nov 21 06:07:42 cohortpay-demo app/web.1:   Parameters: {"content"=>{"id"=>1444, "watchlist_state"=>"unchecked", "passport_state"=>"unverified", "update_sequence"=>2873, "state"=>"unchecked"}, "user"=>{}}
  # Nov 21 06:07:42 cohortpay-demo app/web.1: Can't verify CSRF token authenticity
  # Nov 21 06:07:42 cohortpay-demo app/web.1: Completed 422 Unprocessable Entity in 34ms (ActiveRecord: 13.5ms)
  # Nov 21 06:07:42 cohortpay-demo app/web.1: ActiveRecord::RecordInvalid (Validation failed: Dob must be at least four years old):
  # Nov 21 06:07:42 cohortpay-demo app/web.1:   app/admin/system/users.rb:258:in `block (3 levels) in <top (required)>'
  # Nov 21 06:07:42 cohortpay-demo app/web.1:   app/admin/system/users.rb:256:in `block (2 levels) in <top (required)>'
  # Nov 21 06:07:42 cohortpay-demo app/web.1:   lib/rack_headers.rb:72:in `_call'
  # Nov 21 06:07:42 cohortpay-demo app/web.1:   lib/rack_headers.rb:68:in `call'

  # Nov 21 06:07:42 cohortflow-demo heroku/worker.1: source=worker.1 dyno=heroku.51869768.e66a7e16-4e74-4f5d-8f1a-7510be35763b sample#memory_total=259.14MB sample#memory_rss=245.08MB sample#memory_cache=14.05MB sample#memory_swap=0.00MB sample#memory_pgpgin=69478pages sample#memory_pgpgout=3139pages sample#memory_quota=512.00MB
  # Nov 21 06:07:42 cohort-deploy heroku/router: at=info method=GET path="/cas/app_token.json?app=https://demo.s.oshcaustralia.com.au/admin/agent_organisations/sync_status.json" host=cohort-deploy.herokuapp.com request_id=0eef2a60-9780-4a72-86c4-f1215fb0b67d fwd="54.205.86.120" dyno=web.1 connect=55ms service=251ms status=200 bytes=1810 protocol=https
  # Nov 21 06:07:43 cohortarrivals-demo app/web.1: Started GET "/admin/organisations/sync_status.json" for 54.205.86.120 at 2018-11-20 20:07:43 +0000
  # Nov 21 06:07:43 cohortflow app/web.1: [Scout] [11/20/18 20:07:43 +0000 web.1 (13)] INFO : [20:05] Delivering 26 Metrics for 6 requests and 4 Slow Transaction Traces and 0 Job Traces, Recorded from 1 processes.
  # Nov 21 06:07:44 cohortpay-web heroku/worker.1: source=worker.1 dyno=heroku.7906290.7c19e1d8-6db6-42d9-869a-0a5226ffc845 sample#load_avg_1m=0.00 sample#load_avg_5m=0.00 sample#load_avg_15m=0.00
  # Nov 21 06:07:44 cohortpay-web heroku/worker.1: source=worker.1 dyno=heroku.7906290.7c19e1d8-6db6-42d9-869a-0a5226ffc845 sample#memory_total=447.50MB sample#memory_rss=402.95MB sample#memory_cache=38.95MB sample#memory_swap=5.60MB sample#memory_pgpgin=6866360pages sample#memory_pgpgout=6817619pages sample#memory_quota=512.00MB
  # Nov 21 06:07:47 cohortpay-dispatch heroku/router: at=info method=GET path="/status" host=dispatch.cohortpay.com request_id=971f44f7-a723-4e7c-b7ae-2c4f8e509ba9 fwd="85.93.93.133" dyno=web.1 connect=1ms service=1ms status=301 bytes=195 protocol=http


  # Nov 21 14:15:28 cohortflow heroku/router:  at=info method=GET path="/apps/cohortpay/provider_transactions" host=cohortflow.com request_id=844cb8e7-6f5c-46e9-b143-2fd87eccc033 fwd="61.68.25.202" dyno=web.5 connect=1ms service=217ms status=200 bytes=10810 protocol=https

  # Nov 21 14:15:28 cohortflow app/web.4:  Started PATCH "/organisation.json" for 14.201.12.218 at 2018-11-21 04:15:28 +0000
  # Nov 21 14:15:28 cohortflow app/web.4:  Processing by OrganisationsController#update as JSON
  # Nov 21 14:15:28 cohortflow app/web.4:    Parameters: {"organisation"=>{"agent"=>true, "basic"=>true, "country"=>"KR", "id"=>367842, "referrer_key"=>"au-dteducation", "essential_agent"=>false, "internal"=>false, "name"=>"D T Education", "pro"=>false, "provider"=>false, "type"=>"agent", "approved"=>true, "inbound_message_identifier"=>"fw-zblkfgdzru", "requires_taxation_details"=>true, "payment_method"=>"Subscriptions::StripeSubscription", "contact_address"=>"907 / 365 Little Collins Street, Melbourne 3000 Australia", "timezone"=>"Melbourne", "locale"=>"en", "abn"=>"64962186531", "gst_status"=>"registered", "permissions"=>{"update"=>true}, "logo"=>{"name"=>"Logo Large.PNG", "tags"=>nil, "direct_upload_url"=>"https://cohortflow-uploads.s3.amazonaws.com/uploads/1542773652233-1gyk35wfsed-03485a5150fb5ca511ebec9de10131c5/Logo+Large.PNG"}}}
  # Nov 21 14:15:28 cohortflow app/web.4:  Can't verify CSRF token authenticity
  # Nov 21 14:15:28 cohortflow app/web.4:  Completed 422 Unprocessable Entity in 1ms (ActiveRecord: 0.0ms)
  # Nov 21 14:15:28 cohortflow heroku/router:  at=info method=PATCH path="/organisation.json" host=cohortflow.com request_id=35caef8a-3be8-40d1-9d05-3369fae1a213 fwd="14.201.12.218" dyno=web.4 connect=1ms service=35ms status=422 bytes=288 protocol=https
  # Nov 21 14:15:28 cohortflow app/web.4:  ActionController::InvalidAuthenticityToken (ActionController::InvalidAuthenticityToken):
  # Nov 21 14:15:28 cohortflow app/web.4:    lib/rack_headers.rb:71:in `_call'
  # Nov 21 14:15:28 cohortflow app/web.4:    lib/rack_headers.rb:67:in `call'

  # Nov 21 14:15:29 cohortflow app/web.3:  [Scout] [11/21/18 04:15:28 +0000 web.3 (13)] INFO : [04:13] Delivering 98 Metrics for 26 requests and 10 Slow Transaction Traces and 0 Job Traces, Recorded from 1 processes.
  # Nov 21 14:15:30 cohortflow heroku/router:  at=info method=GET path="/product_tours.json?scope=&page=1&order=&p=%2Fapps%2Fcohortpay%2Fprovider_transactions&d=cohortflow.com" host=cohortflow.com request_id=d87ca75a-46cb-4a6e-b26f-6f79fb45c53e fwd="61.68.25.202" dyno=web.4 connect=1ms service=60ms status=304 bytes=815 protocol=https
  # Nov 21 14:15:30 cohortflow app/web.2:  Started GET "/apps/cohortpay/api/provider_transactions.json?scope=&page=1&order=" for 61.68.25.202 at 2018-11-21 04:15:30 +0000
  # Nov 21 14:15:30 cohortflow app/web.2:  Processing by AppsController#invoke_api as JSON
  # Nov 21 14:15:30 cohortflow app/web.2:    Parameters: {"scope"=>"", "page"=>"1", "order"=>"", "app"=>"cohortpay", "rest"=>"provider_transactions"}
  # Nov 21 14:15:30 cohortflow app/web.4:  Started GET "/product_tours.


  # Nov 21 19:50:49 cohortarrivals app/web.1:    Rendered vendor/bundle/ruby/2.3.0/bundler/gems/cohort-core-21de8356087e/app/views/cohort_core/_analytics.html.erb (0.1ms)
  # Nov 21 19:50:49 cohortarrivals app/web.1:  Completed 200 OK in 13ms (Views: 8.8ms | ActiveRecord: 2.1ms)
  # Nov 21 19:51:48 cohortarrivals heroku/router:  at=info method=GET path="/admin/tasks.json" host=cohortarrivals.com request_id=1beb0129-b2b9-49ed-a9ae-57b5e405ddc2 fwd="54.211.122.132" dyno=web.1 connect=0ms service=31ms status=200 bytes=894 protocol=https
  # Nov 21 19:51:48 cohortarrivals app/web.1:  Started GET "/admin/tasks.json" for 54.211.122.132 at 2018-11-21 09:51:47 +0000
  # Nov 21 19:51:48 cohortarrivals app/web.1:  Processing by TasksController#index as JSON
  # Nov 21 19:51:48 cohortarrivals app/web.1:  Completed 200 OK in 25ms (Views: 0.1ms | ActiveRecord: 14.2ms)
  # Nov 21 19:51:49 cohortarrivals app/web.1:  Started GET "/" for 185.93.3.92 at 2018-11-21 09:51:49 +0000
  # Nov 21 19:51:49 cohortarrivals app/web.1:  Processing by LandingController#index as HTML
  # Nov 21 19:51:49 cohortarrivals app/web.1:  Redirected to https://cohortarrivals.com/en
  # Nov 21 19:51:49 cohortarrivals app/web.1:  Filter chain halted as :set_locale rendered or redirected
  # Nov 21 19:51:49 cohortarrivals app/web.1:  Completed 302 Found in 1ms (ActiveRecord: 0.0ms)
  # Nov 21 19:51:50 cohortarrivals heroku/router:  at=info method=GET path="/" host=cohortarrivals.com request_id=37c8c83e-0c14-43e7-abb6-0718adda24f4 fwd="185.93.3.92" dyno=web.1 connect=1ms service=9ms status=302 bytes=511 protocol=https
  # Nov 21 19:51:50 cohortarrivals app/web.1:  Started GET "/en" for 185.93.3.92 at 2018-11-21 09:51:50 +0000
  # Nov 21 19:51:50 cohortarrivals app/web.1:  Processing by LandingController#index as HTML
  # Nov 21 19:51:50 cohortarrivals app/web.1:    Parameters: {"locale"=>"en"}
  # Nov 21 19:51:50 cohortarrivals app/web.1:    Rendered landing/_partner_login.html.erb (0.3ms)
  # Nov 21 19:51:50 cohortarrivals app/web.1:    Rendered layouts/_questions.html.erb (0.1ms)
  # Nov 21 19:51:50 cohortarrivals app/web.1:    Rendered landing/index.html.erb within layouts/application (3.4ms)
  # Nov 21 19:51:50 cohortarrivals app/web.1:    Rendered layouts/_typekit.html.erb (0.0ms)
  # Nov 21 19:51:50 cohortarrivals app/web.1:    Rendered layouts/_banner.html.erb (1.8ms)
  # Nov 21 19:51:50 cohortarrivals app/web.1:    Rendered layouts/_beacon.html.erb (0.1ms)
  # Nov 21 19:51:50 cohortarrivals app/web.1:    Rendered layouts/_footer.html.erb (1.8ms)
  # Nov 21 19:51:50 cohortarrivals heroku/router:  at=info method=GET path="/en" host=cohortarrivals.com request_id=9ef39b59-b274-44a6-a31e-a5b9a6af2cff fwd="185.93.3.92" dyno=web.1 connect=1ms service=20ms status=200 bytes=11753 protocol=https
  # Nov 21 19:51:50 cohortarrivals app/web.1:    Rendered vendor/bundle/ruby/2.3.0/bundler/gems/cohort-core-21de8356087e/app/views/cohort_core/_analytics.html.erb (0.1ms)
  # Nov 21 19:51:50 cohortarrivals app/web.1:  Completed 200 OK in 14ms (Views: 9.4ms | ActiveRecord: 2.1ms)
  # Nov 21 19:52:25 cohortarrivals heroku/router:  at=info method=GET path="/partner/dashboard_details/app_js?locale=en" host=cohortarrivals.com request_id=e02dfd62-d5ef-4460-856c-4c56cca29e64 fwd="43.225.33.50" dyno=web.1 connect=1ms service=10ms status=302 bytes=613 protocol=https
  # Nov 21 19:52:25 cohortarrivals app/web.1:  Started GET "/partner/dashboard_details/app_js?locale=en" for 43.225.33.50 at 2018-11-21 09:52:25 +0000
  # Nov 21 19:52:25 cohortarrivals app/web.1:  Processing by Partners::DashboardDetailsController#app_js as */*
  # Nov 21 19:52:25 cohortarrivals app/web.1:    Parameters: {"locale"=>"en"}
  # Nov 21 19:52:25 cohortarrivals app/web.1:  Redirected to https://cohortarrivals.com/assets/cohortflow-4238beabf739bd00dc99455099394c08.js
  # Nov 21 19:52:25 cohortarrivals app/web.1:  Completed 302 Found in 4ms (ActiveRecord: 2.1ms)
  # Nov 21 19:52:25 cohortarrivals heroku/router:  at=info method=GET path="/api/partner_bookings/student_details.json?reference=U5BB84" host=cohortarrivals.com request_id=834eb3db-eb49-4d5b-8000-a6c8948df8c3 fwd="43.225.33.50, 10.7.221.233,54.204.161.128" dyno=web.1 connect=0ms service=16ms status=304 bytes=434 protocol=https
  # Nov 21 19:52:26 cohortarrivals app/web.1:  Started GET "/api/partner_bookings/student_details.json?reference=U5BB84" for 54.204.161.128 at 2018-11-21 09:52:25 +0000
  # Nov 21 19:52:26 cohortarrivals app/web.1:  Processing by API::PartnerBookingsController#student_details as JSON
  # Nov 21 19:52:26 cohortarrivals app/web.1:    Parameters: {"reference"=>"U5BB84"}
  # Nov 21 19:52:26 cohortarrivals app/web.1:  Completed 200 OK in 11ms (Views: 0.3ms | ActiveRecord: 5.3ms)





  # Nov 21 14:14:52 cohortflow app/web.3: Completed 304 Not Modified in 71ms (Views: 0.9ms | ActiveRecord: 3.3ms)
  # Nov 21 14:14:52 cohortflow heroku/router: at=info method=POST path="/students/110215/documents.json" host=cohortflow.com request_id=038cc91a-8848-48e9-8931-ffb46942f80b fwd="202.166.198.43" dyno=web.5 connect=0ms service=98ms status=200 bytes=1375 protocol=https
  # Nov 21 14:14:52 cohortflow app/web.5: Started POST "/students/110215/documents.json" for 202.166.198.43 at 2018-11-21 04:14:52 +0000
  # Nov 21 14:14:52 cohortflow app/web.5: Processing by Students::DocumentsController#create as JSON
  # Nov 21 14:14:52 cohortflow app/web.5:   Parameters: {"document"=>{"direct_upload_url"=>"https://cohortflow-uploads.s3.amazonaws.com/uploads/1542773659498-sqag563cip-821c1642d82ee8613f1b7b553468b56d/Offer.pdf", "student_id"=>110215, "tags"=>["IIBIT LOO"], "folder"=>"Offer Letter Documents"}, "student_id"=>"110215"}
  # Nov 21 14:14:52 cohortflow app/web.5: [ActiveJob] Enqueued DocumentProcessor (Job ID: 1d7e28ad-dfbe-432d-85e7-1f23be45c9b6) to QueueClassic(default) with arguments: gid://cohortflow/Document/58982
  # Nov 21 14:14:52 cohortflow app/web.5: Completed 200 OK in 73ms (Views: 6.3ms | ActiveRecord: 9.8ms)
  # Nov 21 14:14:52 cohortflow app/worker.1: [ActiveJob] [DocumentProcessor] [1d7e28ad-dfbe-432d-85e7-1f23be45c9b6] Performing DocumentProcessor from QueueClassic(default) with arguments: gid://cohortflow/Document/58982
  # Nov 21 14:14:52 cohortflow app/worker.1: [ActiveJob] [DocumentProcessor] [1d7e28ad-dfbe-432d-85e7-1f23be45c9b6] Command :: file -b --mime '/tmp/6bb24468956384c482a8b5a901fb638320181121-4-2e2y6p.pdf'
  # Nov 21 14:14:52 cohortflow app/worker.1: [ActiveJob] [DocumentProcessor] [1d7e28ad-dfbe-432d-85e7-1f23be45c9b6] Command :: identify -format '%wx%h,%[exif:orientation]' '/tmp/6bb24468956384c482a8b5a901fb638320181121-4-8wmi67.pdf[0]' 2>/dev/null
  # Nov 21 14:14:53 cohortflow app/worker.1: [ActiveJob] [DocumentProcessor] [1d7e28ad-dfbe-432d-85e7-1f23be45c9b6] Command :: convert '/tmp/6bb24468956384c482a8b5a901fb638320181121-4-8wmi67.pdf[0]' -auto-orient -resize "100x100>" '/tmp/6b63b793d8cdad1d836056aad656769a20181121-4-hfn7zc.png'
  # Nov 21 14:14:53 cohortflow app/web.4: Started GET "/students/110215/documents/folders.json" for 202.166.198.43 at 2018-11-21 04:14:52 +0000
  # Nov 21 14:14:53 cohortflow app/web.1: Started GET "/students/110215/documents.json?scope=&page=1&order=" for 202.166.198.43 at 2018-11-21 04:14:52 +0000
  # Nov 21 14:14:53 cohortflow app/web.4: Processing by Students::DocumentsController#folders as JSON
  # Nov 21 14:14:53 cohortflow app/web.4:   Parameters: {"student_id"=>"110215", "document"=>{}}
  # Nov 21 14:14:53 cohortflow app/web.4: Completed 200 OK in 49ms (Views: 10.1ms | ActiveRecord: 4.6ms)
  # Nov 21 14:14:53 cohortflow app/web.1: Processing by Students::DocumentsController#index as JSON
  # Nov 21 14:14:53 cohortflow app/web.1:   Parameters: {"scope"=>"", "page"=>"1", "order"=>"", "student_id"=>"110215"}
  # Nov 21 14:14:53 cohortflow heroku/router: at=info method=GET path="/students/110215/documents/folders.json" host=cohortflow.com request_id=c2dc3ff8-68b4-4040-ba9e-29967dbba883 fwd="202.166.198.43" dyno=web.4 connect=1ms service=67ms status=200 bytes=920 protocol=https
  # Nov 21 14:14:53 cohortflow heroku/worker.1: source=worker.1 dyno=heroku.27066801.51a1a4b6-34cf-4c7b-a2bc-e8711b1e2433 sample#load_avg_1m=0.29 sample#load_avg_5m=0.09 sample#load_avg_15m=0.04
  # Nov 21 14:14:53 cohortflow heroku/worker.1: source=worker.1 dyno=heroku.27066801.51a1a4b6-34cf-4c7b-a2bc-e8711b1e2433 sample#memory_total=323.45MB sample#memory_rss=305.09MB sample#memory_cache=18.36MB sample#memory_swap=0.00MB sample#memory_pgpgin=166255pages sample#memory_pgpgout=83451pages sample#memory_quota=512.00MB
  # Nov 21 14:14:53 cohortflow heroku/router: at=info method=GET path="/students/110215/documents.json?scope=&page=1&order=" host=cohortflow.com request_id=880365b6-12e0-4661-a83f-24cb3712d253 fwd="202.166.198.43" dyno=web.1 connect=0ms service=307ms status=200 bytes=3560 protocol=https
  # Nov 21 14:14:53 cohortflow app/worker.1: [ActiveJob] [DocumentProcessor] [1d7e28ad-dfbe-432d-85e7-1f23be45c9b6] Command :: file -b --mime '/tmp/6bb24468956384c482a8b5a901fb638320181121-4-pcc85j.pdf'
  # Nov 21 14:14:53 cohortflow app/worker.1: [ActiveJob] [DocumentProcessor] [1d7e28ad-dfbe-432d-85e7-1f23be45c9b6] [paperclip] saving documents/docs/original/7830723a51b5f0ba06a6bce855ff5eb78e318849.pdf
  # Nov 21 14:14:53 cohortflow app/worker.1: [ActiveJob] [DocumentProcessor] [1d7e28ad-dfbe-432d-85e7-1f23be45c9b6] [AWS S3 200 0.075288 0 retries] put_object(:acl=>:private,:bucket_name=>"cohortflow-uploads",:content_length=>164410,:content_type=>"application/pdf",:data=>Paperclip::UriAdapter: Offer.pdf,:key=>"documents/docs/original/7830723a51b5f0ba06a6bce855ff5eb78e318849.pdf")
  # Nov 21 14:14:53 cohortflow app/worker.1: [ActiveJob] [DocumentProcessor] [1d7e28ad-dfbe-432d-85e7-1f23be45c9b6] [paperclip] saving documents/docs/thumbnail/2d2b2afd7c979f1b1f5a32981881956cabfe5924.png
  # Nov 21 14:14:53 cohortflow app/worker.1: [ActiveJob] [DocumentProcessor] [1d7e28ad-dfbe-432d-85e7-1f23be45c9b6] [AWS S3 200 0.030745 0 retries] put_object(:acl=>:private,:bucket_name=>"cohortflow-uploads",:content_length=>10016,:content_type=>"image/png",:data=>Paperclip::FileAdapter: 6b63b793d8cdad1d836056aad656769a20181121-4-hfn7zc.png,:key=>"documents/docs/thumbnail/2d2b2afd7c979f1b1f5a32981881956cabfe5924.png")
  # Nov 21 14:14:53 cohortflow app/worker.1: [ActiveJob] [DocumentProcessor] [1d7e28ad-dfbe-432d-85e7-1f23be45c9b6] Performed DocumentProcessor from QueueClassic(default) in 733.25ms
  # Nov 21 14:14:53 cohortflow app/web.1: Completed 200 OK in 283ms (Views: 34.7ms | ActiveRecord: 16.7ms)
  # Nov 21 14:14:54 cohortflow heroku/web.2: source=web.2 dyno=heroku.27066801.eb55d644-1c29-40f7-a680-5f3ecb0bddf1 sample#load_avg_1m=0.01 sample#load_avg_5m=0.06 sample#load_avg_15m=0.06
  # Nov 21 14:14:54 cohortflow heroku/web.2: source=web.2 dyno=heroku.27066801.eb55d644-1c29-40f7-a680-5f3ecb0bddf1 sample#memory_total=681.93MB sample#memory_rss=499.38MB sample#memory_cache=0.44MB sample#memory_swap=182.11MB sample#memory_pgpgin=182644pages sample#memory_pgpgout=60822pages sample#memory_quota=512.00MB
  # Nov 21 14:14:54 cohortflow heroku/web.2: Process running mem=681M(133.1%)
  # Nov 21 14:14:54 cohortflow heroku/web.2: Error R14 (Memory quota exceeded)
  # Nov 21 14:14:56 cohortflow app/web.1: Started GET "/students" for 112.134.200.63 at 2018-11-21 04:14:56 +0000
  # Nov 21 14:14:56 cohortflow app/web.1: Processing by StudentsController#index as HTML
  # Nov 21 14:14:56 cohortflow heroku/router: at=info method=GET path="/" host=cohortflow.com request_id=753a86d1-00b4-4d55-b817-eae9a34cb9b6 fwd="82.103.139.165" dyno=web.5 connect=0ms service=14ms status=302 bytes=602 protocol=https
  # Nov 21 14:14:57 cohortflow app/web.5: Started GET "/" for 82.103.139.165 at 2018-11-21 04:14:56 +0000
  # Nov 21 14:14:57 cohortflow app/web.5: Processing by LandingController#index as HTML
  # Nov 21 14:14:57 cohortflow app/web.5: Redirected to https://cohortgo.com
  # Nov 21 14:14:57 cohortflow app/web.5: Completed 302 Found in 5ms (ActiveRecord: 1.1ms)
  # Nov 21 14:14:57 cohortflow app/heroku-postgres: source=DATABASE addon=postgresql-fluffy-94567 sample#current_transaction=7967483 sample#db_size=1543969304bytes sample#tables=162 sample#active-connections=13 sample#waiting-connections=0 sample#index-cache-hit-rate=0.99989 sample#table-cache-hit-rate=0.99931 sample#load-avg-1m=0.05 sample#load-avg-5m=0.045 sample#load-avg-15m=0.015 sample#read-iops=0.0064935 sample#write-iops=0.011769 sample#memory-total=4045048kB sample#memory-free=220156kB sample#memory-cached=2870104kB sample#memory-postgres=556444kB
  # Nov 21 14:14:58 cohortflow heroku/web.4: source=web.4 dyno=heroku.27066801.10cb480b-5f85-48c8-a788-87002d69fdb4 sample#load_avg_1m=0.00 sample#load_avg_5m=0.00 sample#load_avg_15m=0.01
  # Nov 21 14:14:58 cohortflow heroku/web.4: source=web.4 dyno=heroku.27066801.10cb480b-5f85-48c8-a788-87002d69fdb4 sample#memory_total=590.29MB sample#memory_rss=429.68MB sample#memory_cache=0.48MB sample#memory_swap=160.12MB sample#memory_pgpgin=156757pages sample#memory_pgpgout=97224pages sample#memory_quota=512.00MB
  # Nov 21 14:14:58 cohortflow heroku/web.4: Process running mem=590M(115.2%)
  # Nov 21 14:14:58 cohortflow heroku/web.4: Error R14 (Memory quota exceeded)
  # Nov 21 14:15:00 cohortflow heroku/router: at=info method=GET path="/product_tours.json?scope=&page=1&order=&p=%2Fapps%2Fcohortpay%2Fagent_transactions%2FCPS00228656&d=cohortflow.com" host=cohortflow.com request_id=7c16e9fe-0a88-4946-962f-ca9708be4aeb fwd="139.194.38.153" dyno=web.4 connect=0ms service=17ms status=200 bytes=912 protocol=https
  # Nov 21 14:15:00 cohortflow app/web.4: Started GET "/product_tours.json?scope=&page=1&order=&


  # Nov 21 14:12:39 cohortflow app/web.1: [ActiveJob] Enqueued DocumentProcessor (Job ID: 58beb8bf-3a2a-4bf1-84c8-b52220886b02) to QueueClassic(default) with arguments: gid://cohortflow/Document/58980
  # Nov 21 14:12:39 cohortflow app/worker.1: [ActiveJob] [DocumentProcessor] [58beb8bf-3a2a-4bf1-84c8-b52220886b02] Performing DocumentProcessor from QueueClassic(default) with arguments: gid://cohortflow/Document/58980
  # Nov 21 14:12:39 cohortflow heroku/router: at=info method=POST path="/students/69434/documents.json" host=cohortflow.com request_id=ec06a4df-1216-4f3c-9888-35fbec975878 fwd="112.134.142.17" dyno=web.1 connect=1ms service=411ms status=200 bytes=1390 protocol=https
  # Nov 21 14:12:39 cohortflow app/web.1: Completed 200 OK in 265ms (Views: 12.7ms | ActiveRecord: 21.8ms)
  # Nov 21 14:12:39 cohortflow app/worker.1: [ActiveJob] [DocumentProcessor] [58beb8bf-3a2a-4bf1-84c8-b52220886b02] Command :: file -b --mime '/tmp/a8a40a5e9a8f89fe1457ee7ba6f8606920181121-4-1ajv7if.pdf'
  # Nov 21 14:12:39 cohortflow app/worker.1: [ActiveJob] [DocumentProcessor] [58beb8bf-3a2a-4bf1-84c8-b52220886b02] Command :: identify -format '%wx%h,%[exif:orientation]' '/tmp/693f7e9ac29305866852e479e89b01dc20181121-4-r4tu1d.pdf[0]' 2>/dev/null
  # Nov 21 14:12:40 cohortflow app/worker.1: [ActiveJob] [DocumentProcessor] [58beb8bf-3a2a-4bf1-84c8-b52220886b02] Command :: convert '/tmp/693f7e9ac29305866852e479e89b01dc20181121-4-r4tu1d.pdf[0]' -auto-orient -resize "100x100>" '/tmp/bbb85d99a8d48decd1e023252b629f7f20181121-4-1k9svdo.png'
  # Nov 21 14:12:40 cohortflow app/web.2: Started GET "/students/69434/documents/folders.json" for 112.134.142.17 at 2018-11-21 04:12:40 +0000
  # Nov 21 14:12:40 cohortflow app/web.2: Processing by Students::DocumentsController#folders as JSON
  # Nov 21 14:12:40 cohortflow app/web.2:   Parameters: {"student_id"=>"69434", "document"=>{}}
  # Nov 21 14:12:40 cohortflow app/web.2: Completed 200 OK in 70ms (Views: 7.2ms | ActiveRecord: 8.6ms)
  # Nov 21 14:12:40 cohortflow heroku/router: at=info method=GET path="/students/69434/documents/folders.json" host=cohortflow.com request_id=aff7b63c-37c1-43d9-849a-9fa481966766 fwd="112.134.142.17" dyno=web.2 connect=0ms service=79ms status=304 bytes=815 protocol=https
  # Nov 21 14:12:40 cohortflow app/web.2: Started GET "/students/69434/documents.json?scope=&page=1&order=" for 112.134.142.17 at 2018-11-21 04:12:40 +0000
  # Nov 21 14:12:40 cohortflow app/worker.1: [ActiveJob] [DocumentProcessor] [58beb8bf-3a2a-4bf1-84c8-b52220886b02] Command :: file -b --mime '/tmp/a8a40a5e9a8f89fe1457ee7ba6f8606920181121-4-1utl46u.pdf'
  # Nov 21 14:12:40 cohortflow app/worker.1: [ActiveJob] [DocumentProcessor] [58beb8bf-3a2a-4bf1-84c8-b52220886b02] [paperclip] saving documents/docs/original/385ee8a1a86aa678792c773979f1c23ac74b409b.pdf
  # Nov 21 14:12:40 cohortflow app/worker.1: [ActiveJob] [DocumentProcessor] [58beb8bf-3a2a-4bf1-84c8-b52220886b02] [AWS S3 200 0.104101 0 retries] put_object(:acl=>:private,:bucket_name=>"cohortflow-uploads",:content_length=>120857,:content_type=>"application/pdf",:data=>Paperclip::UriAdapter: CoE+Certificate+-+nahoor.pdf,:key=>"documents/docs/original/385ee8a1a86aa678792c773979f1c23ac74b409b.pdf")
  # Nov 21 14:12:40 cohortflow app/worker.1: [ActiveJob] [DocumentProcessor] [58beb8bf-3a2a-4bf1-84c8-b52220886b02] [paperclip] saving documents/docs/thumbnail/319775463634f4024235c1f666bf54493be63a15.png
  # Nov 21 14:12:40 cohortflow app/web.2: Processing by Students::DocumentsController#index as JSON
  # Nov 21 14:12:40 cohortflow app/web.2:   Parameters: {"scope"=>"", "page"=>"1", "order"=>"", "student_id"=>"69434"}
  # Nov 21 14:12:40 cohortflow app/worker.1: [ActiveJob] [DocumentProcessor] [58beb8bf-3a2a-4bf1-84c8-b52220886b02] [AWS S3 200 0.038392 0 retries] put_object(:acl=>:private,:bucket_name=>"cohortflow-uploads",:content_length=>8229,:content_type=>"image/png",:data=>Paperclip::FileAdapter: bbb85d99a8d48decd1e023252b629f7f20181121-4-1k9svdo.png,:key=>"documents/docs/thumbnail/319775463634f4024235c1f666bf54493be63a15.png")
  # Nov 21 14:12:40 cohortflow app/worker.1: [ActiveJob] [DocumentProcessor] [58beb8bf-3a2a-4bf1-84c8-b52220886b02] Performed DocumentProcessor from QueueClassic(default) in 901.27ms



  # Nov 21 15:10:22 cohortflow app/web.1:  Started PUT "/admin/organisations/ap:11122/products.json" for 54.167.139.215 at 2018-11-21 05:10:22 +0000
  # Nov 21 15:10:22 cohortflow app/web.1:  Processing by Admin::Organisations::ProductsController#update as JSON
  # Nov 21 15:10:22 cohortflow app/web.1:    Parameters: {"app_configs"=>{}, "enabled_apps"=>["cohortarrivals"], "app_features"=>nil, "organisation_contract_map"=>{"cohortarrivals"=>1}, "organisation_id"=>"ap:11122", "product"=>{}}
  # Nov 21 15:10:23 cohortflow app/postgres.12086:  [DATABASE] [18-1]  sql_error_code = 23502 ERROR:  null value in column "app_features" violates not-null constraint
  # Nov 21 15:10:23 cohortflow app/postgres.12086:  [DATABASE] [18-2]  sql_error_code = 23502 DETAIL:  Failing row contains (375643, Ahead Edu Vivian, UTC, null, null, null, 435342, 2018-11-21 05:10:22.195009, 2018-11-21 05:10:22.95809, null, null, null, null, null, {}, {}, f, {}, null, en, null, agent, null, null, null, null, unknown, null, f, {cohortarrivals}, null, null, null, null, null, null, null, new, {}, 1, null, basic, null, null, null, null, null, f, null, null, null, null, null, null, f, null, default, 11122, fw-p5xgatj98d, pending, null, null, null, null, null, null, {}).
  # Nov 21 15:10:23 cohortflow app/postgres.12086:  [DATABASE] [18-3]  sql_error_code = 23502 STATEMENT:  UPDATE "organisations" SET "app_features" = $1, "enabled_apps" = $2, "updated_at" = $3 WHERE "organisations"."id" = $4
  # Nov 21 15:10:23 cohortflow app/web.1:  Completed 500 Internal Server Error in 244ms (ActiveRecord: 101.1ms)
  # Nov 21 15:10:23 cohortflow app/web.1:  ActiveRecord::StatementInvalid (PG::NotNullViolation: ERROR:  null value in column "app_features" violates not-null constraint
  # Nov 21 15:10:23 cohortflow app/web.1:  DETAIL:  Failing row contains (375643, Ahead Edu Vivian, UTC, null, null, null, 435342, 2018-11-21 05:10:22.195009, 2018-11-21 05:10:22.95809, null, null, null, null, null, {}, {}, f, {}, null, en, null, agent, null, null, null, null, unknown, null, f, {cohortarrivals}, null, null, null, null, null, null, null, new, {}, 1, null, basic, null, null, null, null, null, f, null, null, null, null, null, null, f, null, default, 11122, fw-p5xgatj98d, pending, null, null, null, null, null, null, {}).
  # Nov 21 15:10:23 cohortflow app/web.1:  : UPDATE "organisations" SET "app_features" = $1, "enabled_apps" = $2, "updated_at" = $3 WHERE "organisations"."id" = $4):
  # Nov 21 15:10:23 cohortflow app/web.1:    app/controllers/admin/organisations/products_controller.rb:10:in `update'
  # Nov 21 15:10:23 cohortflow app/web.1:    lib/rack_headers.rb:71:in `_call'
  # Nov 21 15:10:23 cohortflow app/web.1:    lib/rack_headers.rb:67:in `call'
  # Nov 21 15:10:23 cohortflow app/worker.1:  [ActiveJob] [SyncService::PushJob] [f4f879d7-5f96-43b0-919e-d765bf3d1cd5] Failed to sync object: '{"status":500,"error":"Internal Server Error"}'
  # Nov 21 15:10:23 cohortflow app/worker.1:  [ActiveJob] [SyncService::PushJob] [f4f879d7-5f96-43b0-919e-d765bf3d1cd5] Performed SyncService::PushJob from QueueClassic(default) in 1991.14ms
  # Nov 21 15:10:23 cohortflow app/worker.1:  [ActiveJob] [SyncService::PushJob] [2db2210f-7eac-4929-8bad-02724e206e61] Performing SyncService::PushJob from QueueClassic(default) with arguments: gid://cohortflow/ContactProduct/12832, "knox+https://cohort-knowledge-graph.herokuapp.com/listeners/contact_products/push.json", gid://cohortflow/ObjectSyncStatus/40219
  # Nov 21 15:10:23 cohortflow app/worker.1:  [ActiveJob] [SyncService::PushJob] [2db2210f-7eac-4929-8bad-02724e206e61] Performed SyncService::PushJob from QueueClassic(default) in 145.35ms
  # Nov 21 15:10:23 cohortflow app/worker.1:  [ActiveJob] [IntercomCompanySyncJob] [4fb0a985-d8dc-4ef5-ba74-ffdf315fecff] Performing IntercomCompanySyncJob from QueueClassic(default) with arguments: gid://cohortflow/Organisation/375643
  # Nov 21 15:10:23 cohortflow app/worker.1:  [ActiveJob] [IntercomCompanySyncJob] [4fb0a985-d8dc-4ef5-ba74-ffdf315fecff] Performed IntercomCompanySyncJob from QueueClassic(default) in 0.11ms


  # Nov 20 20:22:59 portal-provisioning app/worker.1:  /app/vendor/bundle/ruby/2.5.0/gems/bundler-1.15.2/lib/bundler/vendor/thor/lib/thor/base.rb:444:in `start'
  # Nov 20 20:22:59 portal-provisioning app/worker.1:  /app/vendor/bundle/ruby/2.5.0/gems/bundler-1.15.2/lib/bundler/cli.rb:10:in `start'
  # Nov 20 20:22:59 portal-provisioning app/worker.1:  /app/vendor/bundle/ruby/2.5.0/gems/bundler-1.15.2/exe/bundle:30:in `block in <top (required)>'
  # Nov 20 20:22:59 portal-provisioning app/worker.1:  /app/vendor/bundle/ruby/2.5.0/gems/bundler-1.15.2/lib/bundler/friendly_errors.rb:121:in `with_friendly_errors'
  # Nov 20 20:22:59 portal-provisioning app/worker.1:  /app/vendor/bundle/ruby/2.5.0/gems/bundler-1.15.2/exe/bundle:22:in `<top (required)>'
  # Nov 20 20:22:59 portal-provisioning app/worker.1:  /app/bin/bundle:3:in `load'
  # Nov 20 20:22:59 portal-provisioning app/worker.1:  /app/bin/bundle:3:in `<main>'
  # Nov 20 20:22:59 portal-provisioning app/worker.1:  E, [2018-11-20T10:22:58.767090 #4] ERROR -- : Retrying AgentProfileProvision::User in exponentially_longer seconds, due to a FlowService::FlowResponseException. The original exception was #<RestClient::BadRequest: 400 Bad Request>.
  # Nov 20 20:22:59 portal-provisioning app/worker.1:  I, [2018-11-20T10:22:58.770278 #4]  INFO -- : [ActiveJob] Enqueued AgentProfileProvision::User (Job ID: b30433ee-58ed-4c05-bacc-1d695fb4be88) to QueueClassic(default) at 2018-11-20 10:44:36 UTC with arguments: #<GlobalID:0x00000000072e9300 @uri=#<URI::GID gid://cohortgo-portal-provisioning/PartnerApp/1>>, #<GlobalID:0x00000000072e8ae0 @uri=#<URI::GID gid://cohortgo-portal-provisioning/Activation/22>>
  # Nov 20 20:23:11 scaler app/worker.1:  2018-11-20 10:23:11 +0000: INFO: Checking: cohortpay-contact:worker
  # Nov 20 20:23:11 scaler app/worker.1:  2018-11-20 10:23:11 +0000: INFO: Checking: cohortflow:worker
  # Nov 20 20:23:11 scaler app/worker.1:  2018-11-20 10:23:11 +0000: INFO: Checking: cohortpay-transact:worker
  # Nov 20 20:23:11 scaler app/worker.1:  2018-11-20 10:23:11 +0000: INFO: Checking: oshcaustralia:worker
  # Nov 20 20:23:11 scaler app/worker.1:  2018-11-20 10:23:11 +0000: INFO: Checking: cohort-deploy:worker
  # Nov 20 20:23:11 scaler app/worker.1:  2018-11-20 10:23:11 +0000: INFO: Checking: cohortpay:worker
  # Nov 20 20:23:12 scaler app/worker.1:  2018-11-20 10:23:11 +0000: INFO: Checking: cohort-knowledge-graph:worker
  # Nov 20 20:23:12 scaler app/worker.1:  2018-11-20 10:23:11 +0000: INFO: Checking: cohortgo:worker
  # Nov 20 20:23:12 scaler app/worker.1:  2018-11-20 10:23:11 +0000: INFO: Checking: cohortgo-portal-provisioning:worker
  # Nov 20 20:23:54 portal-provisioning app/worker.1:  D, [2018-11-20T10:23:53.871019 #4] DEBUG -- :   PartnerApp Load (1.4ms)  SELECT  "partner_apps".* FROM "partner_apps" WHERE "partner_apps"."id" = $1 LIMIT $2  [["id", 1], ["LIMIT", 1]]
  # Nov 20 20:23:54 portal-provisioning app/worker.1:  D, [2018-11-20T10:23:53.873287 #4] DEBUG -- :   Activation Load (1.4ms)  SELECT  "activations".* FROM "activations" WHERE "activations"."id" = $1 LIMIT $2  [["id", 22], ["LIMIT", 1]]
  # Nov 20 20:23:54 portal-provisioning app/worker.1:  I, [2018-11-20T10:23:53.874194 #4]  INFO -- : [ActiveJob] [AgentProfileProvision::Activate] [ecbf936b-c888-4cff-ab6a-8e3989575360] Performing AgentProfileProvision::Activate (Job ID: ecbf936b-c888-4cff-ab6a-8e3989575360) from QueueClassic(default) with arguments: #<GlobalID:0x00000000071b4e58 @uri=#<URI::GID gid://cohortgo-portal-provisioning/PartnerApp/1>>, #<GlobalID:0x00000000071b4638 @uri=#<URI::GID gid://cohortgo-portal-provisioning/Activation/22>>
  # Nov 20 20:23:54 portal-provisioning app/worker.1:  D, [2018-11-20T10:23:53.876394 #4] DEBUG -- : [ActiveJob] [AgentProfileProvision::Activate] [ecbf936b-c888-4cff-ab6a-8e3989575360]   AgentProfile Load (1.3ms)  SELECT  "agent_profiles".* FROM "agent_profiles" WHERE "agent_profiles"."id" = $1 LIMIT $2  [["id", 11113], ["LIMIT", 1]]
  # Nov 20 20:23:54 portal-provisioning app/worker.1:  E, [2018-11-20T10:23:54.147463 #4] ERROR -- : [ActiveJob] [AgentProfileProvision::Activate] [ecbf936b-c888-4cff-ab6a-8e3989575360] Error performing AgentProfileProvision::Activate (Job ID: ecbf936b-c888-4cff-ab6a-8e3989575360) from QueueClassic(default) in 272.99ms: AgentProfileProvision::Base::ProvisionFailure (User does not exist):
  # Nov 20 20:23:54 portal-provisioning app/worker.1:  /app/app/jobs/agent_profile_provision/activate.rb:6:in `perform'
  # Nov 20 20:23:54 portal-provisioning app/worker.1:  /app/vendor/bundle/ruby/2.5.0/gems/activejob-5.2.0/lib/active_job/execution.rb:39:in `block in perform_now'
  # Nov 20 20:23:54 portal-provisioning app/worker.1:  /app/vendor/bundle/ruby/2.5.0/gems/activesupport-5.2.0/lib/active_support/callbacks.rb:109:in `block in run_callbacks'
  # Nov 20 20:23:54 portal-provisioning app/worker.1:  /app/vendor/bundle/ruby/2.5.0/gems/i18n-1.0.1/lib/i18n.rb:284:in `with_locale'
  # Nov 20 20:23:54 portal-provisioning app/worker.1:  /app/vendor/bundle/ruby/2.5.0/gems/activejob-5.2.0/lib/active_job/translation.rb:9:in `block (2 levels) in <module:Translation>'
  # Nov 20 20:23:54 portal-provisioning app/worker.1:  /app/vendor/bundle/ruby/2.5.0/gems/activesupport-5.2.0/lib/active_support/callbacks.rb:118:in `instance_exec'
  # Nov 20 20:23:54 portal-provisioning app/worker.1:  /app/vendor/bundle/ruby/2.5.0/gems/activesupport-5.2.0/lib/active_s
end
