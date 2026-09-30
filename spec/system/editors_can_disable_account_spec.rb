# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Editor account" do
  it "lets an editor remove their approved login" do
    editor = create(:editor, email: "editor@example.com", name: "Sydney Editor")
    skip_login("/account", email: editor.email, name: editor.name)

    click_on "Disable my login"

    expect(page).to have_text("Your editor login has been disabled")
    expect(page).to have_button("Email me a sign-in link")
    expect(Role.find_by(email: editor.email)).to be_nil
  end
end
