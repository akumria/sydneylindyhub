# frozen_string_literal: true

class SessionsController < ApplicationController
  layout "website"
  include CityHelper

  def new; end

  def create
    role = Role.find_by(email: params[:email].to_s.strip.downcase)

    if role && development_login_bypass?
      log_in(role)
      return redirect_to return_to_session.path(fallback: events_path)
    end

    send_login_link(role)
    redirect_to login_path, notice: t("sessions.link_sent")
  end

  def verify
    role = EditorLoginToken.role_for(params[:token])
    return redirect_to(login_path, alert: t("sessions.invalid_link")) unless role

    log_in(role)
    redirect_to return_to_session.path(fallback: events_path)
  end

  def destroy
    login_session.log_out!
    redirect_to action: :new
  end

  private

  def log_in(role)
    login_session.log_in!(email: role.email, name: role.name)
  end

  def send_login_link(role)
    LoginMailer.magic_link(role).deliver_now if role
  end

  def development_login_bypass?
    Rails.env.development? && ENV.fetch("SKIP_LOGIN", "false") == "true"
  end

  def login_session
    LoginSession.new(request)
  end

  def return_to_session
    ReturnToSession.new(request)
  end
end
