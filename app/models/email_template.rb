# A canned email a herd's moderators send applicants from their own mail
# client. Waterhole never sends it: the request page turns it into a mailto:
# link, filled in for that applicant.
#
# Always per instance, like KeywordRule, and for the same reason: every
# instance's moderators may edit their templates.
class EmailTemplate < ApplicationRecord
  # {{username}}, with optional spaces inside the braces.
  PLACEHOLDER = /\{\{\s*(\w+)\s*\}\}/

  Placeholder = Data.define(:label, :value)

  # In the order the form offers them.
  PLACEHOLDERS = {
    "username"     => Placeholder.new("Username",     ->(request, _) { request.username }),
    "display_name" => Placeholder.new("Display name", ->(request, _) { request.display_name.presence || request.username }),
    "email"        => Placeholder.new("Email",        ->(request, _) { request.email }),
    "instance"     => Placeholder.new("Instance",     ->(request, _) { request.instance.domain }),
    "moderator"    => Placeholder.new("Your name",    ->(_, moderator) { moderator.name })
  }.freeze

  # A mailto: link much longer than this is cut off or refused by some mail
  # clients and browsers.
  MAX_SUBJECT = 200
  MAX_BODY = 4000

  belongs_to :instance

  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: true, length: { maximum: 100 }, uniqueness: { scope: :instance_id }
  validates :subject, length: { maximum: MAX_SUBJECT }
  validates :body, presence: true, length: { maximum: MAX_BODY }
  validate  :placeholders_known

  scope :enabled, -> { where(enabled: true) }

  # The subject and body with every placeholder filled in for this applicant,
  # written by this moderator.
  def render_for(request, moderator:)
    { subject: fill(subject.to_s, request, moderator), body: fill(body.to_s, request, moderator) }
  end

  private

  def fill(text, request, moderator)
    text.gsub(PLACEHOLDER) { PLACEHOLDERS.fetch($1).value.call(request, moderator).to_s }
  end

  def placeholders_known
    %i[subject body].each do |attribute|
      unknown = public_send(attribute).to_s.scan(PLACEHOLDER).flatten.uniq - PLACEHOLDERS.keys
      next if unknown.empty?

      errors.add(attribute, "uses unknown placeholder#{"s" if unknown.many?} #{unknown.map { "{{#{it}}}" }.to_sentence}")
    end
  end
end
