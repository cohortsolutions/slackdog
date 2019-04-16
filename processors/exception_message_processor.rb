require './services/github_service'

class ExceptionMessageProcessor
  class << self
    def process(app, exception)
      exception_message = exception['message']
      backtrace = exception['backtrace']

      patterns.each do |config|
        match = exception_message.match(config[:matches])
        next unless match

        response = {}
        captures = match.named_captures
        file, line = captures['file'], captures['line'].to_i

        unless file
          errored_line = backtrace[0]
          if errored_line['internal']
            file = errored_line['file']
            line = errored_line['line'].to_i
          end
        end

        if file && line > 0 && result = GithubService.get_line(app, file, line)
          response[:context] = result[:context]
          captures['exceptionLine'] = result[:focus]
        end

        response[:message] = config[:message].call(captures)
        return response if response[:message]
      end

      nil
    end

    private

    def patterns
      @patterns ||= [
        {
          matches: /undefined method `(?<missingMethod>[^\']+)' for nil:NilClass(\z| (?<file>[^:]+):(?<line>\d+):in )/,

          message: lambda do |captures|
            line = captures['exceptionLine']
            return unless line

            expression = Regexp.new("([\\$@\\w]+)\\.#{captures['missingMethod']}")
            result = line.scan(expression).flatten.map { |r| "`#{r}`" }

            if result.size > 1
              "Either #{result.join(', or ')} is null"
            elsif result.size == 1
              "#{result.first} is null"
            end
          end
        },
        {
          matches: /undefined method `(?<missingMethod>[^\']+)' for (?<methodSource>[^\s]+)(\z| (?<file>[^:]+):(?<line>\d+):in )/,
          message: ->(captures) { "Tried calling `#{captures['missingMethod']}` on `#{captures['methodSource']}`" }
        },
        {
          matches: /null value in column \"(?<field>.*)\" violates not-null constraint/,
          message: ->(captures) { "`#{captures['field']}` must have a value (database constraint)" }
        }
      ].freeze
    end
  end
end
