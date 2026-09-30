# frozen_string_literal: true

class UsersController < CmsBaseController
  layout "cms"

  def show
    render locals: { user: current_user }
  end

  def destroy
    Role.find_by!(email: current_user.email).destroy!
    login_session.log_out!
    flash.notice = "Your editor login has been disabled"

    redirect_to login_path
  end
end
