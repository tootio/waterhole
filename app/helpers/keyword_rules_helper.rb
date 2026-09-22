module KeywordRulesHelper
  # Any watchword match is wrapped in <mark />
  def highlight_keywords(text)
    return text if text.blank?

    intervals = instance_keyword_rules.flat_map { |rule| rule.match_indices(text) }
    return text if intervals.empty?

    merged = merge_match_intervals(intervals)
    parts = split_into_parts(text, merged)
    safe_join(parts.map { |part| part.mark? ? content_tag(:mark, part.text) : part.text })
  end

  private

  def merge_match_intervals(intervals)
    sorted = intervals.sort_by { |s, e| [ s, e ] }
    merged = []
    sorted.each do |start_pos, stop_pos|
      if merged.empty? || merged.last[1] < start_pos
        merged << [ start_pos, stop_pos ]
      else
        merged.last[1] = [ merged.last[1], stop_pos ].max
      end
    end
    merged
  end

  Part = Data.define(:text, :mark?)

  def split_into_parts(text, matches)
    return [] if text.empty?
    return [ Part.new(text: text, mark?: false) ] if matches.empty?

    parts = []
    current_idx = 0

    matches.each do |start_pos, stop_pos|
      if start_pos > current_idx
        parts << Part.new(text: text[current_idx...start_pos], mark?: false)
      end
      if stop_pos > start_pos
        parts << Part.new(text: text[start_pos...stop_pos], mark?: true)
      end
      current_idx = stop_pos
    end

    if current_idx < text.length
      parts << Part.new(text: text[current_idx..], mark?: false)
    end

    parts
  end

  def instance_keyword_rules
    @instance_keyword_rules ||= Current.mastodon_instance&.keyword_rules&.enabled&.to_a || []
  end
end
