# frozen_string_literal: true

module AuthHelper
  def stub_login(email: Faker::Internet.unique.email, name: Faker::Name.lindy_hop_name, admin: false)
    role = create(admin ? :admin : :editor, email:, name:)
    allow(EditorLoginToken).to receive(:role_for).and_return(role)
    role
  end

  def skip_login(after_login_path = "/events", id: nil, email: nil,
                 name: Faker::Name.lindy_hop_name, admin: false)
    email ||= Faker::Internet.unique.email
    auth_id = id || email
    user = instance_double(LoginSession::User,
                           name:,
                           name_with_role: name,
                           admin?: admin,
                           auth_id:,
                           email:,
                           logged_in?: true)
    login_session = instance_double(LoginSession, "Fake login", user:)
    allow(login_session).to receive(:log_out!)
    allow(LoginSession).to receive(:new).and_return(login_session)
    visit after_login_path
  end
end
