# frozen_string_literal: true

class ShotsController < ApplicationController
  include Pagy::Backend

  before_action :authenticate_user!, except: %i[show compare chart]
  before_action :load_shot, only: %i[edit update destroy]

  FILTER_PARAMS = %i[bean_brand bean_type].freeze

  def index
    load_shots_with_pagy
  end

  def chart
    @no_header = true
    @shot = Shot.active.find(params[:id])
    @chart = ShotChart.new(@shot)
  end

  def edit
    shots = current_user.shots.active
    %i[grinder_model bean_brand bean_type].each do |method|
      unique_values = Rails.cache.fetch("#{shots.cache_key_with_version}/#{method}") { shots.distinct.pluck(method).compact }
      instance_variable_set("@#{method.to_s.pluralize}", unique_values.sort_by(&:downcase))
    end
  end

  def show
    @shot = Shot.active.find(params[:id])
    @shot.ensure_screenshot
    @chart = ShotChart.new(@shot, skin: current_user&.skin)
    return if current_user.nil? || @shot.user != current_user

    @compare_shots = current_user.shots.active.where.not(id: @shot.id).by_start_time.pluck(:id, :profile_title, :start_time)
  rescue ActiveRecord::RecordNotFound
    redirect_to :root
  end

  def compare
    @shot = Shot.active.find(params[:id])
    @comparison = Shot.active.find(params[:comparison])
    @chart = ShotChartCompare.new(@shot, @comparison, skin: current_user&.skin)
  end

  def create
    files = Array(params[:files])
    files.each do |file|
      Shot.from_file(current_user, file)&.save
    end

    flash[:notice] = "#{'Shot'.pluralize(files.count)} successfully uploaded."
    if params.key?(:drag)
      head :ok
    else
      redirect_to({action: :index})
    end
  end

  def update
    @shot.update(shot_params)
    flash[:notice] = "Shot successfully updated."
    redirect_to action: :show
  end

  def destroy
    @shot.soft_delete!

    respond_to do |format|
      format.turbo_stream do
        if request.referer.ends_with?("shots/#{@shot.id}")
          flash[:notice] = "Shot successfully deleted."
          redirect_to action: :index
        else
          load_shots_with_pagy
          if @shots.any?
            render turbo_stream: turbo_stream.replace("shot-list", partial: "shots/list", locals: {shots: @shots, pagy: @pagy, url: shots_path(extra_params)})
          else
            redirect_to action: :index
          end
        end
      end
      format.html do
        flash[:notice] = "Shot successfully deleted."
        redirect_to action: :index
      end
    end
  end

  private

  def load_shot
    @shot = current_user.shots.active.find(params[:id])
  end

  def shot_params
    params.require(:shot).permit(:profile_title, :bean_weight, *Shot::EXTRA_DATA_METHODS)
  end

  def load_shots_with_pagy
    @shots = current_user.shots.active.by_start_time
    FILTER_PARAMS.each do |filter|
      next if params[filter].blank?

      @shots = @shots.where(filter => params[filter]) if params[filter]
    end
    @pagy, @shots = pagy(@shots)
  end

  def extra_params
    FILTER_PARAMS.filter_map do |filter|
      next if params[filter].blank?

      [filter, params[filter]]
    end.to_h
  end
end
