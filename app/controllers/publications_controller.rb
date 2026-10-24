# frozen_string_literal: true

class PublicationsController < CmsBaseController
  def show
    @publication = StaticPublication.order(id: :desc).first
    refresh_github if @publication && StaticPublication.github? && GithubPublication.configured?
    @active = StaticPublication.active.exists?
  end

  def create
    unless StaticPublication.enabled?
      redirect_to publication_path, alert: t("publications.disabled")
      return
    end

    publication = StaticPublication.create!(requested_by: current_user.email)
    dispatch_github(publication) if StaticPublication.github?
    redirect_to publication_path, notice: t("publications.queued") unless performed?
  rescue ActiveRecord::RecordNotUnique
    redirect_to publication_path, alert: t("publications.busy")
  end

  private

  def dispatch_github(publication)
    GithubPublication.new.dispatch(publication)
  rescue GithubPublication::Rejected
    publication.update!(status: "failed", finished_at: Time.current)
    redirect_to publication_path, alert: t("publications.rejected")
  rescue GithubPublication::Error
    redirect_to publication_path, alert: t("publications.unconfirmed")
  end

  def refresh_github
    @run_url = GithubPublication.new.refresh(@publication)
  rescue GithubPublication::Error
    @status_error = t("publications.unconfirmed")
  end
end
