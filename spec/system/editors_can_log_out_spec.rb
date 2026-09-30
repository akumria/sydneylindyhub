# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Editor logout" do
  it "ends the editor session" do
    role = create(:editor, name: "Al Minns")
    allow(EditorLoginToken).to receive(:role_for).with("valid-token").and_return(role)

    visit verify_login_path(token: "valid-token")
    click_on "Al Minns"
    click_on "Log out"

    expect(page).to have_button("Email me a sign-in link")
    visit "/events"
    expect(page).to have_button("Email me a sign-in link")
  end
end
