require 'redis'
require 'json'
require 'securerandom'

Dir['./workers/*_job.rb'].each { |f| require f }

class QueueService
  class Job
    def self.queue_with(klass, args)
      new('args' => args, 'class_name' => klass.name).tap do |job|
        job.queue!
      end
    end

    FIELDS = %w(args class_name fail_reason run_count).freeze

    FIELDS.each do |field|
      attr_reader field.to_sym
    end

    def initialize(raw)
      @raw = raw

      FIELDS.each do |f|
        instance_variable_set("@#{f}", @raw[f])
      end
    end

    def to_attrs
      FIELDS.each_with_object({}) { |f, obj| obj[f] = send(f) }
    end

    def to_json
      to_attrs.to_json
    end

    def queue!
      QueueService.queue(to_json)
    end

    def failed_with(message)
      @run_count ||= 0
      @run_count += 1

      @fail_reason = message
    end

    def process!
      time = Time.now
      run_id = SecureRandom.uuid
      puts "[Performing] [#{run_id}] #{to_attrs}"

      begin
        klass = Object.const_get(class_name)
        puts 'got klass'
        klass && klass.perform_now(*args)
        puts 'possibly performed'
        puts "[Performed] [#{run_id}] -> #{Time.now - time} seconds"

        return true
      rescue => e
        puts 'failed :('
        message = e.message
        puts "[Failed] [#{run_id}] #{message}"
        puts e.backtrace.join("\n")

        failed_with(message)
        return false
      end

      puts 'at end'
    end
  end

  class << self
    def queue(json)
      push(json)
    end

    def run_next!
      json = pop
      return false unless json

      job = Job.new(JSON.parse(json))
      result = job.process!
      push(json, queue: 'failed') unless result

      result
    end

    private

    def pop
      redis_client.lpop('queue')
    end

    def push(json, queue: nil)
      redis_client.lpush(queue || 'queue', json)
    end

    def redis_client
      @redis_client ||= Redis.new
    end
  end
end
