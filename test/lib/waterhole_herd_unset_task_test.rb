require "test_helper"
require "rake"

class WaterholeHerdUnsetTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.none?
    Rake::Task["waterhole:herd:unset"].reenable
  end

  def unset(domain) = capture_io { Rake::Task["waterhole:herd:unset"].invoke(domain) }

  test "removes a manual policy" do
    policy = domain_policies(:blocked_spam)

    out, = unset(policy.domain)

    assert_match(/Removed policy for #{Regexp.escape(policy.domain)}\./, out)
    assert_not DomainPolicy.exists?(policy.id)
  end

  test "an iftas_dni policy is left alone, with a pointer to allow instead" do
    policy = domain_policies(:blocked_synced)

    out, = unset(policy.domain)

    assert_match(/not set by hand/, out)
    assert_match(/waterhole:herd:allow\[#{Regexp.escape(policy.domain)}\]/, out)
    assert DomainPolicy.exists?(policy.id)
    assert policy.reload.iftas_dni?
  end

  test "a domain with no policy says so" do
    out, = unset("nothing-here.example")

    assert_match(/No policy for nothing-here\.example\./, out)
  end
end
