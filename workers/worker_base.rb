require './services/queue_service'

class WorkerBase
  def self.perform_later(*args)
    QueueService::Job.queue_with(self, args)
  end

  def self.perform_now(*args)
    new.perform(*args)
  end
end
