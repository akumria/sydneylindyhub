# frozen_string_literal: true

class PublicationsController < CmsBaseController
  def show
    @publication = StaticPublication.order(id: :desc).first
    @active = StaticPublication.active.exists?
  end

  def create
    unless StaticPublication.enabled?
      redirect_to publication_path, alert: t("publications.disabled")
      return
    end

    StaticPublication.create!(requested_by: current_user.email)
    redirect_to publication_path, notice: t("publications.queued")
  rescue ActiveRecord::RecordNotUnique
    redirect_to publication_path, alert: t("publications.busy")
  end
end
