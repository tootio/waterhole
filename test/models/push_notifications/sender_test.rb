require "test_helper"

module PushNotifications
  class SenderTest < ActiveSupport::TestCase
    include PushTestHelper

    setup do
      @moderator = moderators(:avery)
      @subscription = subscribe_browser(@moderator)
    end

    def stub_push(status) = stub_request(:post, @subscription.endpoint).to_return(status:)

    test "the payload is declarative and holds no names" do
      payload = JSON.parse(Message.new_registrations(2, waiting: 2, audience: @moderator.id, path: "/").to_json)

      assert_equal 8030, payload["web_push"]
      assert_equal "Waterhole", payload.dig("notification", "title")
      assert_equal "2 new registrations are waiting", payload.dig("notification", "body")
      assert_equal "new-registrations-#{@moderator.id}", payload.dig("notification", "tag")
      assert payload.dig("notification", "renotify")
      assert_equal "#{Waterhole::Deployment.base_url}/", payload.dig("notification", "navigate")
      refute_match(/#{Regexp.escape(@moderator.instance.domain)}|#{@moderator.username}/, payload.to_s)
    end

    test "sends encrypted, signed and with a limited lifetime" do
      stub_push(201)

      assert_equal :delivered, Sender.deliver_to(@subscription, Message.test)

      assert_requested(:post, @subscription.endpoint) do |request|
        request.headers["Content-Encoding"] == "aes128gcm" &&
          request.headers["Authorization"].start_with?("vapid t=") &&
          request.headers["Ttl"] == 1.day.to_i.to_s &&
          !request.body.include?("Waterhole")
      end
    end

    test "a 410 or 404 deletes the subscription" do
      [ 410, 404 ].each do |status|
        subscription = subscribe_browser(@moderator)
        stub_request(:post, subscription.endpoint).to_return(status:)

        assert_equal :gone, Sender.deliver_to(subscription, Message.test)
        refute PushSubscription.exists?(subscription.id)
      end
    end

    test "a temporary failure keeps the subscription and is not reported" do
      [ 429, 500, 503 ].each do |status|
        stub_push(status)
        assert_no_error_reported { assert_equal :failed, Sender.deliver_to(@subscription, Message.test) }
      end

      stub_request(:post, @subscription.endpoint).to_timeout
      assert_no_error_reported { assert_equal :failed, Sender.deliver_to(@subscription, Message.test) }

      [ SocketError, Net::HTTPBadResponse ].each do |error|
        stub_request(:post, @subscription.endpoint).to_raise(error)
        assert_no_error_reported { assert_equal :failed, Sender.deliver_to(@subscription, Message.test) }
      end

      assert PushSubscription.exists?(@subscription.id)
    end

    test "a rejected key ends the subscription, and is reported once" do
      stub_push(403)

      assert_error_reported(WebPush::Unauthorized) do
        assert_equal :gone, Sender.deliver_to(@subscription, Message.test)
      end
      refute PushSubscription.exists?(@subscription.id)
    end

    test "keys that cannot encrypt end the subscription without contacting anyone" do
      @subscription.update_columns(p256dh: "not-a-key")

      assert_equal :gone, Sender.deliver_to(@subscription.reload, Message.test)
      assert_not_requested :post, @subscription.endpoint
    end

    test "our own malformed VAPID key is reported, and nothing is lost" do
      saved = ENV["WATERHOLE_VAPID_PRIVATE_KEY"]
      ENV["WATERHOLE_VAPID_PRIVATE_KEY"] = "not-a-key"

      assert_error_reported { assert_equal :failed, Sender.deliver_to(@subscription, Message.test) }
      assert PushSubscription.exists?(@subscription.id)
    ensure
      ENV["WATERHOLE_VAPID_PRIVATE_KEY"] = saved
    end

    test "an endpoint no longer on the list is dropped without being contacted" do
      @subscription.update_column(:endpoint, "https://internal.example/x")
      assert_equal "https://internal.example/x", @subscription.reload.endpoint

      assert_equal :gone, Sender.deliver_to(@subscription.reload, Message.test)
      assert_not_requested :post, "https://internal.example/x"
    end

    test "deliver is done once any browser took it, or none is left" do
      other = subscribe_browser(@moderator)
      stub_push(503)
      stub_request(:post, other.endpoint).to_return(status: 201)
      assert Sender.deliver(@moderator, Message.test)

      stub_request(:post, other.endpoint).to_return(status: 503)
      refute Sender.deliver(@moderator.reload, Message.test)

      stub_push(410)
      stub_request(:post, other.endpoint).to_return(status: 410)
      assert Sender.deliver(@moderator.reload, Message.test)
      assert_empty @moderator.reload.push_subscriptions
    end

    test "deliver sees the browsers as they are now" do
      stub_push(410)
      @moderator.push_subscriptions.load
      Sender.deliver(@moderator, Message.test)

      assert_requested :post, @subscription.endpoint, times: 1
      assert Sender.deliver(@moderator, Message.test)
      assert_requested :post, @subscription.endpoint, times: 1
    end
  end
end
