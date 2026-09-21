require "test_helper"

class Blocklists::IftasDniTest < ActiveSupport::TestCase
  HEADER = "#domain,#severity,#reject_media,#reject_reports,#public_comment,#obfuscate"
  CANARY_ROW = %("dni.invalid","suspend","FALSE","FALSE","iftas:canary","TRUE")

  # Every real response carries the canary row; tests about ordinary parsing
  # add it automatically so they don't have to think about the guard.
  def csv(*rows) = csv_without_canary(*rows, CANARY_ROW)

  def csv_without_canary(*rows) = ([ HEADER ] + rows).join("\n")

  test "parses domain and public comment, lowercasing the domain" do
    entries = Blocklists::IftasDni.parse(csv(%("Spam.Example","suspend","FALSE","FALSE","iftas:csam","TRUE")))

    assert_equal [ { domain: "spam.example", reason: "iftas:csam" } ], entries
  end

  test "skips a row whose severity is not suspend" do
    entries = Blocklists::IftasDni.parse(csv(%("silenced.example","silence","FALSE","FALSE","iftas:spam","TRUE")))

    assert_empty entries
  end

  test "the canary row itself never appears in the parsed entries" do
    entries = Blocklists::IftasDni.parse(csv)

    assert_empty entries
  end

  test "a canary tag combined with other tags still counts as the canary" do
    body = csv_without_canary(
      %("other.example","suspend","FALSE","FALSE","iftas:spam","TRUE"),
      %("dni.invalid","suspend","FALSE","FALSE","iftas:canary;other","TRUE")
    )

    entries = Blocklists::IftasDni.parse(body)

    assert_equal [ { domain: "other.example", reason: "iftas:spam" } ], entries
  end

  test "an empty public comment becomes a nil reason" do
    entries = Blocklists::IftasDni.parse(csv(%("bare.example","suspend","FALSE","FALSE","","TRUE")))

    assert_equal [ { domain: "bare.example", reason: nil } ], entries
  end

  test "skips a blank domain" do
    entries = Blocklists::IftasDni.parse(csv(%("","suspend","FALSE","FALSE","iftas:spam","TRUE")))

    assert_empty entries
  end

  # The canary's whole job is to catch a response that looks fine otherwise --
  # a stale cache, the wrong sheet, an upstream format change -- so its
  # absence must reject the response outright rather than just being noted.
  test "raises when the canary row is missing" do
    body = csv_without_canary(%("spam.example","suspend","FALSE","FALSE","iftas:csam","TRUE"))

    error = assert_raises(RuntimeError) { Blocklists::IftasDni.parse(body) }
    assert_match(/canary/, error.message)
  end

  test "raises when there are no rows at all" do
    assert_raises(RuntimeError) { Blocklists::IftasDni.parse(HEADER) }
  end
end
