# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workshop exceptions", :aggregate_failures do
  around do |example|
    previous_store = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = previous_store
  end

  let(:date) { SOLDNTime.today + 3.days }
  let(:venue) { create(:venue) }
  let(:organiser) { create(:organiser) }
  let(:attrs) do
    { title: "Visiting Blues workshop", url: "https://example.org/blues", venue_id: venue.id,
      class_organiser_id: organiser.id, date: date.iso8601, last_verified_at: Time.current,
      source_notes: "PRIVATE primary source checked", workshop_exception_reason: "PRIVATE visiting teachers" }
  end

  def sign_in
    get verify_login_path(token: EditorLoginToken.generate(create(:editor)))
  end

  def create_workshop
    sign_in
    post workshops_path, params: { workshop_form: attrs }
    Event.find_by!(url: attrs[:url])
  end

  it "requires editorial authentication" do
    get new_workshop_path
    expect(response).to redirect_to(login_path)
    expect { post workshops_path, params: { workshop_form: attrs } }.not_to change(Event, :count)
  end

  it "offers a dedicated form and an editor entry point" do
    sign_in
    get events_path
    expect(response.body).to include("New workshop exception")
    get new_workshop_path
    expect(response.body).to include("Approve a workshop exception", "workshop_form[date]")
  end

  # This checks the complete editorial lifecycle of a single dated approval.
  # rubocop:disable RSpec/ExampleLength
  it "creates, lists, edits and cancels a dated workshop without publishing private notes" do
    event = create_workshop
    expect(response).to redirect_to(event_path(event))
    expect(event).to have_attributes(frequency: 0, has_social: false, has_class: true,
                                     first_date: date, last_date: date)
    expect(Event.workshops_on_date(date).map(&:id)).to eq([event.id])
    expect(Event.workshops_on_date(date + 7.days)).to be_empty
    expect(Event.listing_classes).not_to include(event)
    expect(Event.socials_on_date(date)).not_to include(event)
    get root_path
    expect(response.body).to include("Workshops", "Visiting Blues workshop")
    expect(response.parsed_body.at_css("#workshops").text).to include("Visiting Blues workshop")
    expect(response.body).not_to include("PRIVATE")
    get event_path(event)
    expect(response.body).to include("Workshop")
    get edit_event_path(event)
    expect(response).to redirect_to(edit_workshop_path(event))
    patch event_path(event), params: { event: { frequency: 1 } }
    expect(response).to redirect_to(edit_workshop_path(event))
    get edit_workshop_path(event)
    expect(response.body).to include("Edit workshop exception", date.iso8601, "PRIVATE visiting teachers")
    patch workshop_path(event), params: { workshop_form: attrs.merge(cancelled: true) }
    expect(response).to redirect_to(event_path(event))
    expect(event.reload.event_instances.count).to eq(1)
    expect(event.event_instances.first).to be_cancelled
    get root_path
    expect(response.body).to include("Cancelled", "Visiting Blues workshop")

    allow(SOLDNTime).to receive(:today).and_return(date + 1.day)
    get root_path
    expect(response.body).to include("Cancelled", "Visiting Blues workshop")

    allow(SOLDNTime).to receive(:today).and_return(date + 3.days)
    get root_path
    expect(response.body).to include("Cancelled", "Visiting Blues workshop")

    allow(SOLDNTime).to receive(:today).and_return(date + 4.days)
    get root_path
    expect(response.body).not_to include("Visiting Blues workshop")
  end

  # rubocop:enable RSpec/ExampleLength

  it "rejects incomplete approval and returns the form" do
    sign_in
    post workshops_path, params: { workshop_form: attrs.except(:workshop_exception_reason) }
    expect(response).to have_http_status(:unprocessable_content)
    expect(Event.count).to eq(0)
    post workshops_path, params: { workshop_form: attrs.except(:last_verified_at) }
    expect(response).to have_http_status(:unprocessable_content)
    expect(Event.count).to eq(0)
  end

  it "rolls back invalid edits without losing the approved date" do
    event = create_workshop
    patch workshop_path(event), params: { workshop_form: attrs.merge(title: "", date: (date + 1.day).iso8601) }
    expect(response).to have_http_status(:unprocessable_content)
    expect(event.reload.title).to eq("Visiting Blues workshop")
    expect(event.event_instances.pluck(:date)).to eq([date])
  end

  it "requires an editor to alter an approved date" do
    event = create_workshop
    event.update!(organiser_token: "workshop-token")
    get edit_external_event_path("workshop-token")
    expect(response).to have_http_status(:not_found)
    patch external_event_path("workshop-token"), params: { event: { dates: (date + 7.days).iso8601 } }
    expect(response).to have_http_status(:not_found)
    expect(event.reload.event_instances.pluck(:date)).to eq([date])
  end

  it "does not use workshop routes for ordinary events or other cities" do
    sign_in
    get edit_workshop_path(create(:event))
    expect(response).to have_http_status(:not_found)
    stub_const("CITY", City.build_london)
    get new_workshop_path
    expect(response).to have_http_status(:not_found)
  end
end
