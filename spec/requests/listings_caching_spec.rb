# frozen_string_literal: true

require "rails_helper"

# The listings page is the site's hot path, and it is served from a response
# cache keyed on the most recent audit record, so an editor's change invalidates
# it (see ListingsController#cache_key and ApplicationController#fetch_response).
#
# The test environment sets :null_store (config/environments/test.rb), so the
# cache is inert by default and these examples would pass whether or not the
# caching worked. Each one therefore swaps in a store that really holds values,
# and asserts on what a reader would see rather than on the cache's internals.
#
# Editing a row with update_column skips callbacks, and so records no audit.
# That is what lets an example tell "served from cache" apart from "re-rendered".
RSpec.describe "Listings caching" do
  let(:today) { Time.zone.parse("December 20, 2012 12:00") }

  before do
    # Start from a working store rather than the null store test runs on.
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    # The listings page shows a 14 day window from SOLDNTime.today, so the clock
    # has to be pinned before events will appear on it.
    Timecop.freeze(today)
  end

  after { Timecop.return }

  def create_listed_event(title)
    create(:event, title:, dates: [Date.new(2012, 12, 21)])
  end

  # Change a row without recording an audit, so only a cached response can
  # still be showing the old title. Skipping validations is the point here: this
  # is a raw column write standing in for someone editing the database directly.
  def rename_behind_the_cache(event, title)
    event.update_column(:title, title) # rubocop:disable Rails/SkipsModelValidations
  end

  it "serves a repeat request from the cache", :aggregate_failures do
    create_listed_event("Friday Night Swing")

    get "/"
    expect(response.body).to include("Friday Night Swing")

    rename_behind_the_cache(Event.last, "Renamed Social")

    get "/"

    expect(response.body).to include("Friday Night Swing")
  end

  it "renders again once a new audit is recorded", :aggregate_failures do
    event = create_listed_event("Friday Night Swing")

    get "/"
    expect(response.body).to include("Friday Night Swing")

    rename_behind_the_cache(event, "Renamed Social")
    create(:audit, auditable: event, action: "update")

    get "/"

    expect(response.body).to include("Renamed Social")
  end

  # Any new audit moves Audit.last, so the key changes even though nothing was
  # edited this time. A cache that ignored the audit would keep serving the old
  # listing and dancers would never see the correction.
  it "re-renders when a later audit records an unrelated change", :aggregate_failures do
    event = create_listed_event("Friday Night Swing")

    get "/"
    expect(response.body).to include("Friday Night Swing")

    rename_behind_the_cache(event, "Renamed Social")
    create(:audit, auditable: event, action: "destroy")

    get "/"

    expect(response.body).to include("Renamed Social")
  end

  it "does not build a cache key when there are no audit records" do
    expect(ListingsController.new.send(:cache_key)).to be_nil
  end
end
