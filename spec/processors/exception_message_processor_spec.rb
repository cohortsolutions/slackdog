require './processors/exception_message_processor'

RSpec.describe ExceptionMessageProcessor do
  describe '#process' do
    let(:context) { %w(line_1 line_2 line_3 line_4 line_5).freeze }
    context 'undefined method for NilClass' do
      let(:exception_message) do
        {
          'message' => "undefined method `foo' for nil:NilClass /path/to/file:123:in `some_method'"
        }
      end

      it 'can handle multiple possibles' do
        line_in_error = 'result = "#{self.foo} - #{obj.bar} - #{self.meta.foo}"'

        expect(GithubService).to receive(:get_line).
          with('some_app', '/path/to/file', 123).
          and_return({focus: line_in_error, context: context})

        result = ExceptionMessageProcessor.process('some_app', exception_message)
        expect(result[:context]).to eq context
        expect(result[:message]).to eq 'Either `self`, or `meta` is null'
      end

      it 'can handle a single possible' do
        line_in_error = 'result = "#{obj.bar} - #{self.meta.foo}"'

        expect(GithubService).to receive(:get_line).
          with('some_app', '/path/to/file', 123).
          and_return({focus: line_in_error, context: context})

        result = ExceptionMessageProcessor.process('some_app', exception_message)
        expect(result[:context]).to eq context
        expect(result[:message]).to eq '`meta` is null'
      end

      context 'with backtrace' do
        let(:exception_message) do
          {
            'message' => "undefined method `foo' for nil:NilClass",
            'backtrace' => [{'file' => '/path/to/file.rb', 'line' => 123, 'method' => "`some_method'", 'internal' => true}]
          }
        end

        it 'can handle multiple possibles' do
          line_in_error = 'result = "#{self.foo} - #{obj.bar} - #{self.meta.foo}"'

          expect(GithubService).to receive(:get_line).
            with('some_app', '/path/to/file.rb', 123).
            and_return({focus: line_in_error, context: context})

          result = ExceptionMessageProcessor.process('some_app', exception_message)
          expect(result[:context]).to eq context
          expect(result[:message]).to eq 'Either `self`, or `meta` is null'
        end

        it 'can handle a single possible' do
          line_in_error = 'result = "#{obj.bar} - #{self.meta.foo}"'

          expect(GithubService).to receive(:get_line).
            with('some_app', '/path/to/file.rb', 123).
            and_return({focus: line_in_error, context: context})

          result = ExceptionMessageProcessor.process('some_app', exception_message)
          expect(result[:context]).to eq context
          expect(result[:message]).to eq '`meta` is null'
        end
      end
    end
  end
end
