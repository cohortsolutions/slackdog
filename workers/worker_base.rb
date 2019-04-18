require './services/queue_service'

class WorkerBase
  def self.perform_later(*args)
    QueueService::Job.queue_with(self, args)
  end

  def self.perform_now(*args)
    puts 'in perform_now'
    new.perform(*args)
    puts 'after perform_now'
  end
end
