module SomeHelper
  extend ActiveSupport::Concern

  def calling_method
    failing_method
  end

  def failing_method
    # this is the method that caused the exception
    result = @company.foo
    return result.empty?
  end

  def other_failing_method
    result = "#{self.foo} - #{obj.bar} - #{self.meta.foo}"
    return result.empty?
  end
end
