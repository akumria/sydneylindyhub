# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Static publication", :aggregate_failures do
  around do |example|
    ClimateControl.modify(STATIC_PUBLISH_ENABLED: "true") { example.run }
  end

  def sign_in
    role = create(:editor)
    get verify_login_path(token: EditorLoginToken.generate(role))
  end

  it "requires editor authentication" do
    post publication_path
    expect(response).to redirect_to(login_path)
    expect(StaticPublication.count).to eq(0)
  end

  it "queues a publication and displays its status" do
    sign_in
    post publication_path
    follow_redirect!
    expect(response.body).to include("Queued", "queued or running")
    expect(StaticPublication.last.requested_by).to eq(session[:user]["email"])
  end

  it "does not allow a second active publication" do
    sign_in
    post publication_path
    expect { post publication_path }.not_to change(StaticPublication, :count)
    expect(flash[:alert]).to include("already queued or running")
  end

  it "does not queue when disabled" do
    sign_in
    ClimateControl.modify(STATIC_PUBLISH_ENABLED: "false") do
      post publication_path
      follow_redirect!
    end
    expect(StaticPublication.count).to eq(0)
    expect(response.body).to include("not configured")
  end

  it "shows a publish button and warns about unconfirmed failures" do
    sign_in
    StaticPublication.create!(requested_by: "editor@example.com", status: "failed")
    get publication_path
    expect(response.body).to include("Publish website", "could not be confirmed")
  end

  it "shows the initial publishing page" do
    sign_in
    get publication_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Publish website")
  end
end
