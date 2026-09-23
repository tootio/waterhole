module KeywordRulesHelper
  # .text-marker is defined in application.css.
  MARK_STYLES = {
    "critical" => "text-marker text-marker-critical",
    "warning"  => "text-marker text-marker-warning",
    "info"     => "text-marker text-marker-info"
  }.freeze

  # Any watchword match is wrapped in <mark />, coloured by its rule's severity.
  # Where matches overlap, see #resolve_match_intervals for which one shows.
  def highlight_keywords(text)
    return text if text.blank?

    intervals = instance_keyword_rules.flat_map do |rule|
      rule.match_indices(text).map { |start_pos, stop_pos| Match.new(start_pos, stop_pos, rule.severity) }
    end
    return text if intervals.empty?

    parts = split_into_parts(text, resolve_match_intervals(intervals))
    safe_join(parts.each_with_index.map do |part, i|
      next part.text unless part.mark?

      # The marker overshoots its text on both sides; where it touches another
      # mark, that overshoot would paint over the neighbour's first/last letter.
      classes = [ MARK_STYLES.fetch(part.severity) ]
      classes << "text-marker-joined-start" if i.positive? && parts[i - 1].mark?
      classes << "text-marker-joined-end" if parts[i + 1]&.mark?
      content_tag(:mark, part.text, class: classes.join(" "))
    end)
  end

  private

  Match = Struct.new(:start, :stop, :severity) do
    def length = stop - start
    def rank = Flag::SEVERITIES.fetch(severity.to_sym)
    def covers?(from, to) = start <= from && to <= stop
    # Sharing a boundary is not strict containment: [0, 5] does not strictly contain [0, 3].
    def strictly_contains?(other) = start < other.start && other.stop < stop
  end

  # Turns possibly overlapping matches into disjoint, sorted [start, stop, severity]
  # pieces. Every character covered by any match stays covered; which match it
  # belongs to is decided per character:
  #
  # 1. a match strictly inside another (sharing neither start nor end) wins over
  #    the outer one, whatever their severities: [0, 5], [2, 3] -> [0, 2], [2, 3], [3, 5]
  # 2. otherwise the highest severity wins:
  #    [0, 4, critical], [2, 5, info] -> [0, 4, critical], [4, 5, info]
  # 3. on equal severity the shorter match wins, then the one starting first.
  #
  # Pieces of different matches stay separate even when adjacent and of equal
  # severity, so each match's boundaries remain visible.
  def resolve_match_intervals(matches)
    matches = matches.uniq { [ it.start, it.stop, it.severity ] }
    boundaries = matches.flat_map { [ it.start, it.stop ] }.uniq.sort

    pieces = []
    boundaries.each_cons(2) do |from, to|
      covering = matches.select { it.covers?(from, to) }
      next if covering.empty?

      innermost = covering.reject { |outer| covering.any? { outer.strictly_contains?(it) } }
      winner = innermost.min_by { [ -it.rank, it.length, it.start ] }

      if pieces.last && pieces.last[:match].equal?(winner) && pieces.last[:stop] == from
        pieces.last[:stop] = to
      else
        pieces << { start: from, stop: to, match: winner }
      end
    end

    pieces.map { [ it[:start], it[:stop], it[:match].severity.to_s ] }
  end

  Part = Data.define(:text, :severity) do
    def mark? = !severity.nil?
  end

  def split_into_parts(text, matches)
    return [] if text.empty?
    return [ Part.new(text: text, severity: nil) ] if matches.empty?

    parts = []
    current_idx = 0

    matches.each do |start_pos, stop_pos, severity|
      if start_pos > current_idx
        parts << Part.new(text: text[current_idx...start_pos], severity: nil)
      end
      if stop_pos > start_pos
        parts << Part.new(text: text[start_pos...stop_pos], severity: severity)
      end
      current_idx = stop_pos
    end

    if current_idx < text.length
      parts << Part.new(text: text[current_idx..], severity: nil)
    end

    parts
  end

  def instance_keyword_rules
    @instance_keyword_rules ||= Current.mastodon_instance&.keyword_rules&.enabled&.to_a || []
  end
end
