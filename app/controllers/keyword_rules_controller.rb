class KeywordRulesController < ApplicationController
  before_action :set_keyword_rule, only: %i[edit update destroy]

  # Every change re-flags the instance's whole pending queue.
  throttle to: 20, within: 1.minute, name: "keyword_rule_change",
    by: -> { current_instance.id }, only: %i[create update destroy]

  def index
    @keyword_rules = current_instance.keyword_rules.order(:pattern)
    @suggestions = SuggestedWatchword.all
  end

  def new
    @keyword_rule = current_instance.keyword_rules.new(severity: "warning", match_type: "word")
    # Applying a suggested watchword pre-fills the form.
    @keyword_rule.assign_attributes(keyword_rule_params) if params.key?(:keyword_rule)
  end

  def create
    @keyword_rule = current_instance.keyword_rules.new(keyword_rule_params)

    if @keyword_rule.save
      recompute_pending
      redirect_to keyword_rules_path, notice: "Rule added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @keyword_rule.update(keyword_rule_params)
      recompute_pending
      redirect_to keyword_rules_path, notice: "Rule updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @keyword_rule.destroy!
    recompute_pending
    redirect_to keyword_rules_path, notice: "Rule removed."
  end

  private

  def set_keyword_rule
    @keyword_rule = current_instance.keyword_rules.find(params[:id])
  end

  # Changing the rules changes what the existing queue should be flagged for.
  def recompute_pending
    current_instance.registration_requests.pending.find_each do |request|
      RecomputeFlagsJob.perform_later(request)
    end
  end

  def keyword_rule_params
    params.expect(keyword_rule: [ :pattern, :match_type, :severity, :enabled, :description ])
  end
end
