require './slack'

RSpec.describe Slack do
  describe '#message' do
    before do
      expect(SlackService).to receive(:post_reply)
    end

    context 'exception logs' do
      it 'formats using the exception template' do
        log_lines = %{
          Nov 21 06:07:42 cohortpay-demo app/web.1: Started POST "/admin/users/identity_push.json" for 54.205.86.120 at 2018-11-20 20:07:41 +0000
          Nov 21 06:07:42 cohortpay-demo app/web.1: Processing by Admin::UsersController#identity_push as JSON
          Nov 21 06:07:42 cohortpay-demo app/web.1:   Parameters: {"content"=>{"id"=>1444, "watchlist_state"=>"unchecked", "passport_state"=>"unverified", "update_sequence"=>2873, "state"=>"unchecked"}, "user"=>{}}
          Nov 21 06:07:42 cohortpay-demo app/web.1: Can't verify CSRF token authenticity
          Nov 21 06:07:42 cohortpay-demo app/web.1: Completed 422 Unprocessable Entity in 34ms (ActiveRecord: 13.5ms)
          Nov 21 06:07:42 cohortpay-demo app/web.1: ActiveRecord::RecordInvalid (Validation failed: Dob must be at least four years old):
          Nov 21 06:07:42 cohortpay-demo app/web.1:   app/admin/system/users.rb:258:in `block (3 levels) in <top (required)>'
          Nov 21 06:07:42 cohortpay-demo app/web.1:   app/admin/system/users.rb:256:in `block (2 levels) in <top (required)>'
          Nov 21 06:07:42 cohortpay-demo app/web.1:   lib/rack_headers.rb:72:in `_call'
          Nov 21 06:07:42 cohortpay-demo app/web.1:   lib/rack_headers.rb:68:in `call'
        }.split("\n").map(&:strip).reject(&:empty?)

        allow(Papertrail).to receive(:log_lines_between).and_return(log_lines)

        attachments = Slack.message({'text' => 'Error Code: 500 - 20181120150057'})
        expect(attachments).to eq [{
          "color"=>"danger",
          "fallback"=>"[cohortpay-demo] *Validation failed* 'Dob must be at least four years old'.",
          "mrkdwn_in"=>["text"],
          "text"=>[
            "`[POST]` /admin/users/identity_push.json (54.205.86.120)",
            "[cohortpay-demo] *Validation failed* 'Dob must be at least four years old'.",
            "```",
            "* admin/system/users.rb      : 258 in block (3 levels) in <top (required)>",
            "* admin/system/users.rb      : 256 in block (2 levels) in <top (required)>",
            "```"
          ].join("\n")
        }]
      end

      it 'reports on database errors' do
        log_lines = %{
          Nov 21 15:10:22 cohortflow app/web.1:  Started PUT "/admin/organisations/ap:11122/products.json" for 54.167.139.215 at 2018-11-21 05:10:22 +0000
          Nov 21 15:10:22 cohortflow app/web.1:  Processing by Admin::Organisations::ProductsController#update as JSON
          Nov 21 15:10:22 cohortflow app/web.1:    Parameters: {"app_configs"=>{}, "enabled_apps"=>["cohortarrivals"], "app_features"=>nil, "organisation_contract_map"=>{"cohortarrivals"=>1}, "organisation_id"=>"ap:11122", "product"=>{}}
          Nov 21 15:10:23 cohortflow app/postgres.12086:  [DATABASE] [18-1]  sql_error_code = 23502 ERROR:  null value in column "app_features" violates not-null constraint
          Nov 21 15:10:23 cohortflow app/postgres.12086:  [DATABASE] [18-2]  sql_error_code = 23502 DETAIL:  Failing row contains (375643, Ahead Edu Vivian, UTC, null, null, null, 435342, 2018-11-21 05:10:22.195009, 2018-11-21 05:10:22.95809, null, null, null, null, null, {}, {}, f, {}, null, en, null, agent, null, null, null, null, unknown, null, f, {cohortarrivals}, null, null, null, null, null, null, null, new, {}, 1, null, basic, null, null, null, null, null, f, null, null, null, null, null, null, f, null, default, 11122, fw-p5xgatj98d, pending, null, null, null, null, null, null, {}).
          Nov 21 15:10:23 cohortflow app/postgres.12086:  [DATABASE] [18-3]  sql_error_code = 23502 STATEMENT:  UPDATE "organisations" SET "app_features" = $1, "enabled_apps" = $2, "updated_at" = $3 WHERE "organisations"."id" = $4
          Nov 21 15:10:23 cohortflow app/web.1:  Completed 500 Internal Server Error in 244ms (ActiveRecord: 101.1ms)
          Nov 21 15:10:23 cohortflow app/web.1:  ActiveRecord::StatementInvalid (PG::NotNullViolation: ERROR:  null value in column "app_features" violates not-null constraint
          Nov 21 15:10:23 cohortflow app/web.1:  DETAIL:  Failing row contains (375643, Ahead Edu Vivian, UTC, null, null, null, 435342, 2018-11-21 05:10:22.195009, 2018-11-21 05:10:22.95809, null, null, null, null, null, {}, {}, f, {}, null, en, null, agent, null, null, null, null, unknown, null, f, {cohortarrivals}, null, null, null, null, null, null, null, new, {}, 1, null, basic, null, null, null, null, null, f, null, null, null, null, null, null, f, null, default, 11122, fw-p5xgatj98d, pending, null, null, null, null, null, null, {}).
          Nov 21 15:10:23 cohortflow app/web.1:  : UPDATE "organisations" SET "app_features" = $1, "enabled_apps" = $2, "updated_at" = $3 WHERE "organisations"."id" = $4):
          Nov 21 15:10:23 cohortflow app/web.1:    app/controllers/admin/organisations/products_controller.rb:10:in `update'
          Nov 21 15:10:23 cohortflow app/web.1:    lib/rack_headers.rb:71:in `_call'
          Nov 21 15:10:23 cohortflow app/web.1:    lib/rack_headers.rb:67:in `call'
        }.split("\n").map(&:strip).reject(&:empty?)

        allow(Papertrail).to receive(:log_lines_between).and_return(log_lines)

        attachments = Slack.message({'text' => 'Error Code: 500 - 20181120150057'})
        expect(attachments).to eq [{
          'color' => 'danger',
          'fallback' => "[cohortflow] *PG::NotNullViolation: ERROR* 'null value in column \"app_features\" violates not-null constraint'.",
          'mrkdwn_in' => ['text'],
          'text' => [
            "`[PUT]` /admin/organisations/ap:11122/products.json (54.167.139.215)",
            "[cohortflow] *PG::NotNullViolation: ERROR* 'null value in column \"app_features\" violates not-null constraint'.",
            "```",
            "* controllers/admin/organisations/products_controller :  10 in update",
            "```"
          ].join("\n")
        }]
      end
    end

    context 'active job logs' do
      it 'formats using the job template' do
        log_lines = %{
          Nov 21 15:10:23 cohortflow app/worker.1:  [ActiveJob] [SyncService::PushJob] [f4f879d7-5f96-43b0-919e-d765bf3d1cd5] Failed to sync object: '{"status":500,"error":"Internal Server Error"}'
          Nov 21 15:10:23 cohortflow app/worker.1:  [ActiveJob] [SyncService::PushJob] [f4f879d7-5f96-43b0-919e-d765bf3d1cd5] Performed SyncService::PushJob from QueueClassic(default) in 1991.14ms
          Nov 21 15:10:23 cohortflow app/worker.1:  [ActiveJob] [SyncService::PushJob] [2db2210f-7eac-4929-8bad-02724e206e61] Performing SyncService::PushJob from QueueClassic(default) with arguments: gid://cohortflow/ContactProduct/12832, "knox+https://cohort-knowledge-graph.herokuapp.com/listeners/contact_products/push.json", gid://cohortflow/ObjectSyncStatus/40219
          Nov 21 15:10:23 cohortflow app/worker.1:  [ActiveJob] [SyncService::PushJob] [2db2210f-7eac-4929-8bad-02724e206e61] Performed SyncService::PushJob from QueueClassic(default) in 145.35ms
          Nov 21 15:10:23 cohortflow app/worker.1:  [ActiveJob] [IntercomCompanySyncJob] [4fb0a985-d8dc-4ef5-ba74-ffdf315fecff] Performing IntercomCompanySyncJob from QueueClassic(default) with arguments: gid://cohortflow/Organisation/375643
          Nov 21 15:10:23 cohortflow app/worker.1:  [ActiveJob] [IntercomCompanySyncJob] [4fb0a985-d8dc-4ef5-ba74-ffdf315fecff] Performed IntercomCompanySyncJob from QueueClassic(default) in 0.11ms
          Nov 20 20:23:54 portal-provisioning app/worker.1:  I, [2018-11-20T10:23:53.874194 #4]  INFO -- : [ActiveJob] [AgentProfileProvision::Activate] [ecbf936b-c888-4cff-ab6a-8e3989575360] Performing AgentProfileProvision::Activate (Job ID: ecbf936b-c888-4cff-ab6a-8e3989575360) from QueueClassic(default) with arguments: #<GlobalID:0x00000000071b4e58 @uri=#<URI::GID gid://cohortgo-portal-provisioning/PartnerApp/1>>, #<GlobalID:0x00000000071b4638 @uri=#<URI::GID gid://cohortgo-portal-provisioning/Activation/22>>
          Nov 20 20:23:54 portal-provisioning app/worker.1:  D, [2018-11-20T10:23:53.876394 #4] DEBUG -- : [ActiveJob] [AgentProfileProvision::Activate] [ecbf936b-c888-4cff-ab6a-8e3989575360]   AgentProfile Load (1.3ms)  SELECT  "agent_profiles".* FROM "agent_profiles" WHERE "agent_profiles"."id" = $1 LIMIT $2  [["id", 11113], ["LIMIT", 1]]
          Nov 20 20:23:54 portal-provisioning app/worker.1:  E, [2018-11-20T10:23:54.147463 #4] ERROR -- : [ActiveJob] [AgentProfileProvision::Activate] [ecbf936b-c888-4cff-ab6a-8e3989575360] Error performing AgentProfileProvision::Activate (Job ID: ecbf936b-c888-4cff-ab6a-8e3989575360) from QueueClassic(default) in 272.99ms: AgentProfileProvision::Base::ProvisionFailure (User does not exist):
          Nov 20 20:23:54 portal-provisioning app/worker.1:  /app/app/jobs/agent_profile_provision/activate.rb:6:in `perform'
          Nov 20 20:23:54 portal-provisioning app/worker.1:  /app/vendor/bundle/ruby/2.5.0/gems/activejob-5.2.0/lib/active_job/execution.rb:39:in `block in perform_now'
          Nov 20 20:23:54 portal-provisioning app/worker.1:  /app/vendor/bundle/ruby/2.5.0/gems/activesupport-5.2.0/lib/active_support/callbacks.rb:109:in `block in run_callbacks'
          Nov 20 20:23:54 portal-provisioning app/worker.1:  /app/vendor/bundle/ruby/2.5.0/gems/i18n-1.0.1/lib/i18n.rb:284:in `with_locale'
          Nov 20 20:23:54 portal-provisioning app/worker.1:  /app/vendor/bundle/ruby/2.5.0/gems/activejob-5.2.0/lib/active_job/translation.rb:9:in `block (2 levels) in <module:Translation>'
        }.split("\n").map(&:strip).reject(&:empty?)

        allow(Papertrail).to receive(:log_lines_between).and_return(log_lines)

        attachments = Slack.message({'text' => 'Error Code: 500 - 20181120150057'})
        expect(attachments).to eq [{
          "fields" => [{
            "short"=>true,
            "title"=>"Job",
            "value"=>"SyncService::PushJob"
          }, {
            "short"=>true,
            "title"=>"Job ID",
            "value"=>"f4f879d7"
          }, {
            "short"=>true,
            "title"=>"Status",
            "value"=>"Finished"
          }, {
            "short"=>true,
            "title"=>"Server",
            "value"=>"cohortflow:app/worker.1"
          }],
          "mrkdwn_in"=>["text"]
        }, {
          "fields" => [{
            "short"=>true,
            "title"=>"Job",
            "value"=>"SyncService::PushJob"
          }, {
            "short"=>true,
            "title"=>"Job ID",
            "value"=>"2db2210f"
          }, {
            "short"=>true,
            "title"=>"Status",
            "value"=>"Finished"
          }, {
            "short"=>true,
            "title"=>"Server",
            "value"=>"cohortflow:app/worker.1"
          }],
          "mrkdwn_in"=>["text"]
        }, {
          "fields"=> [{
            "short"=>true,
            "title"=>"Job",
            "value"=>"IntercomCompanySyncJob"
          }, {
            "short"=>true,
            "title"=>"Job ID",
            "value"=>"4fb0a985"
          }, {
            "short"=>true,
            "title"=>"Status",
            "value"=>"Finished"
          }, {
            "short"=>true,
            "title"=>"Server",
            "value"=>"cohortflow:app/worker.1"
          }],
          "mrkdwn_in"=>["text"]
        }, {
          "color"=>"danger",
          "fallback"=> "[portal-provisioning] *AgentProfileProvision::Activate* 'User does not exist'.",
          "fields"=> [{
            "short"=>true,
            "title"=>"Job",
            "value"=>"AgentProfileProvision::Activate"
          }, {
            "short"=>true,
            "title"=>"Job ID",
            "value"=>"ecbf936b"
          }, {
            "short"=>true,
            "title"=>"Status",
            "value"=>"Errored"
          }, {
            "short"=>true,
            "title"=>"Server",
            "value"=>"portal-provisioning:app/worker.1"
          }],
          "mrkdwn_in"=>["text"],
          "text"=> [
            "*AgentProfileProvision::Base::ProvisionFailure* User does not exist",
            "```",
            "* app/jobs/agent_profile_provision/activate.rb        :   6 in perform",
            "* vendor/bundle/ruby/2.5.0/gems/activejob-5.2.0/lib/a :  39 in block in perform_now",
            "* vendor/bundle/ruby/2.5.0/gems/activesupport-5.2.0/l : 109 in block in run_callbacks",
            "* vendor/bundle/ruby/2.5.0/gems/i18n-1.0.1/lib/i18n.r : 284 in with_locale",
            "* vendor/bundle/ruby/2.5.0/gems/activejob-5.2.0/lib/a :   9 in block (2 levels) in <module:Translation>",
            "```"
          ].join("\n")
        }]
      end
    end

    context 'heroku debug logs' do
      pending 'formats using the debug template' do
        log_lines = %{
          Nov 21 14:14:57 cohortflow app/heroku-postgres: source=DATABASE addon=postgresql-fluffy-94567 sample#current_transaction=7967483 sample#db_size=1543969304bytes sample#tables=162 sample#active-connections=13 sample#waiting-connections=0 sample#index-cache-hit-rate=0.99989 sample#table-cache-hit-rate=0.99931 sample#load-avg-1m=0.05 sample#load-avg-5m=0.045 sample#load-avg-15m=0.015 sample#read-iops=0.0064935 sample#write-iops=0.011769 sample#memory-total=4045048kB sample#memory-free=220156kB sample#memory-cached=2870104kB sample#memory-postgres=556444kB
          Nov 21 14:14:58 cohortflow heroku/web.4: source=web.4 dyno=heroku.27066801.10cb480b-5f85-48c8-a788-87002d69fdb4 sample#load_avg_1m=0.00 sample#load_avg_5m=0.00 sample#load_avg_15m=0.01
          Nov 21 14:14:58 cohortflow heroku/web.4: source=web.4 dyno=heroku.27066801.10cb480b-5f85-48c8-a788-87002d69fdb4 sample#memory_total=590.29MB sample#memory_rss=429.68MB sample#memory_cache=0.48MB sample#memory_swap=160.12MB sample#memory_pgpgin=156757pages sample#memory_pgpgout=97224pages sample#memory_quota=512.00MB
          Nov 21 14:14:58 cohortflow heroku/web.4: Process running mem=590M(115.2%)
          Nov 21 14:14:58 cohortflow heroku/web.4: Error R14 (Memory quota exceeded)
          Nov 21 14:15:00 cohortflow heroku/router: at=info method=GET path="/product_tours.json?scope=&page=1&order=&p=%2Fapps%2Fcohortpay%2Fagent_transactions%2FCPS00228656&d=cohortflow.com" host=cohortflow.com request_id=7c16e9fe-0a88-4946-962f-ca9708be4aeb fwd="139.194.38.153" dyno=web.4 connect=0ms service=17ms status=200 bytes=912 protocol=https
        }.split("\n").map(&:strip).reject(&:empty?)

        allow(Papertrail).to receive(:log_lines_between).and_return(log_lines)

        attachments = Slack.message({'text' => 'Error Code: 500 - 20181120150057'})
        expect(attachments).to eq []
      end
    end

    context 'combination of log types' do
      let!(:log_lines) do
        File.readlines('./spec/fixtures/combination_1.txt')
      end

      it 'things' do
        allow(Papertrail).to receive(:log_lines_between).and_return(log_lines)

        attachments = Slack.message({'text' => 'Error Code: 500 - 20181120150057'})
        expect(attachments).to eq ([
          {
            'color' => 'danger',
            'fallback' => "[cohortflow] *RestClient::ServiceUnavailable* '503 Service Unavailable' (Request timeout)",
            'mrkdwn_in' => ['text'],
            'text' => [
              '`[GET]` /tags.json (203.206.244.8)',
              "[cohortflow] *RestClient::ServiceUnavailable* '503 Service Unavailable' (Request timeout)",
              '```',
              '* controllers/product_tours_controller.rb      :  94 in proxy_tour_request',
              '* controllers/product_tours_controller.rb      :  31 in public_index',
              '```'
            ].join("\n")
          },
          {
            'mrkdwn_in' => ['text'],
            'text' =>  [
              '`[GET]` /product_tours.json (54.91.44.133)',
              '`[GET]` /tags.json (203.206.244.8)',
              '`[POST]` /rules/simulate.json',
              '`[GET]` /product_tours.json',
              '`[GET]` /product_tours.json (54.226.168.76)',
              '`[GET]` /product_tours.json',
              '`[GET]` /product_tours.json (54.234.34.7)',
              '`[GET]` / *->* <https://cohortgo.com|_redirected_> (185.180.12.65)',
              '`[GET]` / *->* <https://cohortgo.com|_redirected_> (209.58.139.194)',
              '`[GET]` /es/policy_applications/new (66.249.75.89)',
              '`[GET]` /pt/quote *->* <https://oshcaustralia.com.au/pt/quote?adjusted=true&adults=1&children=0&finish=2017-02-01&start=2014-12-21|_redirected_> (144.76.7.79)'
            ].join("\n")
          },
          {
            'color' => 'danger',
            'fallback' => "[errbit-cohortsolutions] *Mongo::Error::OperationFailure* 'quota exceeded (12501)'",
            'mrkdwn_in' => ['text'],
            'text' => [
              "`[POST]` /api/v3/projects/true/notices (54.91.44.133)",
              "[errbit-cohortsolutions] *Mongo::Error::OperationFailure* 'quota exceeded (12501)'",
              "```",
              "* models/error_report.rb                              :  56 in generate_notice!",
              "```"
            ].join("\n")
          },
          {
            'mrkdwn_in' => ['text'],
            'text' => '`[GET]` / (209.58.139.194)'
          }
        ])
      end
    end
  end

  describe '#send_message' do
    it 'posts a report back to Slack' do
      stub_request(:post, "https://slack.com/api/chat.postMessage").
           with(
             body: "{\"channel\":null,\"thread_ts\":null,\"attachments\":[{\"mrkdwn_in\":[\"text\"],\"fields\":[{\"title\":\"Job\",\"value\":\"SyncService::PushJob\",\"short\":true},{\"title\":\"Job ID\",\"value\":\"f4f879d7\",\"short\":true},{\"title\":\"Status\",\"value\":\"Finished\",\"short\":true},{\"title\":\"Server\",\"value\":\"cohortflow:app/worker.1\",\"short\":true}]},{\"mrkdwn_in\":[\"text\"],\"fields\":[{\"title\":\"Job\",\"value\":\"SyncService::PushJob\",\"short\":true},{\"title\":\"Job ID\",\"value\":\"2db2210f\",\"short\":true},{\"title\":\"Status\",\"value\":\"Finished\",\"short\":true},{\"title\":\"Server\",\"value\":\"cohortflow:app/worker.1\",\"short\":true}]},{\"mrkdwn_in\":[\"text\"],\"fields\":[{\"title\":\"Job\",\"value\":\"IntercomCompanySyncJob\",\"short\":true},{\"title\":\"Job ID\",\"value\":\"4fb0a985\",\"short\":true},{\"title\":\"Status\",\"value\":\"Finished\",\"short\":true},{\"title\":\"Server\",\"value\":\"cohortflow:app/worker.1\",\"short\":true}]},{\"color\":\"danger\",\"fallback\":\"[portal-provisioning] *AgentProfileProvision::Activate* 'User does not exist'.\",\"mrkdwn_in\":[\"text\"],\"text\":\"*AgentProfileProvision::Base::ProvisionFailure* User does not exist\\n```\\n/app/app/jobs/agent_profile_provision/activate.rb   :   6 in perform\\n/app/vendor/bundle/ruby/2.5.0/gems/activejob-5.2.0/ :  39 in block in perform_now\\n/app/vendor/bundle/ruby/2.5.0/gems/activesupport-5. : 109 in block in run_callbacks\\n/app/vendor/bundle/ruby/2.5.0/gems/i18n-1.0.1/lib/i : 284 in with_locale\\n/app/vendor/bundle/ruby/2.5.0/gems/activejob-5.2.0/ :   9 in block (2 levels) in <module:Translation>\\n```\",\"fields\":[{\"title\":\"Job\",\"value\":\"AgentProfileProvision::Activate\",\"short\":true},{\"title\":\"Job ID\",\"value\":\"ecbf936b\",\"short\":true},{\"title\":\"Status\",\"value\":\"Errored\",\"short\":true},{\"title\":\"Server\",\"value\":\"portal-provisioning:app/worker.1\",\"short\":true}]}],\"as_user\":false}",
             headers: {
         	  'Authorization'=>'Bearer',
         	  'Content-Type'=>'application/json'
             }).
           to_return(status: 200, body: "", headers: {})
    end
  end
end
