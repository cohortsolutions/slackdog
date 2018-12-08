require './processors/exception_message_processor'

RSpec.describe ExceptionMessageProcessor do
  describe '#possible_message_for' do
    context 'undefined method for NilClass' do
      let(:exception_message) do
        "undefined method `foo' for nil:NilClass /path/to/file:123:in `some_method'"
      end

      it 'can handle multiple possibles' do
        line_in_error = 'result = "#{self.foo} - #{obj.bar} - #{self.meta.foo}"'

        expect(GithubService).to receive(:get_line).
          with('some_app', '/path/to/file', 123).
          and_return({focus: line_in_error})

        result = ExceptionMessageProcessor.possible_message_for('some_app', exception_message)
        expect(result[:message]).to eq 'Either `self`, or `meta` is null'
      end

      it 'can handle a single possible' do
        line_in_error = 'result = "#{obj.bar} - #{self.meta.foo}"'

        expect(GithubService).to receive(:get_line).
          with('some_app', '/path/to/file', 123).
          and_return({focus: line_in_error})

        result = ExceptionMessageProcessor.possible_message_for('some_app', exception_message)
        expect(result[:message]).to eq '`meta` is null'
      end
    end
  end
end
