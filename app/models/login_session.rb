# frozen_string_literal: true

class LoginSession
  def initialize(request, role_finder: Role, logger: Rails.logger)
    @request = request
    @role_finder = role_finder
    @logger = logger
  end

  def log_in!(email:, name:)
    request.reset_session # calling reset_session prevents "session fixation" attacks
    request.session[:user] = {
      "email" => email,
      "name" => name
    }
    logger.info("Logged in as #{email}")
  end

  def log_out!
    email = user.email
    request.reset_session
    logger.info("Logged out as #{email}")
  end

  def user
    if request.session[:user].present?
      User.new(request.session[:user], role_finder:)
    else
      Guest.new
    end
  end

  private

  attr_reader :request, :role_finder, :logger

  class User
    def initialize(user, role_finder:)
      @user = user
      @role_finder = role_finder
    end

    def logged_in?
      role.present?
    end

    def name
      user.fetch("name")
    end

    def name_with_role
      if admin?
        "#{name} (Admin)"
      else
        name
      end
    end

    def admin?
      !!role&.admin?
    end

    def email
      user.fetch("email")
    end

    def auth_id
      email
    end

    private

    attr_reader :user, :role_finder

    def role
      role_finder.find_by(email: email)
    end
  end

  class Guest
    def logged_in?
      false
    end

    def name
      "Guest"
    end

    def name_with_role
      name
    end

    def admin?
      false
    end

    def email
      "NO EMAIL"
    end

    def auth_id
      email
    end
  end
end
