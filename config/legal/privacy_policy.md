# Privacy Policy

> **THIS IS EXAMPLE TEXT.** It ships with Waterhole as a starting point and is not
> legal advice. It describes what the software actually does, which should make it
> a useful skeleton — but the legal framing, your lawful basis, and your retention
> periods are yours to determine.
> Run `bin/rails waterhole:legal:install` to copy it into your legal directory
> (`WATERHOLE_LEGAL_DIR`, default `storage/legal`) and edit it there; this
> template is only shown until you do.

## Who is responsible

**[OPERATOR NAME]**, **[POSTAL ADDRESS]**, **[EMAIL]**.

Note the split of responsibility: for the personal data of **applicants**, the
Mastodon instance is the controller and this deployment processes that data on the
instance's behalf. For the personal data of **moderators** signing in here, this
deployment is the controller.

## What this service processes, and why

### About people applying to join a Mastodon instance

Mirrored from the instance's own admin API so moderators can review them:

- username, display name, profile note, avatar URL and profile URL
- **email address**, and the domain part separately
- the most recent **IP address** Mastodon recorded for the account, the country
  and network operator (ASN) derived from it, and whether the address belongs to
  Apple's iCloud Private Relay or to a Tor relay
- the free-text reason given for wanting to join
- locale, signup time, whether the address was confirmed, and whether the
  account was created through an app rather than the website
- the moderators' notes and decision about the application

This is used for one purpose: deciding whether to admit the applicant. It is not
used for advertising, profiling beyond that decision, or automated rejection.
Automated flags are advisory only — a person makes every decision.

### Cross-instance signals

If an instance opts in and we approve it, this service can tell its moderators
that the same email address or the same signup network is currently in use on
**another** instance that has also opted in. This is reciprocal: an instance only
sees this if it also contributes. Email addresses are compared as keyed hashes,
never shared in the clear, and only the other instance's **domain** is shown — never its applicants'
details. In the same way, a fingerprint of the reason for joining (never the
text) is compared to find near-identical reasons, and the email domain, the
pattern of the username and the language are compared to find bursts of similar
signups from different networks. These fingerprints and patterns are deleted
together with the application they are derived from (see Retention).

Matches include applicants who have already been approved, until their data is
deleted (see Retention). Because each instance's server supplies its own
registrations, an administrator of a participating instance could misuse the
signal to find out whether a particular address or network has been used to join
another participating instance. Participating instances agree in our terms not to
do this, and we end the participation of any that does, but we cannot technically
prevent it.

### About moderators

Mastodon account identifier, username, display name, avatar, role, when you last
signed in, an access token issued by your own instance, session records
including IP address and browser user agent, and when you consented to which
version of this policy.

Moderators are asked for their consent right after first signing in, and again
whenever this privacy policy changes; until they agree they can only read the
legal pages. Declining signs them out and deletes their record, or anonymises
it where their notes or decisions are part of an instance's records.

## Cookies

This service sets up to three cookies, all first-party. The first two are needed
for it to work; the third is set only if you ask for it. None is used for
tracking, analytics or advertising, and nothing is stored in your browser's
local storage.

| Cookie | What it holds | How long it lasts |
|---|---|---|
| `_waterhole_session` | Protection against forged form submissions, one-off status messages, and short-lived sign-in state (a random value that ties the Mastodon login back to your browser, and the page to return to afterwards) | Until you close your browser |
| `session_id` | A reference to your sign-in, set only once you have signed in | Until you sign out, after 24 hours without use, or at the latest 7 days after signing in |
| `recent_instances` | Only if you tick "Remember this instance in this browser" when signing in: the domains of up to five Mastodon instances you chose to remember, so the sign-in page can offer them again | 90 days after your last sign-in. Signing in without the tick, or **Forget** on the sign-in page, removes an entry sooner |

## Retention

An application is deleted **[N] days** after it is decided (here or directly in
Mastodon) or withdrawn, with everything
about it: the applicant's data, the moderators' notes, the automated flags and
the decision. Only the Mastodon account's numeric ID is kept, while the
instance uses this service, so that the application is not imported again
while the instance still lists it as pending. The instance's moderators can also purge an application earlier, with
the same effect. An application that is never decided is kept for as long as it
is pending on its instance. If the instance stops using this service and does
not return within 14 days, all its applications are deleted, together with the
stored account IDs.

A moderator's record is kept while their instance uses this service. If the
instance stops (its authorisation is removed or blocked, or it does not accept
changed terms in time) and does not return within 14 days, the record is
deleted along with the instance's applications.

Server logs are deleted after **[N] days**.

## Storage and security

Access tokens and email addresses are encrypted at rest. Access requires both DNS
authorisation from the instance administrator and a Mastodon login with
permission to manage users on that instance.

## Your rights

Depending on where you live you may have rights of access, rectification, erasure,
restriction, portability and objection. **Applicants should contact their Mastodon
instance first** — it is the controller for that data. For moderator data, or if
your instance directs you here, contact us at **[EMAIL]**.

The moderators of the instance an applicant applied to can also purge the
application from this service at any time: it is then deleted straight away, as
described under Retention, and not imported again. That does not change
anything on the Mastodon instance itself.

You also have the right to lodge a complaint with a data protection supervisory
authority: **[YOUR SUPERVISORY AUTHORITY]**.

## Third parties

IP geolocation uses public-domain datasets downloaded from a third party, and we
also download Apple's list of iCloud Private Relay addresses and the Tor
Project's list of Tor relays. Your IP address is **not** sent to any of them —
every lookup happens on our own server.

> **Optional — keep this paragraph only if you set `SENTRY_DSN`; otherwise
> delete it together with this note.**

When something in this service breaks, a technical error report is sent to
**[ERROR TRACKER, e.g. "Sentry (Functional Software, Inc.)" or "our own
GlitchTip server"]** so that we can fix it. A report says where in the software
the error happened and which page or background task was running. It is
configured not to include applicants' email addresses, IP addresses, reasons for
joining or moderators' notes, and it does not identify the signed-in moderator;
cookies, form contents and search terms are removed before it is sent. Reports
are kept for **[N] days**.

_Last updated: [DATE]_
