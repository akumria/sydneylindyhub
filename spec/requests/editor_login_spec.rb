# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Editor login" do
  around do |example|
    ClimateControl.modify(CANONICAL_HOST: "sydneylindyhub.com", EDITORIAL_HOST: "edit.sydneylindyhub.com") do
      example.run
    end
  end

  it "emails a magic link to an approved editor", :aggregate_failures do
    role = create(:editor, email: "editor@example.com")

    expect do
      post login_path, params: { email: role.email }
    end.to change(ActionMailer::Base.deliveries, :count).by(1)

    expect(response).to redirect_to(login_path)
    expect(flash[:notice]).to include("If that email is approved")
    expect(ActionMailer::Base.deliveries.last.to).to eq([role.email])
    expect(ActionMailer::Base.deliveries.last.body.encoded).to include("https://edit.sydneylindyhub.com/")
  end

  it "uses the same response for an unknown address without sending mail", :aggregate_failures do
    expect do
      post login_path, params: { email: "unknown@example.com" }
    end.not_to change(ActionMailer::Base.deliveries, :count)

    expect(response).to redirect_to(login_path)
    expect(flash[:notice]).to include("If that email is approved")
  end

  it "bypasses email delivery only for local development", :aggregate_failures do
    role = create(:editor, email: "editor@example.com", name: "Development Editor")
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))

    ClimateControl.modify(SKIP_LOGIN: "true") do
      post login_path, params: { email: role.email }
    end

    expect(response).to redirect_to(events_path)
    expect(session[:user]).to eq("email" => role.email, "name" => role.name)
  end

  it "signs in with a valid token", :aggregate_failures do
    role = create(:editor, email: "editor@example.com", name: "Sydney Editor")

    get verify_login_path(token: EditorLoginToken.generate(role))

    expect(response).to redirect_to(events_path)
    expect(session[:user]).to eq("email" => role.email, "name" => role.name)
  end

  it "rejects an invalid token", :aggregate_failures do
    get verify_login_path(token: "invalid")

    expect(response).to redirect_to(login_path)
    expect(flash[:alert]).to eq("That sign-in link is invalid or has expired.")
  end
end
