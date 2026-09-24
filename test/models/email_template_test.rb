require "test_helper"

class EmailTemplateTest < ActiveSupport::TestCase
  setup do
    @request   = registration_requests(:pending_alpha)
    @moderator = moderators(:avery)
  end

  def template(**attributes)
    EmailTemplate.new(instance: instances(:alpha), name: "Ask", subject: "", body: "Hi", **attributes)
  end

  test "placeholders are filled in for the applicant and the moderator" do
    filled = template(subject: "Your application to {{instance}}",
      body: "Hi {{ display_name }} (@{{username}}, {{email}}),\n— {{moderator}}")
      .render_for(@request, moderator: @moderator)

    assert_equal "Your application to #{instances(:alpha).domain}", filled[:subject]
    assert_equal "Hi rowan (@rowan, rowan@fastmail.com),\n— Avery", filled[:body]
  end

  test "the display name is used when the applicant has one" do
    @request.display_name = "Rowan R."
    assert_equal "Rowan R.", template(body: "{{display_name}}").render_for(@request, moderator: @moderator)[:body]
  end

  test "a missing value becomes empty rather than failing" do
    @request.email = nil
    assert_equal "to: ", template(body: "to: {{email}}").render_for(@request, moderator: @moderator)[:body]
  end

  # A typo would otherwise go out to the applicant as a literal {{usernmae}}.
  test "an unknown placeholder is rejected" do
    record = template(subject: "{{usernmae}}", body: "{{nope}} {{username}}")

    refute record.valid?
    assert_includes record.errors[:subject].join, "{{usernmae}}"
    assert_includes record.errors[:body].join, "{{nope}}"
  end

  test "a template must belong to an instance" do
    refute EmailTemplate.new(name: "Ask", body: "Hi").valid?
  end

  test "names are unique per instance, not across instances" do
    template.save!

    refute template.valid?
    assert EmailTemplate.new(instance: instances(:beta), name: "Ask", body: "Hi").valid?
  end
end
