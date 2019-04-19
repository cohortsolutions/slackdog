raise 'SLACK_TOKEN not set' if ENV['SLACK_TOKEN'].nil?
raise 'SLACK_OAUTH not set' if ENV['SLACK_OAUTH'].nil?
raise 'GITHUB_TOKEN not set' if ENV['GITHUB_TOKEN'].nil?
raise 'PAPERTRAIL_API_TOKEN not set' if ENV['PAPERTRAIL_API_TOKEN'].nil?

require 'sinatra'
require './slack'

post '/slack/event' do
  data = JSON.parse(request.body.read)
  Slack.process_incoming_payload(data)
end
