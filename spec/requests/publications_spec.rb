# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Static publication", :aggregate_failures do
  around do |example|
    ClimateControl.modify(STATIC_PUBLISH_ENABLED: "true", STATIC_PUBLISH_BACKEND: nil, GITHUB_ACTIONS_TOKEN: nil) do
      example.run
    end
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

  context "with GitHub publication" do
    let(:client) { instance_double(GithubPublication, dispatch: nil, refresh: nil) }

    before do
      allow(GithubPublication).to receive(:new).and_return(client)
      sign_in
    end

    around do |example|
      ClimateControl.modify(STATIC_PUBLISH_ENABLED: "true", STATIC_PUBLISH_BACKEND: "github",
                            GITHUB_ACTIONS_TOKEN: "test-token") { example.run }
    end

    it "dispatches an editor request and links the matched run on refresh" do
      post publication_path
      publication = StaticPublication.last
      expect(client).to have_received(:dispatch).with(publication)
      allow(client).to receive(:refresh).with(publication).and_return("https://github.com/akumria/sydneylindyhub/actions/runs/42")
      follow_redirect!
      expect(response.body).to include("View publication run", "actions/runs/42")
    end

    it "disables publishing without its token" do
      ClimateControl.modify(GITHUB_ACTIONS_TOKEN: nil) { post publication_path }
      expect(StaticPublication.count).to eq(0)
      expect(client).not_to have_received(:dispatch)
    end

    it "marks a rejected dispatch failed so corrected access can be retried" do
      allow(client).to receive(:dispatch).and_raise(GithubPublication::Rejected)
      post publication_path
      expect(StaticPublication.last.status).to eq("failed")
      expect(flash[:alert]).to include("rejected")
    end

    it "keeps an ambiguous dispatch active and blocks a duplicate request" do
      allow(client).to receive(:dispatch).and_raise(GithubPublication::Error)
      post publication_path
      expect(StaticPublication.last.status).to eq("queued")
      expect(flash[:alert]).to include("before retrying")
      expect { post publication_path }.not_to change(StaticPublication, :count)
      expect(client).to have_received(:dispatch).once
    end

    it "shows refresh errors without changing status or redispatching" do
      StaticPublication.create!(requested_by: "editor@example.com")
      allow(client).to receive(:refresh).and_raise(GithubPublication::Error)
      get publication_path
      expect(response.body).to include("could not confirm", "queued or running")
      expect(client).not_to have_received(:dispatch)
    end
  end
end
