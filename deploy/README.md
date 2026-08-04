# Self-hosting slim-m

A minimal production stack for a friend group.
It wires up the slim-m server, Caddy for automatic TLS, LiveKit for voice and screen share, and an optional Litestream sidecar that streams the SQLite database to S3-compatible storage.

## Prerequisites

- A host (a VPS, or a box at home with a public IP) with Docker and the Docker Compose plugin installed.
- Two DNS records pointed at that host: one for the slim-m API domain, one for LiveKit's signaling domain.
- Ports 80 and 443 (TCP and UDP) reachable from the internet, plus the UDP media range you choose in `.env`.

## One-command walkthrough

```bash
git clone https://github.com/NC1107/slim-m.git
cd slim-m
cp deploy/.env.example .env
# edit .env: both domains, ACME_EMAIL, and a real LIVEKIT_API_KEY/SECRET
docker compose up -d
```

The server image tracks the rolling `latest` tag.
Set `SLIMM_VERSION` in `.env` to a published release (see the [releases page](https://github.com/NC1107/slim-m/releases)) to freeze it on a specific version instead.
If you do pin, bump it on every upgrade rather than leaving it: a stale tag is a server that predates every security fix since, and this file itself once shipped pinned to the very first release.
`SLIMM_VERSION` is read from `.env`, so pinning never means editing `docker-compose.yml`.

`LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` have no defaults, on purpose.
They authorize minting a room token, so a placeholder default would be a publicly known credential on a publicly reachable SFU.
Compose refuses to start until both are set and tells you which one is missing; generate a pair with `docker run --rm livekit/livekit-server:v1.10.1 generate-keys`.

Check it:

```bash
curl https://<SLIMM_API_DOMAIN>/healthz   # -> ok
docker compose ps                         # server and caddy should show healthy
```

## Backups (optional)

Litestream is off by default because it needs a real S3-compatible bucket.
To turn it on: fill in the `LITESTREAM_*` values in `.env`, uncomment `COMPOSE_PROFILES=litestream`, then re-run `docker compose up -d`.

**Litestream replicates only the SQLite database file. Attachment and avatar bytes are not covered.**
They live on disk beside the database, at `SLIMM_ATTACHMENTS_DIR` (default `/data/media` inside the container, so the same `slimm_data` volume as the database), specifically because multi-megabyte blobs in the SQLite file would bloat what Litestream streams for no benefit.
That means restoring from a Litestream replica brings back every message and its attachment references, but not the attachment files themselves; a client would render broken images and failed downloads for anything uploaded since the last time `/data/media` was backed up some other way.
If attachments matter to your deployment, back up the whole `slimm_data` volume yourself (a periodic `docker run --rm -v slimm_data:/data -v $(pwd):/backup alpine tar czf /backup/slimm-data-$(date +%F).tgz -C / data`, restic, or your platform's volume-snapshot feature), not just the database.

## Browser clients (`SLIMM_CORS_ALLOWED_ORIGINS`)

Empty by default, and that default is the safe one: with nothing set there is no CORS layer at all, and a browser on any other origin is refused.
The desktop and mobile clients send no `Origin` header, so this setting has no effect on them whatsoever.
You only need it if you serve a web build of the client from a different origin than the API.

```
SLIMM_CORS_ALLOWED_ORIGINS=https://app.example.com,http://localhost:8099
```

Deny-by-default matters more here than it looks, and not only for a server on the public internet.
A self-host usually sits on a network your own browser can route to and the rest of the internet cannot.
An open policy would hand every page you happen to visit the ability to drive that deployment from inside the perimeter its network position was protecting it with, using your browser as the way in.
That is why `*` is refused outright rather than accepted as a shortcut, and why the list is exact origins you write down.

Malformed entries stop the server at startup with the offending value named, rather than turning into a `blocked by CORS policy` line in a browser console days later.
An origin is `scheme://host[:port]` and nothing more, so a path, a query, a fragment, or embedded credentials are all rejected.
A default port, an uppercase host, a unicode host, and a bare trailing slash are all normalized to the form a browser actually sends, so those still match.

Credentials are never allowed, whatever you set.
slim-m authenticates with an `Authorization: Bearer` header the client attaches itself; browsers never send that automatically the way they send cookies.
Credentialed mode would therefore buy nothing here while adding the ambient authority that turns one mistaken origin into a full account takeover, so the server does not send `Access-Control-Allow-Credentials` at all.

Only `authorization` and `content-type` are accepted as request headers, and only the methods the API actually serves (`GET`, `POST`, `PUT`, `PATCH`, `DELETE`) are allowed.
Preflights are answered by the server itself and cached for ten minutes.

## Voice and screen share

`SLIMM_LIVEKIT_URL`, `SLIMM_LIVEKIT_API_KEY` and `SLIMM_LIVEKIT_API_SECRET` are what tell the server it has an SFU at all.
Without them the server answers 501 for every voice request, which is a supported way to run text-only but is not what somebody who brought up the `livekit` service is asking for.
The URL must be the one clients reach from outside, not the compose-internal service name, because the server hands it to the client alongside a join token.

LiveKit's signaling channel is fronted by Caddy on the `LIVEKIT_DOMAIN` you set, so no extra port beyond 443 is needed for a client to negotiate a call.
It is plain HTTPS/WSS, so Caddy reverse-proxies it exactly like any other HTTP traffic and passes the `Upgrade: websocket` handshake through with no special configuration.

Carrying the call is separate, and needs four things open at your router or cloud firewall on top of that.
Media never goes through Caddy or port 443 at all: LiveKit's TURN and TURN/TLS listeners bind their own ports directly on the host, and the UDP media range is published straight through to the container.
Caddy is not, and cannot be, in that path.
Docker publishes all four; a firewall in front of Docker does not know that.

| From `.env` | Default | Carries |
| --- | --- | --- |
| `LIVEKIT_UDP_PORT_START`-`LIVEKIT_UDP_PORT_END` | 50000-50100/udp | Call media. The path almost every call actually takes. |
| `LIVEKIT_TURN_RELAY_PORT_START`-`LIVEKIT_TURN_RELAY_PORT_END` | 30000-30100/udp | TURN's relay ports, a separate block from the media range. |
| `LIVEKIT_TURN_UDP_PORT` | 3478/udp | STUN and TURN itself, for clients whose NAT will not do better. |
| `LIVEKIT_TCP_PORT` | 7881/tcp | The fallback for a client that cannot send UDP at all. |

Leaving the TURN relay range closed is worse than having no TURN at all: LiveKit keeps advertising relay candidates and every one of them times out, so calls that would have failed fast instead hang.

The relay range is narrowed from LiveKit's own 30000-40000 default, which nobody publishes ten thousand ports for.
Left at the default the effect is TURN that looks enabled in the config and connects nothing.

Move any of these if something on the host already holds the port.
A UniFi controller publishes 3478 for its own STUN, and a second SFU on the same box already holds 7881.
Both sides of each mapping follow the variable, so changing it in `.env` is enough.

The `livekit` service carries no Docker `HEALTHCHECK`, unlike the server and Caddy.
The image ships no verified shell or HTTP client to probe with, so it relies on `restart: unless-stopped` plus ordinary log monitoring instead.

### TURN/TLS, and why it is not on 443

TURN/TLS (`turns:`) is off by default, and when you turn it on it does not go on 443.
Caddy already owns 443 for the API and LiveKit signaling domains, and TURN is not an HTTP protocol Caddy can multiplex onto that port alongside them.
LiveKit's TURN/TLS listener gets 5349 instead, the IANA default for `turns:`.

The consequence is worth stating plainly: a client on a network so locked down that only outbound 443 is allowed cannot use TURN/TLS to escape it, because it is not on 443 here.
That is an accepted trade-off for a friend-group deployment, and plain UDP TURN on 3478 already covers ordinary home and NAT networks.

Its listener also needs a certificate of its own.
It cannot borrow Caddy's, because Caddy's ACME storage layout is not a stable path to mount from.

To enable it: point a third DNS name at this host (`turn.example.com`, say), obtain a certificate and key for it by whatever means you like, mount them into the `livekit` container, uncomment the `- "5349:5349"` port line in `docker-compose.yml`, and add these four keys under the existing `turn:` block in `LIVEKIT_CONFIG`:

```yaml
          domain: turn.example.com
          tls_port: 5349
          cert_file: /etc/livekit/turn.crt
          key_file: /etc/livekit/turn.key
```

If LiveKit exits at startup with `could not resolve external IP`, that is your host's DNS, not your firewall.
Ubuntu and Fedora run systemd-resolved, whose `/etc/resolv.conf` names a `127.0.0.53` stub that does not exist inside a container, and LiveKit needs one hostname resolved to discover the address peers must reach it on.
The `dns:` block on the livekit service is there for this; point it at whichever resolvers you prefer.
Nothing else in the container uses them: that one STUN lookup is all they serve, and its target is a public Google host either way.

## Custom emoji, and importing them in bulk

**slim-m ships no emoji of its own.**
There is no bundled set, no default pack, and nothing is fetched from anywhere at startup or on first run.
A deployment has exactly the emoji somebody put into it, which means the images are yours to supply and yours to be sure you have the rights to distribute to everyone on the deployment.
Most emoji packs you can download are somebody's copyrighted artwork under a licence worth reading first.

Anyone with MANAGE_SERVER can upload them one at a time from the client.
For seeding a new deployment, the server binary takes a whole directory at once:

```bash
docker compose run --rm -v /path/to/your/emoji:/emoji:ro server import-emoji /emoji
```

That reuses the `server` service's environment and its `slimm_data` volume, so it writes to the same database and the same media directory the running server reads.
It is safe to run while the server is up.
The container runs as an unprivileged user, so the directory you mount has to be world-readable, and mounting it `:ro` is enough because the import only ever reads from it.
Running the binary directly instead of through compose works the same way: it reads the same `SLIMM_DATABASE_PATH` and `SLIMM_ATTACHMENTS_DIR` the server does, so point those at the deployment and give it a directory.

Each file becomes one emoji named after its filename, minus the extension, lowercased, with spaces and dashes turned into underscores and anything else dropped.
`Big Smile.png` becomes `:big_smile:`, and so does `big-smile.png`.
That is the same normalisation an upload through the client goes through, so a bulk-imported emoji is indistinguishable from an uploaded one afterwards.

What is left has to fit in 32 characters, and that is worth checking a downloaded pack against before you point the import at it, because long descriptive filenames are the norm in one.
A name that does not fit is refused rather than shortened: a truncated name is one that two files can quietly end up sharing, and the report telling you about it is better than an emoji you did not name appearing under a name you did not choose.

You get a line per file and a summary:

```
!!!.png           refused, the filename leaves no usable name (a-z, 0-9 or _)
Big Smile.png     imported as :big_smile:
README.txt        refused, not a supported image, whatever the extension claims
nested            refused, not a regular file, and the import does not recurse
party-parrot.gif  imported as :party_parrot:
2 imported, 0 unchanged, 0 skipped, 3 refused, 0 over the limit
```

Running it again over the same directory reports the two as unchanged and does nothing else:

```
!!!.png           refused, the filename leaves no usable name (a-z, 0-9 or _)
Big Smile.png     unchanged, :big_smile: already has these bytes
README.txt        refused, not a supported image, whatever the extension claims
nested            refused, not a regular file, and the import does not recurse
party-parrot.gif  unchanged, :party_parrot: already has these bytes
0 imported, 2 unchanged, 0 skipped, 3 refused, 0 over the limit
```

What it accepts, and what it will not:

- PNG, JPEG, GIF and WebP, decided by reading the first few bytes of each file rather than by trusting the extension.
  A zip named `.png` is refused, and so is an SVG, which is a script that renders rather than an image.
  A PDF is refused here too, even though the server does accept one as a message attachment: an emoji is drawn inline at the size of a word, and that is a narrower thing than a file somebody downloads.
- One megabyte per file, which is already generous for something drawn at about the size of a line of text.
- Thirty-two characters of name, counted after normalising and without the extension.
  `blobcat_happy_extremely_pleased_indeed.png` is refused with `the name is 38 characters, over the 32 character limit`, which is a different line from the one a filename with no usable characters at all gets, so you are never sent looking for an illegal character that is not there.
- Five hundred emoji per deployment.
  Every client fetches the whole list to render `:shortcode:` at all, so this is a real ceiling and not a soft one.
- The directory you name and no deeper.
  A subdirectory is reported rather than descended into, because a nested pack is how two files quietly end up claiming the same name.

Re-running the same import is safe and is the expected way to add to a pack later.
A file whose emoji already exists with those exact bytes is reported as unchanged and nothing happens.
A file whose name is already taken by a *different* image is skipped, and the image your members already recognise stays exactly as it is.
Changing an emoji's picture is deliberately an explicit act: delete it in the client, then import again.

If the deployment hits the five hundred limit part way through, the emoji imported up to that point stay imported, and every file that did not fit is listed as over the limit.
A file that did not fit leaves nothing behind: both the limit and the name are checked before the image is stored, so a refused file writes no bytes into the media directory and no row into the database, and there is nothing to clean up afterwards.

The command exits non-zero if any file in the directory did not end up as an emoji, so a script notices, and the report above it says which files and why.
A pack folder with a `README` or a `LICENSE` in it will therefore exit non-zero on a run that was otherwise fine, with those files named as the reason.

## Storage, and the ceiling you should set

Attachments and custom emoji are files under the media volume, not rows in the database.
There is no per-account quota and there is no ceiling unless you set one:

```
SLIMM_MAX_TOTAL_ATTACHMENT_BYTES=2147483648
```

That is 2 GiB, which the `.env.example` in this directory ships with.

**A single attachment has its own, separate ceiling, and the default is too small for video.**
The message-attachment allowlist covers images, PDF, mp4 and webm video, mpeg/ogg/wav audio, zip and gzip archives, and plain text (source files, logs, csv, json, yaml, sniffed by content rather than by extension - see `crates/slimm-server/src/media/content_type.rs` for the exact rules).
`SLIMM_ATTACHMENT_MAX_BYTES` bounds any one of those, and it defaults to 10 MiB, which most real video and a lot of real audio is already over.
Raise it if you want people to attach video or long recordings:

```
SLIMM_ATTACHMENT_MAX_BYTES=104857600
```

That is 100 MiB, an example rather than a recommendation - the same "the right number is your disk, not a guess" reasoning as the total ceiling above applies here too, and this one also bounds how much memory one upload buffers in the server process before it is written to disk.
Raising it does not raise `SLIMM_MAX_TOTAL_ATTACHMENT_BYTES`; the two are independent, and a single-upload ceiling large enough for video with no deployment-wide ceiling at all is a real, if unusual, choice.
Set it from the volume you actually gave the stack, leaving room for the database to grow.

The default is no ceiling, and that is deliberate rather than an oversight: the right number is the size of your disk, and a guess would either refuse a legitimate upload on a large volume or do nothing on a small one.
Leaving it unset is a supported choice if you would rather watch the volume yourself.

Two things worth knowing about what it does and does not cover.

**It counts attachments and custom emoji, not avatars.**
An avatar is one file per account, overwritten in place, so the total is already bounded by your member count times 2 MiB and no upload can grow it.
They are not rows in the table the ceiling sums, so counting them would need a second mechanism to bound something already bounded.

**Past the ceiling an upload is refused with 507, not 413.**
That distinction exists so a screenshot tells you whose problem it is: a 413 means the sender's file is over the per-upload limit and they should send a smaller one, and a 507 means the volume is full and it is yours.
The refusal happens before any bytes are written, so nothing is left behind to clean up.

An uploaded file that never gets attached to a message is reclaimed by a sweep that runs hourly, two hours after the upload.
A deployment sitting at its ceiling therefore recovers as that sweep works through the backlog, and refuses uploads until it does.

Related, and stated elsewhere in this file but worth repeating here: **Litestream replicates the database only.**
A restore gives you messages and their attachment references, not these bytes. Back the media volume up separately.

## Rate limiting, and the one setting you need behind a proxy

The server limits requests per caller with token buckets.
An authenticated caller is keyed by account, so a limit follows them across devices and networks rather than being shed by reconnecting.
Everyone else is keyed by address.

That second half is where a reverse proxy causes a problem, and it is worth understanding before you decide.
The server sees the TCP peer, and behind a proxy the peer is always the proxy, so without any configuration **every unauthenticated caller in the world shares one bucket**.
The password bucket is a burst of five and then one attempt every six seconds, so a single client making one request a second keeps it permanently empty and nobody can sign in.
It also fires by accident when several of you sign in together.

The fix is to tell the server how many proxies you run:

```
SLIMM_TRUST_PROXY_HOPS=1
```

Behind the Caddy in this directory that is `1`.
Add one for each additional proxy in front of it - a CDN in front of Caddy makes it `2`.

**Leave it unset if the server is exposed directly**, and do not guess.
The two ways of getting it wrong are not equally bad.
Too low keys every unauthenticated caller together, which is the problem above: annoying, and self-inflicted only.
Too high reads an address the *client* chose, so any caller can mint themselves an unlimited number of buckets, and the limit stops existing.
That is why the default is zero and why this is not inferred: nothing in a request distinguishes a proxy you run from one you do not.

The header is read from the right, which is what makes a correct setting safe.
A proxy appends the address it saw, so the rightmost entry is the one your own proxy wrote; a caller can prepend as much as they like and never reach it.

Caddy has no built-in per-IP rate limiting, so this cannot be solved in the Caddyfile instead - that needs a third-party module and a custom Caddy build.

## Moderating a member, and what "remove from Space" really is

Two tools sit between deleting a message and deleting an account.

A **timeout** takes away sending, reacting, attaching files, and joining or speaking in voice, for a set time.
It takes away nothing else: the member keeps reading, and keeps seeing every channel they could see before.
It lapses on its own at its deadline, with nothing needing to run on time for that to happen, and a moderator can lift or shorten it early.
Issuing one needs the KICK_MEMBERS permission.

A **removal** ends their access to the deployment.
Every live session is revoked, signing in stops working, invites they had handed out are revoked, and they stop appearing in the member list.
Issuing one needs BAN_MEMBERS, and it is reversible: readmitting them restores the right to sign in, though their devices all sign in again rather than resuming.

Two things about a removal are worth being plain about, because the word undersells one and oversells the other.

**It is a ban in behaviour, not a kick.**
There is no membership row to delete here - one deployment is one community, and holding an account *is* membership - so a removal has to be a standing refusal recorded against the account.
A version that only closed today's sessions would be undone by signing in again.

**It does not stop the same person making a new account** on a Space whose join policy is `open`.
Nothing short of identity verification would, that is well outside what a self-hosted friend group can or should do, and the honest answer is to say so rather than imply a guarantee that is not there.
If that matters to you, set the join policy to `invite`.

Everything a removed member wrote stays exactly where it is, still attributed to them.
Removing somebody is not a reason to rewrite a conversation other people were part of.
Anonymizing their content is what *deleting an account* does, which is a separate and heavier act that the account's own holder chooses.

Neither tool can be used on yourself, nor on a member whose permissions your own do not already include - so holding KICK_MEMBERS is not a way to silence the administrators one at a time.
The last remaining administrator cannot be removed at all.

## Files

- `docker-compose.yml` (repository root) - the stack itself.
- `deploy/Caddyfile` - routes the API domain and LiveKit's signaling domain through Caddy, terminating TLS.
- `deploy/.env.example` - every variable the compose file reads, with safe defaults and comments.

## Upgrading

The server image is `${SLIMM_VERSION:-latest}` in `docker-compose.yml`, so upgrading or pinning it is bumping `SLIMM_VERSION` in `.env`, never editing `docker-compose.yml` itself (see the note above).
Caddy, LiveKit, and Litestream are hardcoded tags in `docker-compose.yml`; bump those directly and run `docker compose up -d` again.
Newer patches are at hub.docker.com for Caddy and Litestream and at github.com/livekit/livekit/releases for LiveKit.
The named volumes (`slimm_data`, `caddy_data`, `caddy_config`) are untouched by an image swap.

Litestream is deliberately held on the 0.3.x line rather than 0.5.x.
0.5 replaced the replica format (WAL segments became LTX), and this example targets the longer-documented, more stable 0.3 config and CLI surface.
Moving to 0.5 is a replica-format migration, not a tag bump.
