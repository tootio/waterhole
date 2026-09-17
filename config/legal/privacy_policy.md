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

- username, display name, profile note and avatar URL
- **email address**, and the domain part separately
- **IP address** used at signup, and the country and network operator (ASN)
  derived from it
- the free-text reason given for wanting to join
- locale, signup time, and whether the address was confirmed

This is used for one purpose: deciding whether to admit the applicant. It is not
used for advertising, profiling beyond that decision, or automated rejection.
Automated flags are advisory only — a person makes every decision.

### Cross-instance signals

If an instance opts in, this service can tell its moderators that the same email
address or the same signup network is currently in use on **another** instance that
has also opted in. This is reciprocal: an instance only sees this if it also
contributes. Email addresses are compared as salted hashes, never shared in the
clear, and only the other instance's **domain** is shown — never its applicants'
details.

Matches include applicants who have already been approved, until their data is
erased (see Retention). Because each instance's server supplies its own
registrations, an administrator of a participating instance could misuse the
signal to find out whether a particular address or network has been used to join
another participating instance. Participating instances agree in our terms not to
do this, and we end the participation of any that does, but we cannot technically
prevent it.

### About moderators

Mastodon account identifier, username, display name, avatar, an access token
issued by your own instance, and session records including IP address and browser
user agent.

## Cookies

This service sets three cookies, all first-party and all needed for it to work.
None is used for tracking, analytics or advertising, and nothing is stored in your
browser's local storage.

| Cookie | What it holds | How long it lasts |
|---|---|---|
| `_waterhole_session` | Protection against forged form submissions, one-off status messages, and short-lived sign-in state (a random value that ties the Mastodon login back to your browser, and the page to return to afterwards) | Until you close your browser |
| `session_id` | A reference to your sign-in, set only once you have signed in | Until you sign out; the cookie itself is set to expire after 20 years |
| `recent_instances` | The domains of up to five Mastodon instances you have signed in to from this browser, so the sign-in page can offer them again | 90 days after your last sign-in. Use **Forget** on the sign-in page to remove an entry sooner |

All three are signed or encrypted so they cannot be tampered with, are unreadable
to scripts on the page, and are only sent back to this service.

## Retention

Applicant data is erased **[N] days** after a request is decided: email address,
IP address and derived location, the stated reason and profile text are cleared,
while the record of what was decided and by whom is kept as an audit trail.

## Storage and security

Access tokens and email addresses are encrypted at rest. Access requires both DNS
authorisation from the instance administrator and a valid Mastodon login.

## Your rights

Depending on where you live you may have rights of access, rectification, erasure,
restriction, portability and objection. **Applicants should contact their Mastodon
instance first** — it is the controller for that data. For moderator data, or if
your instance directs you here, contact us at **[EMAIL]**.

## Third parties

IP geolocation uses public-domain datasets downloaded from a third party; your IP
address is **not** sent to them — the lookup happens on our own server.

_Last updated: [DATE]_
