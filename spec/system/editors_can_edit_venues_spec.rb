# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Editors can edit venues", :vcr do
  it "with valid data" do
    create(
      :venue,
      name: "The Old Harbour Club",
      address: "99 George Street\nSydney",
      postcode: "2000",
      area: "Sydney",
      website: "https://example.com/old-harbour-club",
      lat: -33.8640,
      lng: 151.2060
    )

    skip_login(id: 12345678901234567, name: "Al Minns")

    click_on "Venues"

    click_on "Edit", match: :first

    fill_in "Name", with: "The Harbour Club"
    fill_in "Address", with: "100 George Street\nSydney"
    fill_in "Postcode", with: "2000"
    fill_in "Latitude", with: "-33.8634"
    fill_in "Longitude", with: "151.2065"
    fill_in "Area", with: "Sydney"
    fill_in "Website", with: "https://example.com/harbour-club"
    Timecop.freeze(Time.zone.local(2000, 1, 2, 23, 17, 16)) do
      click_on "Update"
    end

    expect(page).to have_text("Name: The Harbour Club")
    expect(page).to have_text("Address: 100 George Street\r Sydney")
    expect(page).to have_text("Postcode: 2000")
    expect(page).to have_text("Area: Sydney")
    expect(page).to have_text("Website: https://example.com/harbour-club")
    expect(page).to have_text("Coordinates: [ -33.8634, 151.2065 ]")

    expect(page).to have_text("Last updated by Al Minns (12345678901234567) on Sunday 2nd January 2000 at 23:17:16")
  end

  context "with invalid data" do
    it "shows an error" do
      venue = create(
        :venue,
        name: "The Old Harbour Club",
        address: "99 George Street\nSydney",
        postcode: "2000",
        area: "Sydney",
        website: "https://example.com/old-harbour-club",
        lat: -33.8640,
        lng: 151.2060
      )

      skip_login("/venues/#{venue.to_param}/edit")

      fill_in "Name", with: ""
      fill_in "Address", with: ""
      fill_in "Postcode", with: ""
      fill_in "Latitude", with: ""
      fill_in "Longitude", with: ""
      fill_in "Area", with: ""
      fill_in "Website", with: "www.the100club.co.uk"

      click_on "Update"

      expect(page).to have_text("4 errors prevented this record from being saved")
        .and have_text("Address can't be blank")
        .and have_text("Area can't be blank")
        .and have_text("Name can't be blank")
        .and have_text("Website is invalid")

      fill_in "Name", with: "The 100 Club"
      fill_in "Address", with: "100 George Street\nSydney"
      fill_in "Area", with: "Sydney"
      fill_in "Website", with: "https://www.the100club.co.uk/"
      fill_in "Latitude", with: "-33.8634"
      fill_in "Longitude", with: "151.2065"

      click_on "Update"

      expect(page).to have_text("Name: The 100 Club")
        .and have_text("Address: 100 George Street\r Sydney")
        .and have_text("Area: Sydney")
        .and have_text("Website: https://www.the100club.co.uk/")
        .and have_text("Coordinates: [ -33.8634, 151.2065 ]")
    end
  end
end
