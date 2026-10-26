require "application_system_test_case"

# translate_controller.js: names and translates the reason for joining with
# the browser's on-device LanguageDetector and Translator. Real models are not
# something CI can download, so these stand in fakes before the page loads.
class TranslateTest < ApplicationSystemTestCase
  VIETNAMESE = "muốn lan tỏa điều tốt đẹp".freeze

  setup do
    @request = registration_requests(:pending_alpha)
    sign_in_as moderators(:avery)
  end

  teardown do
    # Registered scripts outlive the test: the browser is reused for the next.
    page.driver.browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: @fake) if @fake
  end

  test "names the reason's language and translates it into the page language" do
    @request.update_columns(invite_request: VIETNAMESE)
    fake_translation_apis
    visit registration_request_path(@request)

    assert_selector "[data-translate-target=language]", text: "Vietnamese"
    assert_selector "[data-translate-target=source][lang=vi]"

    click_button "Translate to English"

    assert_selector "[data-translate-target=output][lang=en]", text: "[vi→en] #{VIETNAMESE}"
    assert_text "Translated from Vietnamese by your browser, on this device."
    assert_no_button "Translate to English"
  end

  test "a reason already in the page language is named but not offered for translation" do
    fake_translation_apis
    visit registration_request_path(@request)

    assert_selector "[data-translate-target=language]", text: "English"
    assert_selector "[data-translate-target=source][lang=en]"
    assert_no_button "Translate to English"
  end

  # create() may only start a download on a user gesture, so an undownloaded
  # detector waits for the click instead of naming nothing on load.
  test "an undownloaded detector detects on the click" do
    @request.update_columns(invite_request: VIETNAMESE)
    fake_translation_apis(detector: "downloadable")
    visit registration_request_path(@request)

    click_button "Translate to English"

    assert_selector "[data-translate-target=language]", text: "Vietnamese"
    assert_selector "[data-translate-target=output]", text: "[vi→en] #{VIETNAMESE}"
  end

  test "a language pair the browser cannot translate says so" do
    @request.update_columns(invite_request: VIETNAMESE)
    fake_translation_apis(translator: "unavailable")
    visit registration_request_path(@request)

    click_button "Translate to English"

    assert_text "Your browser cannot translate Vietnamese to English."
    assert_no_selector "[data-translate-target=output]", visible: true
  end

  test "browsers without the APIs get the original only, with its language left unknown" do
    @request.update_columns(invite_request: VIETNAMESE)
    fake_translation_apis(supported: false)
    visit registration_request_path(@request)

    assert_text VIETNAMESE
    assert_selector "[data-translate-target=source][lang='']"
    assert_no_button "Translate to English"
    assert_no_selector "[data-translate-target=language]", visible: true
  end

  # Every claim and decision broadcasts a refresh, and the morph patches the
  # server-rendered markup back in without disconnecting the controller.
  test "the translation survives a refresh morph" do
    @request.update_columns(invite_request: VIETNAMESE)
    fake_translation_apis
    visit registration_request_path(@request)
    click_button "Translate to English"
    assert_selector "[data-translate-target=output]", text: "[vi→en]"

    page.execute_script(<<~JS)
      window.__statusChanges = 0
      new MutationObserver(() => window.__statusChanges++)
        .observe(document.getElementById("translate_status"), { childList: true, characterData: true, subtree: true })
    JS
    page.execute_script("document.addEventListener('turbo:render', e => { document.documentElement.dataset.renderMethod = e.detail.renderMethod })")
    page.execute_script("Turbo.session.refresh(location.href)")
    assert_selector "html[data-render-method]", visible: :all
    assert_equal "morph", page.evaluate_script("document.documentElement.dataset.renderMethod")

    assert_selector "[data-translate-target=output]", text: "[vi→en] #{VIETNAMESE}"
    assert_selector "[data-translate-target=source][lang=vi]"
    assert_no_button "Translate to English"
    # Left alone, so screen readers do not hear the status again.
    assert_equal 0, page.evaluate_script("window.__statusChanges")
    assert_text "Translated from Vietnamese by your browser, on this device."
  end

  # The click allows a download for a few seconds only, and fetching the
  # detector first can use them up; create() would then fail.
  test "a click that went stale asks for another one instead of failing" do
    @request.update_columns(invite_request: VIETNAMESE)
    fake_translation_apis(translator: "downloadable", activation: false)
    visit registration_request_path(@request)

    click_button "Translate to English"

    assert_text "This is Vietnamese. Click again to download its translation model."
    assert_button "Translate to English"
    assert_no_selector "[data-translate-target=output]", visible: true
  end

  test "an availability check that never settles still offers the button" do
    @request.update_columns(invite_request: VIETNAMESE)
    fake_translation_apis(detector: "hang")
    visit registration_request_path(@request)

    click_button "Translate to English"

    assert_selector "[data-translate-target=output]", text: "[vi→en] #{VIETNAMESE}"
  end

  test "a reason nobody could tell the language of is not offered for translation" do
    fake_translation_apis(detected: "und")
    visit registration_request_path(@request)

    assert_selector "[data-translate-target=source][lang='']"
    assert_no_button "Translate to English"
    assert_no_selector "[data-translate-target=language]", visible: true
  end

  test "the detected tag is passed on whole, script and all" do
    @request.update_columns(invite_request: "想加入本地社群")
    fake_translation_apis(detected: "zh-Hant")
    visit registration_request_path(@request)

    assert_selector "[data-translate-target=language]", text: "Traditional Chinese"
    assert_selector "[data-translate-target=source][lang=zh-Hant]"

    click_button "Translate to English"
    assert_selector "[data-translate-target=output]", text: "[zh-Hant→en]"
  end

  test "a failed translation says so in plain words" do
    @request.update_columns(invite_request: VIETNAMESE)
    fake_translation_apis(translator_fails: true)
    visit registration_request_path(@request)

    click_button "Translate to English"

    assert_text "Your browser could not translate this. Try again, or use its own page translation."
    assert_button "Translate to English"
  end

  test "Back shows the translation it left, without translating again" do
    @request.update_columns(invite_request: VIETNAMESE)
    fake_translation_apis
    visit registration_request_path(@request)
    click_button "Translate to English"
    assert_selector "[data-translate-target=output]", text: "[vi→en]"

    click_on "Back to queue"
    assert_selector "#queue_rows"
    page.go_back

    assert_selector "[data-translate-target=output]", text: "[vi→en] #{VIETNAMESE}"
    assert_no_button "Translate to English"
    assert_equal 1, page.evaluate_script("window.__translations")
  end

  test "the queue does not claim a reason is English either" do
    visit root_path

    assert_selector "#queue_rows span[lang='']", text: @request.invite_request.truncate(30, omission: "")
  end

  private

  # Unless told what to detect, the detector calls anything with a Vietnamese
  # diacritic Vietnamese and everything else English; the translator tags its
  # input with the pair and counts its calls in window.__translations.
  # detector: "hang" never settles availability(), as Electron's can.
  # activation: false stands in for a click whose few seconds ran out.
  def fake_translation_apis(supported: true, detector: "available", detected: nil, translator: "available",
                            translator_fails: false, activation: true)
    source = if supported
      <<~JS
        window.__translations = 0
        window.LanguageDetector = {
          availability: () => #{detector == "hang" ? "new Promise(() => {})" : "Promise.resolve(#{detector.to_json})"},
          create: async () => ({
            detect: async (text) => [{ detectedLanguage: #{detected.to_json} || (/[ốảỏđẹ]/.test(text) ? "vi" : "en"), confidence: 0.9 }],
            destroy() {}
          })
        }
        window.Translator = {
          availability: async () => #{translator.to_json},
          create: async ({ sourceLanguage, targetLanguage }) => {
            if (#{translator_fails}) throw new DOMException("", "OperationError")
            return {
              translate: async (text) => { window.__translations++; return `[${sourceLanguage}→${targetLanguage}] ${text}` },
              destroy() {}
            }
          }
        }
        #{"Object.defineProperty(navigator, 'userActivation', { get: () => ({ isActive: false, hasBeenActive: true }) })" unless activation}
      JS
    else
      "delete window.LanguageDetector; delete window.Translator; delete Window.prototype.LanguageDetector; delete Window.prototype.Translator"
    end

    @fake = page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: source)["identifier"]
  end
end
