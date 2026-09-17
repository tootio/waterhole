# Terms of Service

> **THIS IS EXAMPLE TEXT.** It ships with Waterhole as a starting point and is
> not legal advice. Replace it with terms written for your deployment, then have
> someone qualified review them.
> Run `bin/rails waterhole:legal:install` to copy it into your legal directory
> (`WATERHOLE_LEGAL_DIR`, default `storage/legal`) and edit it there; this
> template is only shown until you do.

## 1. What this service is

This Waterhole deployment is operated by **[OPERATOR NAME]** ("we", "us"). It is
a moderation tool for Mastodon servers. It mirrors the pending registration
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
   fingerprint of each of these documents, so publishing it is an acceptance of
   the versions of these terms and the privacy policy in force at the time.
2. An individual moderator signs in with their own Mastodon account. Only
   accounts allowed to manage users on their instance can sign in, and what they
   may do is determined by that role, not by us.

If one of these documents changes, its fingerprint changes and the record
becomes stale. The
instance administrator must republish it to continue using the service. We will
show the new record and a deadline before access ends.

## 3. Acceptable use

Do not use this service to harass applicants, to build profiles of people beyond
what moderating a registration queue requires, or to share applicants' personal
data with anyone who does not need it to make a moderation decision.

## 4. Informing your applicants

Applicants apply to your instance and never see this service, so we cannot
inform them ourselves. By publishing the DNS record, the instance administrator
agrees to tell the instance's applicants, in the instance's privacy policy, that
their registration data is shared with this service to review it, with a link
to our privacy policy. If the instance shares cross-instance signals, the notice
must cover them too (see the next section). The authorisation page offers a text
to start from.

## 5. Cross-instance signals

Cross-instance signals are off for an instance unless two things are true: its
administrator has added `signals=on` to the instance's DNS record for this
service, and we have approved the instance. Publishing a record with
`signals=on` is acceptance of this section. They are reciprocal: an instance
whose applicants can be matched is also shown matches, and only participating
instances are compared with each other.

**What they disclose.** When an applicant's email address (compared after
normalising it, as a keyed hash) or signup network (the exact IPv4 address, or
the same IPv6 /64) matches a request on another participating instance that is
pending **or already approved**, moderators see that a match exists and the other
instance's domain. They do not see the other applicant's name, address or any
other detail.

The same applies to two patterns that give signup farms away. An applicant's
reason for joining is compared, as a fingerprint computed on this service and
never as text, with the reasons given on other participating instances, and a
nearly identical one is shown as a match. And a burst of signups with the same
email provider, username pattern and language within an hour, each from a
different network, is shown as a burst. Again, only counts and the other
instances' domains are disclosed.

**The risk you accept by opting in.** The signals are computed from what each
instance's Mastodon server reports to this service, and the administrator of a
participating instance controls that server. Such an administrator could create
registrations with email addresses or networks of their choosing, and learn from
the signals whether that address or network belongs to someone who has applied
to, or been admitted by, another participating instance, and which one. This
works for approved accounts until their application is deleted, **[N] days**
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

## 6. Availability

This service is provided as-is, with no guarantee of availability. We may suspend
or withdraw access to any instance, and we may stop operating the service. Your
instance's own Mastodon admin interface remains the authoritative place to manage
registrations.

## 7. Liability

This service is provided free of charge. We are liable without limitation for
damage caused intentionally or through gross negligence, for injury to life,
body or health, and under the **[APPLICABLE PRODUCT LIABILITY LAW]**.
Otherwise our liability is excluded, in particular for damage caused by slight
negligence, for the availability of the service, and for decisions made on the
basis of its flags or signals.

## 8. Changes

We may change these terms. Because acceptance is recorded in DNS, a change
requires each instance administrator to republish their record. Continued use
after republication is acceptance of the changed terms.

## 9. Governing law and jurisdiction

These terms are governed by the law of **[COUNTRY]**, excluding the
UN Convention on Contracts for the International Sale of Goods. If you are a
merchant, a legal entity under public law or a special fund under public law,
the place of jurisdiction for all disputes arising from these terms is
**[CITY, COUNTRY]**. Mandatory consumer protection rules of the country in which a
consumer has their habitual residence remain unaffected.

## 10. Contact

**[OPERATOR NAME]**, **[CONTACT ADDRESS]** — see the [imprint](/imprint).

_Last updated: [DATE]_
