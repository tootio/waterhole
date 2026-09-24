module Flags
  class Rule
    # Flags::DisposableEmail -> "disposable_email"
    def self.rule_name = name.demodulize.underscore

    def self.call(request) = new(request).call

    def initialize(request) = @request = request

    # Evaluate the rule for the given request.
    # This method should return a Flags::Detection object if the rule is triggered, or nil if it is not.
    #
    # Evaluation takes place inside a transaction and with a row lock on the request to prevent races.
    # Thus, it should not do heavy work.
    def call
      raise NotImplementedError
    end

    private

    attr_reader :request

    def detect(severity, **details)
      Detection.new(rule: self.class.rule_name, severity: Flag.severities.fetch(severity.to_s), details:)
    end
  end
end
