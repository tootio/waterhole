class NotesController < ApplicationController
  # Each note is broadcast to everyone watching the request.
  throttle to: 30, within: 1.minute, name: "note", by: -> { current_moderator.id }, only: :create

  before_action :set_note, only: %i[edit update destroy]
  before_action :require_author, only: %i[edit update destroy]

  def create
    @registration_request = registration_requests_scope.find(params[:registration_request_id])
    @note = @registration_request.notes.new(note_params.merge(moderator: current_moderator))

    if @note.save
      respond_to do |format|
        # The note reaches everyone (including the author) via the broadcast, so
        # this response only resets the composer -- appending here too would
        # double-insert it for the author.
        format.turbo_stream { render :create }
        format.html { redirect_to registration_request_path(@registration_request) }
      end
    else
      redirect_to registration_request_path(@registration_request),
        alert: @note.errors.full_messages.to_sentence
    end
  end

  def edit; end

  def update
    if @note.update(note_params.merge(edited_at: Time.current))
      redirect_to registration_request_path(@note.registration_request)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @note.destroy!
    redirect_to registration_request_path(@note.registration_request)
  end

  private

  def set_note
    @note = Note.joins(:registration_request)
      .where(registration_requests: { instance_id: current_instance.id })
      .find(params[:id])
  end

  def require_author
    return if @note.moderator_id == current_moderator.id

    redirect_to registration_request_path(@note.registration_request),
      alert: "You can only edit your own notes."
  end

  def note_params = params.expect(note: [ :body, :parent_id ])
end
