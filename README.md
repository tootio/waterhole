# Waterhole

Collaborative moderation for Mastodon registration requests.

Many Waterhole deployments run the same code, and each Mastodon instance picks
the one it trusts by publishing a DNS TXT record. That is why a deployment is
configured entirely through **environment variables**, as Mastodon is: nothing
that differs between deployments lives in the repository. Waterhole does not use
Rails credentials (`config/credentials.yml.enc`), and operators never edit
`config/environments/*`.

## Configuration

Every setting is documented in [`.env.production.sample`](.env.production.sample).

```bash
cp .env.production.sample .env.production
bin/rails waterhole:secrets >> .env.production   # then remove the empty duplicates
```

- **Outside a container**, Rails reads `.env.production` at boot.
- **In a container**, the same variables are passed in (see Deployment below).
  `.env*` files are never baked into the image.
- Variables already set in the environment always win over the file.

A production boot with a required setting missing stops with a list of what is
missing, instead of failing on the first encrypted read.

**Back up the encryption keys with the database.** Without them, stored access
tokens, OAuth client secrets and applicant emails cannot be read.

Operator-owned files live outside the code as well:

| What | Variable | Default |
|---|---|---|
| Terms, privacy policy, imprint | `WATERHOLE_LEGAL_DIR` | `storage/legal` (templates ship in `config/legal`) |
| IP geolocation databases | `WATERHOLE_MMDB_DIR` | `storage/mmdb` |

Start the legal documents from the templates with `bin/rails waterhole:legal:install`.

## Deployment

Waterhole must be served over HTTPS on a stable host: `WATERHOLE_HOST` is
published in every connected instance's DNS record, and the OAuth redirect URI
it registers with Mastodon is `https://WATERHOLE_HOST/…`.

**Docker Compose** is the main path, as it is for Mastodon. It runs the web
server, a separate job worker (syncing, DNS re-verification, IP database
refresh), and PostgreSQL. The steps are at the top of
[`docker-compose.yml`](docker-compose.yml). In short:

```bash
cp .env.production.sample .env.production   # DB_HOST=db, plus the secrets
mkdir legal && cp config/legal/*.md legal/  # then make them yours
docker compose up -d                        # --build until images are published
```

Put a TLS-terminating reverse proxy (nginx, Caddy, …) in front of
`127.0.0.1:3000`. To upgrade, run `docker compose pull && docker compose up -d`.

**Kamal** is an alternative if you already use it:
`cp config/deploy.yml.example config/deploy.yml` (gitignored), then
`bin/kamal deploy --skip-push --version <release>` to run a released image.
kamal-proxy handles TLS.

Either way, **back up the database together with `.env.production`.**

Release images are published to `ghcr.io/tootio/waterhole` for amd64 and arm64.
Pushing a tag such as `v1.2.0` runs CI against it and, if it passes, publishes
`v1.2.0`, `1.2.0`, `1.2` and `latest` with a signed build provenance
attestation. Pre-release tags (`v1.2.0-rc.1`) never move `latest`.

## Development

Ruby is pinned in `mise.toml`.

```bash
mise install
bin/setup
bin/dev
```

`.env.development` and `.env.test` are committed on purpose. They hold throwaway
keys that protect only seed data and fixtures. Put local overrides in
`.env.development.local`, which is gitignored.

Run the full check suite (RuboCop, Brakeman, audits, tests, seeds) with `bin/ci`.

## License

Copyright (C) 2026 Daniel Jagszent

Waterhole is free software: you can redistribute it and/or modify it under the
terms of the GNU Affero General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version. See [LICENSE](LICENSE).

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU Affero General Public License for more details.

**If you run a modified Waterhole**, the AGPL requires you to offer your users
its source code (section 13). The footer's "Source code" link points to the
upstream repository by default; set `WATERHOLE_SOURCE_URL` to your fork.

### Third-party material

- `public/icon.svg` and `public/icon.png` are the mammoth from
  [Noto Emoji](https://github.com/googlefonts/noto-emoji), Copyright 2013
  Google Inc., under the Apache License 2.0
  ([vendor/licenses/Apache-2.0.txt](vendor/licenses/Apache-2.0.txt)).
- IP geolocation data is not part of this repository. It is downloaded at
  runtime from [ip-location-db](https://github.com/sapics/ip-location-db) and is
  in the public domain (PDDL).
