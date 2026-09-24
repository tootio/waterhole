class EmailTemplatesController < ApplicationController
  before_action :set_email_template, only: %i[edit update destroy]

  throttle to: 20, within: 1.minute, name: "email_template_change",
    by: -> { current_instance.id }, only: %i[create update destroy]

  def index
    @email_templates = current_instance.email_templates.order(:name)
  end

  def new
    @email_template = current_instance.email_templates.new
  end

  def create
    @email_template = current_instance.email_templates.new(email_template_params)

    if @email_template.save
      redirect_to email_templates_path, notice: "Template added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @email_template.update(email_template_params)
      redirect_to email_templates_path, notice: "Template updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @email_template.destroy!
    redirect_to email_templates_path, notice: "Template removed."
  end

  private

  def set_email_template
    @email_template = current_instance.email_templates.find(params[:id])
  end

  def email_template_params
    params.expect(email_template: [ :name, :subject, :body, :enabled ])
  end
end
