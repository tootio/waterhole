require "test_helper"

class EmailTemplatesTest < ActionDispatch::IntegrationTest
  setup do
    @moderator = sign_in_as moderators(:avery)
    @own   = EmailTemplate.create!(instance: instances(:alpha), name: "Ask for more", subject: "About {{username}}", body: "Hello {{username}}")
    @other = EmailTemplate.create!(instance: instances(:beta), name: "Beta only", body: "Hi")
  end

  test "a moderator sees only their own instance's templates" do
    get email_templates_path

    assert_response :success
    assert_select "li", /Ask for more/
    assert_select "li", { count: 0, text: /Beta only/ }
  end

  test "the form offers every placeholder to insert" do
    get new_email_template_path

    EmailTemplate::PLACEHOLDERS.each_key do |key|
      assert_select "button[data-placeholder-insert-token-param=?]", "{{#{key}}}"
    end
  end

  test "a moderator can add, edit and delete their own instance's templates" do
    post email_templates_path, params: { email_template: { name: "Rejected", subject: "", body: "Sorry {{username}}" } }
    assert_equal instances(:alpha), EmailTemplate.find_by!(name: "Rejected").instance

    patch email_template_path(@own), params: { email_template: { body: "Hey {{display_name}}" } }
    assert_equal "Hey {{display_name}}", @own.reload.body

    delete email_template_path(@own)
    refute EmailTemplate.exists?(@own.id)
  end

  test "an unknown placeholder is shown back rather than saved" do
    post email_templates_path, params: { email_template: { name: "Typo", body: "Hi {{usrname}}" } }

    assert_response :unprocessable_entity
    assert_select "div", /\{\{usrname\}\}/
  end

  test "another instance's templates cannot be changed" do
    patch email_template_path(@other), params: { email_template: { body: "Pwned" } }
    assert_response :not_found
    assert_equal "Hi", @other.reload.body

    delete email_template_path(@other)
    assert_response :not_found
    assert EmailTemplate.exists?(@other.id)
  end

  test "the request page offers the instance's templates as filled-in mailto links" do
    request = registration_requests(:pending_alpha)
    get registration_request_path(request)

    assert_select "details a[href=?]", "mailto:rowan@fastmail.com?subject=About%20rowan&body=Hello%20rowan", text: "Ask for more"
    assert_select "details a", { count: 0, text: "Beta only" }
  end

  test "a disabled template is listed for editing but not offered on the request page" do
    patch email_template_path(@own), params: { email_template: { enabled: "0" } }
    refute @own.reload.enabled?

    get email_templates_path
    assert_select "li", /Ask for more.*disabled/m

    get registration_request_path(registration_requests(:pending_alpha))
    assert_select "main details", false
  end

  test "without templates the request page points to setting them up" do
    EmailTemplate.delete_all
    get registration_request_path(registration_requests(:pending_alpha))

    assert_select "main details", false
    assert_select "a[href=?]", email_templates_path
  end

  test "an applicant without an address gets no email menu" do
    request = registration_requests(:pending_alpha)
    request.update_columns(email: nil)
    get registration_request_path(request)

    assert_select "main details", false
  end
end
