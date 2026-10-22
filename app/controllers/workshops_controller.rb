# frozen_string_literal: true

# Workshop approval is available only through the authenticated editorial interface.
class WorkshopsController < CmsBaseController
  before_action :require_sydney

  def new
    @event = Event.new
    @form = WorkshopForm.new
    render :form
  end

  def edit
    @event = find_workshop
    @form = WorkshopForm.from_event(@event)
    render :form
  end

  def create
    @event = Event.new
    @form = WorkshopForm.new(workshop_params)
    persist
  end

  def update
    @event = find_workshop
    @form = WorkshopForm.new(workshop_params)
    persist
  end

  private

  def persist
    if @form.save(@event)
      redirect_to event_path(@event)
    else
      render :form, status: :unprocessable_content
    end
  end

  def find_workshop
    event = Event.find(params[:id])
    raise ActiveRecord::RecordNotFound unless event.workshop?

    event
  end

  def require_sydney
    raise ActiveRecord::RecordNotFound unless CITY.sydney?
  end

  def workshop_params
    params.require(:workshop_form).permit(WorkshopForm.attribute_names)
  end
end
