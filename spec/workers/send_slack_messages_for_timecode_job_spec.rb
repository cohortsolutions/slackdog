require './slack'

RSpec.describe SendSlackMessagesForTimecodeJob do
  describe '#perform' do
    context 'exception logs' do
      let(:envelope) { {'channel' => '123', 'ts' => '456'} }

      it 'formats validation errors' do
        log_lines = File.readlines('./spec/fixtures/errors/validation_error_dob.txt')
        allow(Papertrail).to receive(:log_lines_between).and_return(log_lines)

        attachments = [{
          "color" => "danger",
          "fallback" => "[some_app] *Validation failed* 'Dob must be at least four years old'.",
          "mrkdwn_in" => ['pretext', 'text'],
          "pretext" => nil,
          "text" => File.read('./spec/fixtures/formatted/validation_error_dob.txt').strip
        }]

        expect(SlackService).to receive(:post_reply).with('123', '456', attachments)
        SendSlackMessagesForTimecodeJob.perform_now('500', '20181120150057', envelope)
      end

      it 'formats database errors' do
        log_lines = File.readlines('./spec/fixtures/errors/notnull_constraint_violation.txt')
        allow(Papertrail).to receive(:log_lines_between).and_return(log_lines)

        stub_github('slackdog/test', 'app/controllers/admin/organisations/products_controller.rb')
        
        pretext = <<~EOM
        `app_features` must have a value (database constraint)
        ```
          def update
            resource = find_resource(params)
            resource.update_attributes!(app_features: nil)
            render json: resource.to_json
          end
        ```
        EOM

        attachments = [{
          'color' => 'danger',
          'fallback' => "[some_app] *PG::NotNullViolation: ERROR* 'null value in column \"app_features\" violates not-null constraint'.",
          'mrkdwn_in' => ['pretext', 'text'],
          'pretext' => pretext.strip,
          'text' => File.read('./spec/fixtures/formatted/notnull_constraint_violation.txt').strip
        }]

        expect(SlackService).to receive(:post_reply).with('123', '456', attachments)
        SendSlackMessagesForTimecodeJob.perform_now('500', '20181120150057', envelope)
      end

      it 'formats nil reference errors' do
        log_lines = File.readlines('./spec/fixtures/errors/undefined_method_nilclass.txt')
        allow(Papertrail).to receive(:log_lines_between).and_return(log_lines)

        github_request = stub_github('slackdog/test', 'app/controllers/concerns/some_helper_concern.rb')

        pretext = <<~EOM
        `@company` is null
        ```
          def failing_method
            # this is the method that caused the exception
            result = @company.foo
            return result.empty?
          end
        ```
        EOM

        attachments = [{
          'color' => 'danger',
          'fallback' => "[some_app] *NoMethodError* 'undefined method `foo' for nil:NilClass'",
          'mrkdwn_in' => ['pretext', 'text'],
          'pretext' => pretext.strip,
          'text' => File.read('./spec/fixtures/formatted/undefined_method_nilclass.txt').strip
        }]

        expect(SlackService).to receive(:post_reply).with('123', '456', attachments)
        SendSlackMessagesForTimecodeJob.perform_now('500', '20181120150057', envelope)

        expect(github_request).to have_been_requested
      end

      it 'formats nil reference errors with multiple candidates' do
        log_lines = File.readlines('./spec/fixtures/errors/undefined_method_nilclass_multiple_candidates.txt')
        allow(Papertrail).to receive(:log_lines_between).and_return(log_lines)

        github_request = stub_github('slackdog/test', 'app/controllers/concerns/some_helper_concern.rb')

        pretext = <<~EOM
        Either `self`, or `meta` is null
        ```

          def other_failing_method
            result = "\#{self.foo} - \#{obj.bar} - \#{self.meta.foo}"
            return result.empty?
          end
        ```
        EOM

        attachments = [{
          'color' => 'danger',
          'fallback' => "[some_app] *NoMethodError* 'undefined method `foo' for nil:NilClass'",
          'mrkdwn_in' => ['pretext', 'text'],
          'pretext' => pretext.strip,
          'text' => File.read('./spec/fixtures/formatted/undefined_method_nilclass_multiple_candidates.txt').strip
        }]

        expect(SlackService).to receive(:post_reply).with('123', '456', attachments)
        SendSlackMessagesForTimecodeJob.perform_now('500', '20181120150057', envelope)

        expect(github_request).to have_been_requested
      end
    end

    it 'calls out to the Papertrail Service to get log lines' do
      error_code = '500'
      timestamp = '20190416085903'
      reply_to = '1555446899.000700'

      stub_papertrail('./spec/fixtures/errors/papertrail_cache.txt')
      SendSlackMessagesForTimecodeJob.perform_now(error_code, timestamp, reply_to)
    end

    # context 'active job logs' do
    #   it 'formats using the job template' do
    #     log_lines = File.readlines('./spec/fixtures/errors/activerecord_failure.txt')
    #
    #     allow(Papertrail).to receive(:log_lines_between).and_return(log_lines)
    #
    #     attachments = Slack.message({'text' => 'Error Code: 500 - 20181120150057'})
    #     expect(attachments).to eq [{
    #       "fields" => [{
    #         "short"=>true,
    #         "title"=>"Job",
    #         "value"=>"SyncService::PushJob"
    #       }, {
    #         "short"=>true,
    #         "title"=>"Job ID",
    #         "value"=>"f4f879d7"
    #       }, {
    #         "short"=>true,
    #         "title"=>"Status",
    #         "value"=>"Finished"
    #       }, {
    #         "short"=>true,
    #         "title"=>"Server",
    #         "value"=>"cohortflow:app/worker.1"
    #       }],
    #       "mrkdwn_in"=>["text"]
    #     }, {
    #       "fields" => [{
    #         "short"=>true,
    #         "title"=>"Job",
    #         "value"=>"SyncService::PushJob"
    #       }, {
    #         "short"=>true,
    #         "title"=>"Job ID",
    #         "value"=>"2db2210f"
    #       }, {
    #         "short"=>true,
    #         "title"=>"Status",
    #         "value"=>"Finished"
    #       }, {
    #         "short"=>true,
    #         "title"=>"Server",
    #         "value"=>"cohortflow:app/worker.1"
    #       }],
    #       "mrkdwn_in"=>["text"]
    #     }, {
    #       "fields"=> [{
    #         "short"=>true,
    #         "title"=>"Job",
    #         "value"=>"IntercomCompanySyncJob"
    #       }, {
    #         "short"=>true,
    #         "title"=>"Job ID",
    #         "value"=>"4fb0a985"
    #       }, {
    #         "short"=>true,
    #         "title"=>"Status",
    #         "value"=>"Finished"
    #       }, {
    #         "short"=>true,
    #         "title"=>"Server",
    #         "value"=>"cohortflow:app/worker.1"
    #       }],
    #       "mrkdwn_in"=>["text"]
    #     }, {
    #       "color"=>"danger",
    #       "fallback"=> "[portal-provisioning] *AgentProfileProvision::Activate* 'User does not exist'.",
    #       "fields"=> [{
    #         "short"=>true,
    #         "title"=>"Job",
    #         "value"=>"AgentProfileProvision::Activate"
    #       }, {
    #         "short"=>true,
    #         "title"=>"Job ID",
    #         "value"=>"ecbf936b"
    #       }, {
    #         "short"=>true,
    #         "title"=>"Status",
    #         "value"=>"Errored"
    #       }, {
    #         "short"=>true,
    #         "title"=>"Server",
    #         "value"=>"portal-provisioning:app/worker.1"
    #       }],
    #       "mrkdwn_in"=>["text"],
    #       "text"=> [
    #         "*AgentProfileProvision::Base::ProvisionFailure* User does not exist",
    #         "```",
    #         "* app/jobs/agent_profile_provision/activate.rb        :   6 in perform",
    #         "* vendor/bundle/ruby/2.5.0/gems/activejob-5.2.0/lib/a :  39 in block in perform_now",
    #         "* vendor/bundle/ruby/2.5.0/gems/activesupport-5.2.0/l : 109 in block in run_callbacks",
    #         "* vendor/bundle/ruby/2.5.0/gems/i18n-1.0.1/lib/i18n.r : 284 in with_locale",
    #         "* vendor/bundle/ruby/2.5.0/gems/activejob-5.2.0/lib/a :   9 in block (2 levels) in <module:Translation>",
    #         "```"
    #       ].join("\n")
    #     }]
    #   end
    # end
    #
    # context 'heroku debug logs' do
    #   pending 'formats using the debug template' do
    #     log_lines = %{
    #       Nov 21 14:14:57 cohortflow app/heroku-postgres: source=DATABASE addon=postgresql-fluffy-94567 sample#current_transaction=7967483 sample#db_size=1543969304bytes sample#tables=162 sample#active-connections=13 sample#waiting-connections=0 sample#index-cache-hit-rate=0.99989 sample#table-cache-hit-rate=0.99931 sample#load-avg-1m=0.05 sample#load-avg-5m=0.045 sample#load-avg-15m=0.015 sample#read-iops=0.0064935 sample#write-iops=0.011769 sample#memory-total=4045048kB sample#memory-free=220156kB sample#memory-cached=2870104kB sample#memory-postgres=556444kB
    #       Nov 21 14:14:58 cohortflow heroku/web.4: source=web.4 dyno=heroku.27066801.10cb480b-5f85-48c8-a788-87002d69fdb4 sample#load_avg_1m=0.00 sample#load_avg_5m=0.00 sample#load_avg_15m=0.01
    #       Nov 21 14:14:58 cohortflow heroku/web.4: source=web.4 dyno=heroku.27066801.10cb480b-5f85-48c8-a788-87002d69fdb4 sample#memory_total=590.29MB sample#memory_rss=429.68MB sample#memory_cache=0.48MB sample#memory_swap=160.12MB sample#memory_pgpgin=156757pages sample#memory_pgpgout=97224pages sample#memory_quota=512.00MB
    #       Nov 21 14:14:58 cohortflow heroku/web.4: Process running mem=590M(115.2%)
    #       Nov 21 14:14:58 cohortflow heroku/web.4: Error R14 (Memory quota exceeded)
    #       Nov 21 14:15:00 cohortflow heroku/router: at=info method=GET path="/product_tours.json?scope=&page=1&order=&p=%2Fapps%2Fcohortpay%2Fagent_transactions%2FCPS00228656&d=cohortflow.com" host=cohortflow.com request_id=7c16e9fe-0a88-4946-962f-ca9708be4aeb fwd="139.194.38.153" dyno=web.4 connect=0ms service=17ms status=200 bytes=912 protocol=https
    #     }.split("\n").map(&:strip).reject(&:empty?)
    #
    #     allow(Papertrail).to receive(:log_lines_between).and_return(log_lines)
    #
    #     attachments = Slack.message({'text' => 'Error Code: 500 - 20181120150057'})
    #     expect(attachments).to eq []
    #   end
    # end
    #
    # context 'combination of log types' do
    #   let!(:log_lines) do
    #     File.readlines('./spec/fixtures/combination_1.txt')
    #   end
    #
    #   it 'things' do
    #     allow(Papertrail).to receive(:log_lines_between).and_return(log_lines)
    #
    #     attachments = Slack.message({'text' => 'Error Code: 500 - 20181120150057'})
    #     expect(attachments).to eq ([
    #       {
    #         'color' => 'danger',
    #         'fallback' => "[cohortflow] *RestClient::ServiceUnavailable* '503 Service Unavailable' (Request timeout)",
    #         'mrkdwn_in' => ['text'],
    #         'text' => [
    #           '`[GET]` /tags.json (203.206.244.8)',
    #           "[cohortflow] *RestClient::ServiceUnavailable* '503 Service Unavailable' (Request timeout)",
    #           '```',
    #           '* controllers/product_tours_controller.rb      :  94 in proxy_tour_request',
    #           '* controllers/product_tours_controller.rb      :  31 in public_index',
    #           '```'
    #         ].join("\n")
    #       },
    #       {
    #         'mrkdwn_in' => ['text'],
    #         'text' =>  [
    #           '`[GET]` /product_tours.json (54.91.44.133)',
    #           '`[GET]` /tags.json (203.206.244.8)',
    #           '`[POST]` /rules/simulate.json',
    #           '`[GET]` /product_tours.json',
    #           '`[GET]` /product_tours.json (54.226.168.76)',
    #           '`[GET]` /product_tours.json',
    #           '`[GET]` /product_tours.json (54.234.34.7)',
    #           '`[GET]` / *->* <https://cohortgo.com|_redirected_> (185.180.12.65)',
    #           '`[GET]` / *->* <https://cohortgo.com|_redirected_> (209.58.139.194)',
    #           '`[GET]` /es/policy_applications/new (66.249.75.89)',
    #           '`[GET]` /pt/quote *->* <https://oshcaustralia.com.au/pt/quote?adjusted=true&adults=1&children=0&finish=2017-02-01&start=2014-12-21|_redirected_> (144.76.7.79)'
    #         ].join("\n")
    #       },
    #       {
    #         'color' => 'danger',
    #         'fallback' => "[errbit-cohortsolutions] *Mongo::Error::OperationFailure* 'quota exceeded (12501)'",
    #         'mrkdwn_in' => ['text'],
    #         'text' => [
    #           "`[POST]` /api/v3/projects/true/notices (54.91.44.133)",
    #           "[errbit-cohortsolutions] *Mongo::Error::OperationFailure* 'quota exceeded (12501)'",
    #           "```",
    #           "* models/error_report.rb                              :  56 in generate_notice!",
    #           "```"
    #         ].join("\n")
    #       },
    #       {
    #         'mrkdwn_in' => ['text'],
    #         'text' => '`[GET]` / (209.58.139.194)'
    #       }
    #     ])
    #   end
    # end
  end

  # describe '#send_message' do
  #   it 'posts a report back to Slack' do
  #     stub_request(:post, "https://slack.com/api/chat.postMessage").
  #          with(
  #            body: "{\"channel\":null,\"thread_ts\":null,\"attachments\":[{\"mrkdwn_in\":[\"text\"],\"fields\":[{\"title\":\"Job\",\"value\":\"SyncService::PushJob\",\"short\":true},{\"title\":\"Job ID\",\"value\":\"f4f879d7\",\"short\":true},{\"title\":\"Status\",\"value\":\"Finished\",\"short\":true},{\"title\":\"Server\",\"value\":\"cohortflow:app/worker.1\",\"short\":true}]},{\"mrkdwn_in\":[\"text\"],\"fields\":[{\"title\":\"Job\",\"value\":\"SyncService::PushJob\",\"short\":true},{\"title\":\"Job ID\",\"value\":\"2db2210f\",\"short\":true},{\"title\":\"Status\",\"value\":\"Finished\",\"short\":true},{\"title\":\"Server\",\"value\":\"cohortflow:app/worker.1\",\"short\":true}]},{\"mrkdwn_in\":[\"text\"],\"fields\":[{\"title\":\"Job\",\"value\":\"IntercomCompanySyncJob\",\"short\":true},{\"title\":\"Job ID\",\"value\":\"4fb0a985\",\"short\":true},{\"title\":\"Status\",\"value\":\"Finished\",\"short\":true},{\"title\":\"Server\",\"value\":\"cohortflow:app/worker.1\",\"short\":true}]},{\"color\":\"danger\",\"fallback\":\"[portal-provisioning] *AgentProfileProvision::Activate* 'User does not exist'.\",\"mrkdwn_in\":[\"text\"],\"text\":\"*AgentProfileProvision::Base::ProvisionFailure* User does not exist\\n```\\n/app/app/jobs/agent_profile_provision/activate.rb   :   6 in perform\\n/app/vendor/bundle/ruby/2.5.0/gems/activejob-5.2.0/ :  39 in block in perform_now\\n/app/vendor/bundle/ruby/2.5.0/gems/activesupport-5. : 109 in block in run_callbacks\\n/app/vendor/bundle/ruby/2.5.0/gems/i18n-1.0.1/lib/i : 284 in with_locale\\n/app/vendor/bundle/ruby/2.5.0/gems/activejob-5.2.0/ :   9 in block (2 levels) in <module:Translation>\\n```\",\"fields\":[{\"title\":\"Job\",\"value\":\"AgentProfileProvision::Activate\",\"short\":true},{\"title\":\"Job ID\",\"value\":\"ecbf936b\",\"short\":true},{\"title\":\"Status\",\"value\":\"Errored\",\"short\":true},{\"title\":\"Server\",\"value\":\"portal-provisioning:app/worker.1\",\"short\":true}]}],\"as_user\":false}",
  #            headers: {
  #        	  'Authorization'=>'Bearer',
  #        	  'Content-Type'=>'application/json'
  #            }).
  #          to_return(status: 200, body: "", headers: {})
  #   end
  # end
end
