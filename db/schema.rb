# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_24_130000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "decisions", force: :cascade do |t|
    t.string "action", null: false
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.bigint "moderator_id", null: false
    t.datetime "performed_at"
    t.bigint "registration_request_id", null: false
    t.jsonb "response", default: {}, null: false
    t.string "state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["moderator_id"], name: "index_decisions_on_moderator_id"
    t.index ["registration_request_id"], name: "index_decisions_on_registration_request_id"
    t.index ["registration_request_id"], name: "index_decisions_on_registration_request_unique", unique: true
    t.check_constraint "action::text = ANY (ARRAY['approve'::text, 'reject'::text])", name: "decisions_action_check"
    t.check_constraint "state::text = ANY (ARRAY['pending'::text, 'succeeded'::text, 'failed'::text, 'conflict'::text])", name: "decisions_state_check"
  end

  create_table "domain_policies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "domain", null: false
    t.boolean "include_subdomains", default: false, null: false
    t.string "kind", null: false
    t.text "reason"
    t.string "source", default: "manual", null: false
    t.datetime "updated_at", null: false
    t.index ["domain"], name: "index_domain_policies_on_domain", unique: true
    t.index ["kind"], name: "index_domain_policies_on_kind"
    t.check_constraint "kind::text = ANY (ARRAY['allowed'::text, 'blocked'::text])", name: "domain_policies_kind_check"
    t.check_constraint "source::text = ANY (ARRAY['manual'::text, 'iftas_dni'::text])", name: "domain_policies_source_check"
  end

  create_table "email_templates", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.bigint "instance_id", null: false
    t.string "name", null: false
    t.string "subject"
    t.datetime "updated_at", null: false
    t.index ["instance_id", "name"], name: "index_email_templates_on_instance_id_and_name", unique: true
  end

  create_table "flags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "details", default: {}, null: false
    t.bigint "registration_request_id", null: false
    t.string "rule", null: false
    t.integer "severity", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["registration_request_id", "rule"], name: "index_flags_on_registration_request_and_rule", unique: true
    t.index ["registration_request_id"], name: "index_flags_on_registration_request_id"
    t.index ["rule"], name: "index_flags_on_rule"
  end

  create_table "instances", force: :cascade do |t|
    t.string "accepted_terms_digest"
    t.datetime "access_ended_at"
    t.string "client_id"
    t.text "client_secret"
    t.integer "consecutive_verification_failures", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "domain", null: false
    t.text "last_sync_error"
    t.datetime "last_sync_error_at"
    t.datetime "last_synced_at"
    t.string "mastodon_version"
    t.jsonb "oauth_metadata", default: {}, null: false
    t.string "redirect_uri"
    t.string "scopes"
    t.boolean "signals_approved", default: false, null: false
    t.boolean "signals_opted_in", default: false, null: false
    t.string "status", default: "unverified", null: false
    t.bigint "sync_moderator_id"
    t.datetime "terms_grace_until"
    t.datetime "terms_stale_since"
    t.string "title"
    t.datetime "updated_at", null: false
    t.datetime "verification_checked_at"
    t.string "verification_detail"
    t.datetime "verified_at"
    t.index ["domain"], name: "index_instances_on_domain", unique: true
    t.index ["status"], name: "index_instances_on_status"
    t.index ["sync_moderator_id"], name: "index_instances_on_sync_moderator_id"
    t.check_constraint "status::text = ANY (ARRAY['unverified'::text, 'verified'::text, 'terms_outdated'::text, 'revoked'::text, 'blocked'::text])", name: "instances_status_check"
  end

  create_table "keyword_rules", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.boolean "enabled", default: true, null: false
    t.bigint "instance_id", null: false
    t.string "match_type", default: "word", null: false
    t.string "pattern", null: false
    t.integer "severity", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["enabled"], name: "index_keyword_rules_on_enabled"
    t.index ["instance_id"], name: "index_keyword_rules_on_instance_id"
    t.check_constraint "match_type::text = ANY (ARRAY['substring'::text, 'word'::text, 'regex'::text])", name: "keyword_rules_match_type_check"
  end

  create_table "moderators", force: :cascade do |t|
    t.text "access_token"
    t.string "avatar_url"
    t.datetime "consented_at"
    t.string "consented_privacy_digest"
    t.datetime "created_at", null: false
    t.string "display_name"
    t.bigint "instance_id", null: false
    t.datetime "last_authenticated_at"
    t.string "mastodon_account_id", null: false
    t.string "profile_url"
    t.string "role_name"
    t.datetime "token_invalidated_at"
    t.string "token_scopes"
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.index ["instance_id", "mastodon_account_id"], name: "index_moderators_on_instance_id_and_mastodon_account_id", unique: true
    t.index ["instance_id"], name: "index_moderators_on_instance_id"
  end

  create_table "notes", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "edited_at"
    t.bigint "moderator_id", null: false
    t.bigint "parent_id"
    t.bigint "registration_request_id", null: false
    t.datetime "updated_at", null: false
    t.index ["moderator_id"], name: "index_notes_on_moderator_id"
    t.index ["parent_id"], name: "index_notes_on_parent_id"
    t.index ["registration_request_id", "created_at"], name: "index_notes_on_registration_request_id_and_created_at"
    t.index ["registration_request_id"], name: "index_notes_on_registration_request_id"
  end

  create_table "purged_registrations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "instance_id", null: false
    t.string "mastodon_account_id", null: false
    t.index ["instance_id", "mastodon_account_id"], name: "index_purged_registrations_on_instance_and_account", unique: true
  end

  create_table "registration_requests", force: :cascade do |t|
    t.string "account_url"
    t.boolean "approved", default: false, null: false
    t.string "avatar_url"
    t.text "bio"
    t.string "canonical_email_hash"
    t.datetime "claimed_at"
    t.bigint "claimed_by_id"
    t.boolean "confirmed", default: false, null: false
    t.datetime "created_at", null: false
    t.string "created_by_application_id"
    t.string "display_name"
    t.string "email"
    t.string "email_domain"
    t.integer "flags_count", default: 0, null: false
    t.bigint "instance_id", null: false
    t.bigint "invite_fingerprint"
    t.text "invite_request"
    t.inet "ip"
    t.integer "ip_asn"
    t.string "ip_asn_org"
    t.string "ip_country"
    t.datetime "ip_enriched_at"
    t.virtual "ip_group", type: :inet, as: "\nCASE\n    WHEN (ip IS NULL) THEN NULL::inet\n    WHEN (family(ip) = 6) THEN (network(set_masklen(ip, 64)))::inet\n    ELSE ip\nEND", stored: true
    t.string "ip_relay"
    t.datetime "last_seen_in_queue_at"
    t.string "locale"
    t.string "mastodon_account_id", null: false
    t.integer "max_flag_severity", default: 0, null: false
    t.integer "notes_count", default: 0, null: false
    t.jsonb "raw", default: {}, null: false
    t.datetime "resolved_at"
    t.datetime "signed_up_at", null: false
    t.string "signup_shape"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.index ["canonical_email_hash"], name: "index_registration_requests_on_canonical_email_hash"
    t.index ["claimed_by_id"], name: "index_registration_requests_on_claimed_by_id"
    t.index ["email_domain"], name: "index_registration_requests_on_email_domain"
    t.index ["instance_id", "ip_asn"], name: "index_registration_requests_on_instance_id_and_ip_asn"
    t.index ["instance_id", "mastodon_account_id"], name: "index_registration_requests_on_instance_and_account", unique: true
    t.index ["instance_id", "status", "signed_up_at"], name: "index_registration_requests_on_instance_status_signed_up"
    t.index ["instance_id"], name: "index_registration_requests_on_instance_id"
    t.index ["ip"], name: "index_registration_requests_on_ip"
    t.index ["ip_group"], name: "index_registration_requests_on_ip_group"
    t.index ["signup_shape", "signed_up_at"], name: "index_registration_requests_on_signup_shape_and_signed_up_at"
    t.check_constraint "ip_relay::text = ANY (ARRAY['private_relay'::text, 'tor'::text])", name: "registration_requests_ip_relay_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'approved_elsewhere'::text, 'rejected_elsewhere'::text, 'expired'::text])", name: "registration_requests_status_check"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "last_active_at", null: false
    t.bigint "moderator_id", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["moderator_id"], name: "index_sessions_on_moderator_id"
  end

  create_table "sync_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.bigint "instance_id", null: false
    t.integer "pages_fetched", default: 0, null: false
    t.integer "records_created", default: 0, null: false
    t.integer "records_resolved", default: 0, null: false
    t.integer "records_seen", default: 0, null: false
    t.integer "records_updated", default: 0, null: false
    t.datetime "started_at", null: false
    t.string "status", default: "running", null: false
    t.datetime "updated_at", null: false
    t.index ["instance_id", "started_at"], name: "index_sync_runs_on_instance_id_and_started_at"
    t.index ["instance_id"], name: "index_sync_runs_on_instance_id"
    t.check_constraint "status::text = ANY (ARRAY['running'::text, 'succeeded'::text, 'failed'::text])", name: "sync_runs_status_check"
  end

  create_table "votes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "moderator_id", null: false
    t.bigint "registration_request_id", null: false
    t.datetime "updated_at", null: false
    t.string "vote", null: false
    t.index ["moderator_id"], name: "index_votes_on_moderator_id"
    t.index ["registration_request_id", "moderator_id"], name: "index_votes_on_registration_request_id_and_moderator_id", unique: true
    t.check_constraint "vote::text = ANY (ARRAY['approve'::text, 'reject'::text])", name: "votes_vote_check"
  end

  add_foreign_key "decisions", "moderators"
  add_foreign_key "decisions", "registration_requests"
  add_foreign_key "email_templates", "instances"
  add_foreign_key "flags", "registration_requests"
  add_foreign_key "instances", "moderators", column: "sync_moderator_id"
  add_foreign_key "keyword_rules", "instances"
  add_foreign_key "moderators", "instances"
  add_foreign_key "notes", "moderators"
  add_foreign_key "notes", "notes", column: "parent_id"
  add_foreign_key "notes", "registration_requests"
  add_foreign_key "purged_registrations", "instances"
  add_foreign_key "registration_requests", "instances"
  add_foreign_key "registration_requests", "moderators", column: "claimed_by_id"
  add_foreign_key "sessions", "moderators"
  add_foreign_key "sync_runs", "instances"
  add_foreign_key "votes", "moderators"
  add_foreign_key "votes", "registration_requests"
end
