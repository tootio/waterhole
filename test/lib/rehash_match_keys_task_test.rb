require "test_helper"
require "rake"

class RehashMatchKeysTaskTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Rails.application.load_tasks if Rake::Task.tasks.none?
    # Fixtures load without callbacks, so their derived keys start empty.
    # Bring them up to date first; the tests are about what happens next.
    rehash
  end

  def rehash
    Rake::Task["waterhole:rehash_match_keys"].reenable
    capture_io { Rake::Task["waterhole:rehash_match_keys"].invoke }
    Rake::Task["waterhole:rehash_match_keys"].reenable
  end

  # As if stored under older rules that did not merge googlemail.com into
  # gmail.com: the key no longer matches what the current rules produce.
  test "rows stored under old rules get today's key and refresh their flags" do
    request = registration_requests(:pending_alpha)
    request.update_columns(canonical_email_hash: "stale", email_domain: "STALE.example")

    assert_output(/Recomputed match keys on 1 request\./) { Rake::Task["waterhole:rehash_match_keys"].invoke }

    request.reload
    assert_equal EmailCanonicalizer.hash_for(request.email), request.canonical_email_hash
    assert_equal EmailCanonicalizer.domain_of(request.email), request.email_domain
  end

  test "an up-to-date database is left alone" do
    assert_output(/Recomputed match keys on 0 requests\./) { Rake::Task["waterhole:rehash_match_keys"].invoke }
  end
end
