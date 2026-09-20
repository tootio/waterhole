require "test_helper"

class HerdDetailTest < ActionDispatch::IntegrationTest
  setup { sign_in_as moderators(:avery) }

  def mine  = moderators(:avery).instance
  def other = instances(:beta)

  test "a herd is addressed by its domain, dots and all" do
    get herd_path(other)

    assert_response :success
    assert_equal "/herds/#{other.domain}", path
    assert_select "h1", other.domain
  end

  test "your own herd has no special address" do
    get herd_path(mine)

    assert_response :success
    assert_equal "/herds/#{mine.domain}", path
  end

  test "your own page shows the plumbing" do
    get herd_path(mine)

    assert_select "h2", /Authorisation/
    assert_select "h2", /Sync/
    assert_select "h2", /Cross-instance signals/
  end

  # Someone else's sync, tokens and failed checks are their business.
  test "another herd's page shows its status and signals, and nothing else" do
    get herd_path(other)

    assert_select "h2", /Authorisation/
    assert_select "h2", /Cross-instance signals/
    assert_select "h2", { text: /Sync/, count: 0 }
    assert_select "body", { text: /Token borrowed from/, count: 0 }
    assert_select "body", { text: /Mastodon scopes/, count: 0 }
  end

  test "both pages link to the instance itself" do
    [ mine, other ].each do |instance|
      get herd_path(instance)

      assert_select "a[href=?]", instance.base_url, { minimum: 1 },
        "expected a link to #{instance.base_url}"
    end
  end

  # Your own page names both keys, because you can act on one of them.
  test "only your own page breaks signals into its two keys" do
    mine.update!(signals_opted_in: false, signals_approved: false)
    other.update!(signals_opted_in: false, signals_approved: false)

    get herd_path(mine)
    assert_select "body", /does not opt in/
    assert_select "body", /not approved/

    get herd_path(other)
    assert_select "body", { text: /not approved/, count: 0 },
      "why another herd is out is the operator's business"
  end

  test "a blocked herd has no page, not even by URL" do
    other.update!(status: "blocked")

    get herd_path(other)

    assert_response :not_found
  end

  test "a domain that was never here is not found" do
    get "/herds/nobody.example"

    assert_response :not_found
  end

  test "the case a domain is typed in does not matter" do
    get "/herds/#{other.domain.upcase}"

    assert_response :success
    assert_select "h1", other.domain
  end

  test "every page leads back to the herds" do
    get herd_path(other)

    assert_select "a[href=?]", herds_path
  end
end
