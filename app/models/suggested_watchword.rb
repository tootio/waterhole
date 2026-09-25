# Watchwords most instances will want, from config/watchwords.yml. Only
# suggestions: applying one opens the New watchword form pre-filled, and the
# saved rule belongs to that instance alone (see KeywordRule for why there are
# no deployment-wide rules).
class SuggestedWatchword < Data.define(:pattern, :match_type, :severity, :description, :reasoning)
  FILE = Rails.root.join("config/watchwords.yml")

  # Not memoized: the file is tiny, and edits show up without a restart.
  def self.all
    YAML.load_file(FILE).map { new(**it.symbolize_keys) }
  end

  # Same pattern and match type; severity, note and enabled may differ.
  def applied?(rules) = rules.any? { it.pattern == pattern && it.match_type == match_type }

  # `reasoning` only explains the suggestion; it is not part of the rule.
  def to_params = { pattern:, match_type:, severity:, description: }
end
