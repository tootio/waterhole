module Flags
  class Rule
    # Flags::DisposableEmail -> "disposable_email"
    def self.rule_name = name.demodulize.underscore

    def self.call(request) = new(request).call

    def initialize(request) = @request = request

    def call = raise NotImplementedError

    private

    attr_reader :request

    def detect(severity, **details)
      Detection.new(rule: self.class.rule_name, severity: Flag.severities.fetch(severity.to_s), details:)
    end
  end
end
