module Flags
  # Marks a rule whose flags depend on requests other than the one it runs on,
  # on this or another instance: a new, changed or purged request has to
  # recompute theirs too. Flags.cross_instance_rules finds the rules by this
  # module, and each one says through `counterparts` which requests those are.
  #
  # Including it is the whole registration: a rule that defines `counterparts`
  # without including it is left out of that fan-out and of the hourly sweep,
  # and one that includes it without defining `counterparts` raises.
  module CrossInstanceFlag
    extend ActiveSupport::Concern

    class_methods do
      def counterparts(request)
        raise NotImplementedError, "#{name} includes Flags::CrossInstanceFlag but defines no counterparts"
      end
    end
  end
end
