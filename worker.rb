require './services/queue_service'
require './workers/send_slack_messages_for_timecode_job'

while true
  QueueService.run_next!
  sleep 1
end
