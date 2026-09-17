# Terms of Service

> **THIS IS EXAMPLE TEXT.** It ships with Waterhole as a starting point and is
> not legal advice. Replace it with terms written for your deployment, then have
> someone qualified review them.
> Run `bin/rails waterhole:legal:install` to copy it into your legal directory
> (`WATERHOLE_LEGAL_DIR`, default `storage/legal`) and edit it there; this
> template is only shown until you do.

## 1. What this service is

This Waterhole deployment is operated by **[OPERATOR NAME]** ("we", "us"). It is a
moderation tool for Mastodon servers. It mirrors the pending registration
requests of participating Mastodon instances so that their moderators can review
them together, and it relays the resulting approve or reject decision back to the
originating instance.

We are not the operator of the Mastodon instances that connect to this service,
and we do not decide who is admitted to them. Those decisions are made by each
instance's own moderators, acting under their own instance's rules.

## 2. Who may use it

Access requires two things:

1. The administrator of a Mastodon instance authorises this deployment by
   publishing a DNS TXT record on the instance's domain. That record includes a
   digest of these documents, so publishing it is an acceptance of the version of
   these terms in force at the time.
2. An individual moderator signs in with their own Mastodon account. What they may
   do is determined by their role on their own instance, not by us.

If these documents change, the digest changes and the record becomes stale. The
instance administrator must republish it to continue using the service. We will
show the new record and a deadline before access ends.

## 3. Acceptable use

Do not use this service to harass applicants, to build profiles of people beyond
what moderating a registration queue requires, or to share applicants' personal
data with anyone who does not need it to make a moderation decision.

## 4. Cross-instance signals

Cross-instance signals are off for an instance unless two things are true: its
administrator has added `signals=on` to the instance's DNS record for this
service, and we have approved the instance. Publishing a record with
`signals=on` is acceptance of this section. They are reciprocal: an instance
whose applicants can be matched is also shown matches, and only participating
instances are compared with each other.

**What they disclose.** When an applicant's email address (compared after
normalising it, as a salted hash) or signup network (the exact IPv4 address, or
the same IPv6 /64) matches a request on another participating instance that is
pending **or already approved**, moderators see that a match exists and the other
instance's domain. They do not see the other applicant's name, address or any
other detail.

**The risk you accept by opting in.** The signal is computed from what each
instance's Mastodon server reports to this service, and the administrator of a
participating instance controls that server. Such an administrator could create
registrations with email addresses or networks of their choosing, and learn from
the signal whether that address or network belongs to someone who has applied
to, or been admitted by, another participating instance, and which one. This
works for approved accounts until their personal data is erased **[N] days**
after the decision (see the privacy policy). This service cannot tell such probing
apart from real signups. Opting in exposes your own applicants and recently
admitted members to every other participating instance in the same way.

**What you agree to.** By publishing `signals=on`, the instance administrator
agrees, for everyone with access to their instance's queue, to:

1. act on signals only while deciding real registration requests on their own
   instance;
2. never create, import or alter registrations to test whether a person is
   present on another instance;
3. never record, export or combine signals to track a person across instances;
4. tell their own users, in their instance's privacy policy, that this matching
   takes place.

We may withdraw our approval, or end an instance's access to this service, if we
believe it has broken these rules. Leaving is always possible: remove
`signals=on` from your record, and matches involving your instance disappear
within about an hour, once we next read it.

## 5. Availability

This service is provided as-is, with no guarantee of availability. We may suspend
or withdraw access to any instance, and we may stop operating the service. Your
instance's own Mastodon admin interface remains the authoritative place to manage
registrations.

## 6. Changes

We may change these terms. Because acceptance is recorded in DNS, a change
requires each instance administrator to republish their record. Continued use
after republication is acceptance of the changed terms.

## 7. Contact

**[OPERATOR NAME]**, **[CONTACT ADDRESS]** — see the [imprint](/imprint).

_Last updated: [DATE]_
