# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Editor login" do
  it "lets an approved editor return to the requested editor page" do
    role = create(:editor, email: "al.minns@example.com", name: "Al Minns")
    allow(EditorLoginToken).to receive(:role_for).with("valid-token").and_return(role)

    visit "/events/new"
    expect(page).to have_button("Email me a sign-in link")
    expect(page).to have_no_text("New event")

    fill_in "Email address", with: role.email
    click_on "Email me a sign-in link"
    expect(page).to have_text("If that email is approved")

    visit verify_login_path(token: "valid-token")
    expect(page).to have_text("New event")
    expect(page).to have_text("Al Minns")
  end

  it "uses a neutral response for an address outside the approved list" do
    visit "/events"
    fill_in "Email address", with: "unknown@example.com"
    click_on "Email me a sign-in link"

    expect(page).to have_text("If that email is approved")
    expect(page).to have_no_text("Events")
  end

  it "rejects an invalid or expired link" do
    visit verify_login_path(token: "invalid-token")

    expect(page).to have_text("That sign-in link is invalid or has expired")
    expect(page).to have_button("Email me a sign-in link")
  end
end
