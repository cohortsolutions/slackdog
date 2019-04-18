require 'httparty'

class SlackService
  include HTTParty
  base_uri 'https://slack.com'

  def self.post_reply(channel, reply_to, attachments)
    puts 'attempting to send reply to slack'
    options = {
      body: {
        'channel' => channel,
        'thread_ts' => reply_to,
        'attachments' => attachments,
        'as_user' => false
      }.to_json,
      headers: {
        'Authorization' => "Bearer #{ENV['SLACK_OAUTH']}",
        'Content-Type' => 'application/json'
      }
    }

    post('/api/chat.postMessage', options)
  end
end
