raise 'SLACK_TOKEN not set' if ENV['SLACK_TOKEN'].nil?
raise 'SLACK_OAUTH not set' if ENV['SLACK_OAUTH'].nil?
raise 'GITHUB_TOKEN not set' if ENV['GITHUB_TOKEN'].nil?

require 'pry'
require 'sinatra'
require './slack'

post '/slack/event' do
  data = JSON.parse(request.body.read)
  Slack.process_incoming_payload(data)
end
