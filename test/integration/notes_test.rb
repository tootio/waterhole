require "test_helper"

class NotesTest < ActionDispatch::IntegrationTest
  setup do
    @moderator = moderators(:avery)
    @subject = registration_requests(:claimed_alpha)
    sign_in_as @moderator
  end

  test "posting a note records it against the moderator" do
    assert_difference -> { @subject.notes.count }, 1 do
      post registration_request_notes_path(@subject), params: { note: { body: "Seems fine to me." } }
    end

    note = @subject.notes.order(:created_at).last
    assert_equal @moderator, note.moderator
    assert_equal "Seems fine to me.", note.body
  end

  test "the counter cache tracks notes" do
    post registration_request_notes_path(@subject), params: { note: { body: "One" } }

    assert_equal @subject.notes.count, @subject.reload.notes_count
  end

  test "a reply attaches to its root" do
    root = notes(:root)

    post registration_request_notes_path(@subject),
      params: { note: { body: "Agreed.", parent_id: root.id } }

    assert_equal root, @subject.notes.order(:created_at).last.parent
  end

  # Threading is capped at one level on purpose: deeper nesting buys nothing for
  # triage and costs recursive rendering and recursive broadcast targets.
  test "a reply to a reply is refused" do
    root = notes(:root)
    reply = @subject.notes.create!(moderator: @moderator, parent: root, body: "First reply")

    nested = @subject.notes.new(moderator: @moderator, parent: reply, body: "Too deep")

    refute nested.valid?
    assert_match(/cannot reply to a reply/, nested.errors.full_messages.to_sentence)
  end

  test "an empty note is refused" do
    assert_no_difference -> { @subject.notes.count } do
      post registration_request_notes_path(@subject), params: { note: { body: "  " } }
    end
  end

  test "a moderator can edit and delete their own note" do
    note = @subject.notes.create!(moderator: @moderator, body: "Mine")

    patch note_path(note), params: { note: { body: "Edited" } }
    assert_equal "Edited", note.reload.body
    assert note.edited?

    assert_difference -> { @subject.notes.count }, -1 do
      delete note_path(note)
    end
  end

  test "a moderator cannot edit someone else's note" do
    note = notes(:root) # blake's

    patch note_path(note), params: { note: { body: "Hijacked" } }

    assert_equal "Looks genuine to me. Anyone object?", note.reload.body
    assert_match(/only edit your own/, flash[:alert])
  end

  test "a moderator cannot touch a note on another instance's request" do
    other = registration_requests(:other_instance)
    foreign = other.notes.create!(moderator: moderators(:casey), body: "Not yours")

    delete note_path(foreign)

    assert_response :not_found
    assert Note.exists?(foreign.id)
  end

  # parent_id comes from the form, and a reply renders under its parent: a
  # parent on another request would plant the reply in that thread instead.
  test "a reply cannot attach to a note on another instance's request" do
    foreign = registration_requests(:other_instance).notes.create!(moderator: moderators(:casey), body: "Theirs")

    assert_no_difference -> { Note.count } do
      post registration_request_notes_path(@subject),
        params: { note: { body: "Planted", parent_id: foreign.id } }
    end
    assert_empty foreign.replies.reload
  end

  test "a reply cannot attach to a note on another request of the same instance" do
    elsewhere = registration_requests(:pending_alpha).notes.create!(moderator: @moderator, body: "Other thread")

    note = @subject.notes.new(moderator: @moderator, parent: elsewhere, body: "Wrong thread")

    refute note.valid?
    assert_match(/same request/, note.errors.full_messages.to_sentence)
  end
end
