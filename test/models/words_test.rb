require "test_helper"

# Where ICU splits a dictionary script depends on its version (CI, the image
# and a Mac each have their own), so those tests check that the text is split
# into plausible words, not where.
class WordsTest < ActiveSupport::TestCase
  test "counts space-separated words" do
    assert_equal 3, Words.count("let me in")
    assert_equal 0, Words.count(nil)
  end

  test "ignores punctuation" do
    assert_equal 2, Words.count("hello - world !!!")
    assert_equal %w[I'd like to join], Words.tokens("I'd like to join!")
  end

  test "counts a URL or a hyphenated word as one word" do
    assert_equal 1, Words.count("https://example.com/join/now/please")
    assert_equal 3, Words.count("my e-mail: me@example.org")
  end

  {
    "Chinese" => "我想加入这个社区",
    "Japanese" => "コンピューターが好きです",
    "Thai" => "ฉันอยากเข้าร่วมชุมชนนี้",
    "Lao" => "ຂ້ອຍຢາກເຂົ້າຮ່ວມຊຸມຊົນນີ້",
    "Khmer" => "ខ្ញុំចង់ចូលរួមសហគមន៍នេះ",
    "Burmese" => "ကျွန်တော်ဒီအသိုင်းအဝိုင်းကိုဝင်ချင်ပါတယ်"
  }.each do |language, text|
    test "splits #{language} into words" do
      tokens = Words.tokens("#{text}。")

      assert_equal text, tokens.join, "every letter belongs to a word"
      assert_includes 4..text.length / 2, tokens.size, "words, not the whole text or single letters: #{tokens.inspect}"
      assert_equal tokens.size, Words.count(text)
    end
  end

  test "splits scripts apart" do
    assert_equal %w[我 用 Mastodon], Words.tokens("我用Mastodon。")
    assert_equal 4, Words.count("我用Mastodon。 hello")
  end

  test "the invite request is counted this way" do
    request = RegistrationRequest.new(invite_request: "我想加入这个社区。")
    assert_equal Words.count(request.invite_request), request.invite_request_words
    assert_operator request.invite_request_words, :>, 1
  end
end
