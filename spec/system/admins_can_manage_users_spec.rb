# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin user management" do
  it "lists and adds approved editors by name and email" do
    create(:editor, name: "Existing Editor", email: "existing@example.com")
    skip_login("/admin/users", name: "Site Admin", email: "admin@example.com", admin: true)

    expect(page).to have_text("Existing Editor")
    expect(page).to have_text("existing@example.com")

    fill_in "Name", with: "New Editor"
    fill_in "Email", with: "new.editor@example.com"
    select "Editor", from: "Role"
    click_on "Add user"

    expect(page).to have_text("New Editor")
    expect(Role.find_by(email: "new.editor@example.com")).to be_editor
  end

  it "promotes and removes another editor" do
    editor = create(:editor, name: "Other Editor", email: "other@example.com")
    skip_login("/admin/users", name: "Site Admin", email: "admin@example.com", admin: true)

    within("#user_#{editor.id}") { click_on "Make admin" }
    expect(editor.reload).to be_admin

    within("#user_#{editor.id}") { click_on "Delete" }
    expect(Role.find_by(id: editor.id)).to be_nil
  end

  it "shows validation errors for an invalid email" do
    skip_login("/admin/users", name: "Site Admin", email: "admin@example.com", admin: true)

    fill_in "Name", with: "Invalid Editor"
    fill_in "Email", with: "not-an-email"
    click_on "Add user"

    expect(page).to have_text("Email is invalid")
  end
end
