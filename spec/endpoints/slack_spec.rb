require './slack'

RSpec.describe Slack do
  describe '#message' do
    context 'exception logs' do
      it 'queues a message to be processed' do
        expect(SendSlackMessagesForTimecodeJob).to receive(:perform_later).with('500', '20181120150057', {})

        Slack.process_incoming_payload({
          'type' => 'event_callback',
          'event' => {
            'type' => 'message',
            'text' => 'Error Code: 500 - 20181120150057'
          }
        })
      end
    end
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
