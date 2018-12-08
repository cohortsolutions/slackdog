require './papertrail'
require './formatters/exception_attachment_formatter'

RSpec.describe ExceptionAttachmentFormatter do
  describe '#to_payload' do
    let(:event) do
      events = Papertrail.compile_from(log_lines)
      raise 'too many events' if events.size > 1
      raise 'not enough events :(' if events.size == 0

      events.first
    end

    context 'undefined method for NilClass' do
      let(:log_lines) do
        File.readlines('./spec/fixtures/errors/undefined_method_nilclass.txt')
      end

      it 'will parse the exception message as expected' do
        line_in_error = 'result = "#{self.foo} - #{obj.bar} - #{self.meta.foo}"'
        context = %(def some_method
  # some comment within the method
  #{line_in_error}
  do_something_with(result)
end)

        expect(GithubService).to receive(:get_line).
          with('some_app', 'app/controllers/concerns/transaction_payment_methods.rb', 58).
          and_return({focus: line_in_error, context: context})

        formatter = ExceptionAttachmentFormatter.new(event)
        expect(formatter.to_payload).to eq({
          'color' => 'danger',
          'fallback' => "[some_app] *NoMethodError* 'undefined method `foo' for nil:NilClass'",
          'mrkdwn_in' => ['pretext', 'text'],
          'pretext' => [
            'Either `self`, or `meta` is null',
            '```',
            'def some_method',
            '  # some comment within the method',
            '  result = "#{self.foo} - #{obj.bar} - #{self.meta.foo}"',
            '  do_something_with(result)',
            'end',
            '```',
          ].join("\n"),
          'text' => [
            "[some_app] *NoMethodError* 'undefined method `foo' for nil:NilClass'",
            '```',
            '* controllers/concerns/transaction_payment_methods.rb :  58 in agent_payment_request',
            '* controllers/concerns/transaction_payment_methods.rb :  81 in maybe_use_payment_request_partner',
            '```',
            '`[GET]` /zh-CN/identity (49.81.94.45)'
          ].join("\n")
        })
      end
    end

    context 'Not-null constraint violation errors' do
      let(:log_lines) do
        File.readlines('./spec/fixtures/errors/notnull_constraint_violation.txt')
      end

      it 'will parse the exception message as expected' do
        line_in_error = 'result = "#{self.foo} - #{obj.bar} - #{self.meta.foo}"'
        context = %[    contract_maps = params.fetch('organisation_contract_map', organisation.organisation_contract_map)

    organisation.update_attributes!(
      app_configs: app_configs,
      app_features: app_features,]

        expect(GithubService).to receive(:get_line).
          with('some_app', 'app/controllers/admin/organisations/products_controller.rb', 10).
          and_return({focus: line_in_error, context: context})

        formatter = ExceptionAttachmentFormatter.new(event)
        expect(formatter.to_payload).to eq({
          'color' => 'danger',
          'fallback' => "[some_app] *PG::NotNullViolation: ERROR* 'null value in column \"app_features\" violates not-null constraint'.",
          'mrkdwn_in' => ['pretext', 'text'],
          'pretext' => [
            '`app_features` must have a value (database constraint)',
            '```',
            "    contract_maps = params.fetch('organisation_contract_map', organisation.organisation_contract_map)",
            "",
            "    organisation.update_attributes!(",
            "      app_configs: app_configs,",
            "      app_features: app_features,",
            '```',
          ].join("\n"),
          'text' => [
            "[some_app] *PG::NotNullViolation: ERROR* 'null value in column \"app_features\" violates not-null constraint'.",
            '```',
            '* controllers/admin/organisations/products_controller :  10 in update',
            '```',
            '`[PUT]` /admin/organisations/ap:XXXX/products.json (54.225.62.251)'
          ].join("\n")
        })
      end
    end
  end
end
