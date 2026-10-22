# frozen_string_literal: true

require "rails_helper"
require "capybara/rspec"
require "capybara-playwright-driver"

Capybara.register_driver(:playwright) do |app|
  Capybara::Playwright::Driver.new(app, browser_type: :chromium, headless: true,
    playwright_cli_executable_path: File.expand_path("../../node_modules/.bin/playwright", __dir__))
end
Capybara.server = :puma, {Silent: true}

RSpec.describe "Searching in the browser", :meilisearch, type: :system do
  before { driven_by :playwright }

  it "searches as you type, groups people, ticks a facet and opens a record with the keyboard" do
    visit "/"
    fill_in "Search Text", with: "smith 5432"

    expect(page).to have_css(".ql-chip", text: "Last four 5432")
    expect(page).to have_css(".ql-group", count: 1)
    expect(page).to have_css(".ql-group .ql-record[data-querylane-record]", count: 2)
    expect(page).to have_css(".ql-group-title mark", text: "SMITH")
    expect(page).to have_css("#people_info", text: "Showing 1 to 2 of 4 entries")
    expect(page).to have_css(".ql-box-overlay .ql-tok-key", count: 0)

    find(".ql-facet-value", text: "Active").click
    expect(page).to have_field("Search Text", with: "smith 5432 is:active")
    expect(page).to have_css(".ql-facet-value[aria-checked=true]", text: "Active")

    find_field("Search Text").send_keys(:down)
    expect(page.evaluate_script("document.activeElement.dataset.querylaneRecord")).to be_present
    page.driver.with_playwright_page { |playwright| playwright.keyboard.press("Enter") }
    expect(page).to have_text("Opened")
  end

  it "colours operators, masks long digit runs and underlines errors" do
    visit "/"
    fill_in "Search Text", with: "stauts:active 123456789"

    expect(page).to have_css(".ql-box-overlay .ql-tok-key", text: "stauts:")
    expect(page).to have_css(".ql-box-overlay .ql-tok-mask", text: "•••••••••")
    expect(page).to have_css(".ql-error", text: "Did you mean status:?")
    expect(page).to have_css(".ql-box.ql-box-invalid .ql-tok-error")
  end

  it "edits the search in the options panel and writes it back to the box" do
    visit "/"
    fill_in "Search Text", with: "smith"
    expect(page).to have_css(".ql-chip", text: "Name contains smith")

    click_on "Options"
    expect(page).to have_css(".ql-options")
    expect(page).to have_field("Name contains", with: "smith")
    expect(page.evaluate_script("document.activeElement.name")).to eq("compose[name]")

    fill_in "Team", with: "ops"
    find(".ql-options-check", text: "Exclude terminated").click
    expect(page).to have_css(".ql-writes-text", text: "smith team:ops -is:terminated")

    within(".ql-options-foot") { click_on "Search" }
    expect(page).to have_no_css(".ql-options")
    expect(page).to have_field("Search Text", with: "smith team:ops -is:terminated")
    expect(page).to have_css(".ql-chip", text: "Team ops")
  end

  it "loads more records for a person and previews a person with Space" do
    visit "/"
    fill_in "Search Text", with: "smith is:active"
    expect(page).to have_css(".ql-group", count: 2)

    first(".ql-more summary").click
    expect(page).to have_css(".ql-related-head", text: "2 of 2")
    expect(page).to have_css(".ql-related .ql-record", text: "claims")

    find_field("Search Text").send_keys(:down)
    page.driver.with_playwright_page { |playwright| playwright.keyboard.press(" ") }
    expect(page).to have_css(".ql-preview-card", text: "2 records you can see, any status")

    page.driver.with_playwright_page { |playwright| playwright.keyboard.press("Escape") }
    expect(page).to have_no_css(".ql-preview-card")
    expect(page.evaluate_script("document.activeElement.dataset.querylaneRecord")).to be_present
  end

  # Turbo swaps a new answer's rows in a few repaints before it fires
  # turbo:frame-render. A Space pressed in between, whose preview answers after
  # that event, must still open the preview.
  it "previews with Space pressed as soon as a new answer's rows are in" do
    page.driver.with_playwright_page do |playwright|
      playwright.add_init_script(script: <<~JS)
        const fetchNow = window.fetch
        window.fetch = (url, options = {}) => {
          const preview = window.holdPreview && (options.body instanceof FormData || options.body instanceof URLSearchParams) && options.body.has("group")
          return preview ? new Promise((resolve) => setTimeout(resolve, 300)).then(() => fetchNow(url, options)) : fetchNow(url, options)
        }
      JS
    end
    visit "/"
    fill_in "Search Text", with: "smith"
    expect(page).to have_css(".ql-group", count: 1)

    page.execute_script(<<~JS)
      window.holdPreview = true
      const frame = document.getElementById("people-results")
      frame.querySelectorAll("[data-querylane-state]").forEach((state) => state.setAttribute("data-old", ""))
      new MutationObserver((_, observer) => {
        if (!frame.querySelector("[data-querylane-state]:not([data-old])")) return
        observer.disconnect()
        const record = frame.querySelector("[data-querylane-record]")
        record.focus()
        record.dispatchEvent(new KeyboardEvent("keydown", {key: " ", bubbles: true, cancelable: true}))
      }).observe(frame, {childList: true, subtree: true})
    JS
    fill_in "Search Text", with: "smith is:active"

    expect(page).to have_css(".ql-preview-card", text: "2 records you can see, any status")
  end

  it "suggests operators and people in the header box, and opens a person's only record" do
    visit "/elsewhere"
    fill_in "find-input", with: "lee st"
    expect(page).to have_css(".ql-suggest-option code", text: "status:")

    find_field("find-input").send_keys(:tab)
    expect(page).to have_field("find-input", with: "lee status:")
    expect(page).to have_css(".ql-suggest-option code", text: "status:active")

    find_field("find-input").send_keys(:tab)
    expect(page).to have_field("find-input", with: "lee status:active ")
    expect(page).to have_css(".ql-suggest-person", text: "LEE, ANN")
    expect(page).to have_no_css("[data-querylane-complete]")
    expect(page).to have_css("#find-list:not([data-querylane-stale])")

    find_field("find-input").send_keys(:down, :enter)
    expect(page).to have_text("Opened staff s4")
  end

  it "opens the palette with Ctrl-K and runs the full search with Enter" do
    visit "/elsewhere"
    page.driver.with_playwright_page { |playwright| playwright.keyboard.press("Control+k") }
    expect(page).to have_css("dialog.ql-palette[open]")

    fill_in "palette-input", with: "smith"
    expect(page).to have_css(".ql-palette .ql-suggest-person", minimum: 2)
    find_field("palette-input").send_keys(:enter)

    expect(page).to have_field("Search Text", with: "smith")
    expect(page).to have_css(".ql-group-title", text: "SMITH, JOHN")
  end

  it "saves a search, runs it from the Saved list, and refuses one holding a last four" do
    MemorySavedSearches.reset!
    visit "/"
    fill_in "Search Text", with: "smith team:ops"
    expect(page).to have_css(".ql-chip", text: "Team ops")

    click_on "Saved"
    fill_in "people-saved-name", with: "Ops Smiths"
    within("#people-saved") { click_on "Save" }
    expect(page).to have_css(".ql-notice", text: "Search saved.")

    fill_in "Search Text", with: "smith 5432"
    expect(page).to have_css(".ql-chip", text: "Last four 5432")
    click_on "Saved"
    expect(page).to have_css("#people-saved", text: "Cannot save:")
    expect(page).to have_button("Save", disabled: true)

    find(".ql-saved-item", text: "Ops Smiths").click
    expect(page).to have_field("Search Text", with: "smith team:ops")
  end

  it "searches on Enter in the box and applies the panel on Enter in a field" do
    visit "/"
    fill_in "Search Text", with: "smith"
    find_field("Search Text").send_keys(:enter)
    expect(page).to have_css(".ql-chip", text: "Name contains smith")
    expect(page).to have_no_css(".ql-options")

    click_on "Options"
    fill_in "Team", with: "ops"
    find_field("Team").send_keys(:enter)
    expect(page).to have_no_css(".ql-options")
    expect(page).to have_field("Search Text", with: "smith team:ops")
  end

  it "keeps the last results while the words are too short, and finds a facet value" do
    visit "/"
    fill_in "Search Text", with: "smith"
    expect(page).to have_css(".ql-group", minimum: 1)

    fill_in "Search Text", with: "sm"
    expect(page).to have_css(".ql-hint", text: "Type at least 3 letters")
    expect(page).to have_css(".ql-chip", text: "Name contains smith")

    fill_in "Search Text", with: "smith"
    expect(page).to have_no_css(".ql-hint", visible: true)
    expect(page).to have_css(".ql-facet-value", text: "billing", visible: true)
    expect(page).to have_no_css(".ql-facet-value", text: "claims", visible: true)
    find(".ql-facet-find").fill_in(with: "cla")
    expect(page).to have_css(".ql-facet-value", text: "claims", visible: true)
  end
end
