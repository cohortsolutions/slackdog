require 'sinatra'
require './slack'

post '/slack/event' do
  data = JSON.parse(request.body.read)
  Slack.process_incoming_payload(data)
end
