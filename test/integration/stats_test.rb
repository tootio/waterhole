require "test_helper"

class StatsTest < ActionDispatch::IntegrationTest
  setup do
    @mine = moderators(:avery).instance
    sign_in_as moderators(:avery)
  end

  def count_an_hour(instance, **counts)
    instance.registration_stats.create!(hour: 2.hours.ago.beginning_of_hour, **counts)
  end

  test "the page sits under My herd and charts your own signups" do
    count_an_hour(@mine, signups: 4, approved: 3, rejected: 1, flagged: 1)

    get stats_path

    assert_response :success
    assert_select "nav[aria-label='My herd'] a[aria-current=page]", "Stats"
    assert_select "[data-controller=chart][data-chart-kind-value=outcomes]"
    assert_select "dl dd", "75% of decided"
  end

  test "an empty period says so instead of drawing nothing" do
    get stats_path

    assert_select "[data-chart-kind-value=outcomes]", count: 0
    assert_select "p", /No signups in the last 14 days/
  end

  test "the period can be chosen, and a nonsense one is the default" do
    count_an_hour(@mine, signups: 1)

    get stats_path(period: "90d")
    assert_select "nav[aria-label=Period] a[aria-current=page]", "90 days"

    get stats_path(period: "sideways")
    assert_select "nav[aria-label=Period] a[aria-current=page]", "14 days"
  end

  test "a herd that does not share signals sees no shared numbers" do
    @mine.update_columns(signals_opted_in: false)
    count_an_hour(instances(:beta), signups: 50)

    get stats_path

    assert_select "#shared", /does not share signals/
    assert_select "[data-chart-kind-value=shared]", count: 0
  end

  # Two herds: the total minus your own would be the other herd's count.
  test "with fewer than three sharing herds the total is withheld" do
    count_an_hour(@mine, signups: 1)

    get stats_path

    assert_select "#shared", /2 herds share signals so far/
    assert_select "[data-chart-kind-value=shared]", count: 0
  end

  test "from three sharing herds the total is charted" do
    instances(:gamma).update_columns(signals_opted_in: true, signals_approved: true)
    count_an_hour(@mine, signups: 1)
    count_an_hour(instances(:beta), signups: 2, signalled: 1)
    count_an_hour(instances(:unverified), signups: 100)

    get stats_path

    assert_select "#shared [data-chart-kind-value=shared]" do |chart|
      data = JSON.parse(chart.first["data-chart-series-value"])
      assert_equal 3, data["signups"].sum
      assert_equal 1, data["signalled"].sum
    end
  end
end
