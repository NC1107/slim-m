<!-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 -->
# Deployment sizing

How much processor and memory a slim-m server needs, measured rather than estimated.

Everything here comes from a capacity study run on 2026-09-15 against server 0.63.0.
The harness is `scripts/loadtest.py`, which holds real sessions open over real websockets and reads the server's own `/metrics` across each run.
Runs were constrained with systemd resource limits, which is how Docker expresses the same caps, so the numbers transfer to a container deployment.

## The short answer

Two cores and 256 MB carries any deployment that fits inside the connection limit.

One core does not, and that is the single most important finding here.
It is not a matter of degree: at one core the server is throttled into second-scale delays while using only three quarters of the core it was given.

## Hard limits

| Limit | Value | How it fails |
| --- | --- | --- |
| Simultaneous websocket connections | 1024 | Refused cleanly. Existing connections are unaffected. |
| Memory per connection | 144 KB | Linear from 100 to 1024 connections. |
| Memory at the connection limit | 166 MB | Connections cannot push the server past this, because the count cap stops them first. |
| Delivery throughput | about 26,000 per second | Latency degrades before the processor saturates. |

A "delivery" is one message arriving at one connection.
One message sent into a channel a hundred people are watching is a hundred deliveries.
Deliveries, not messages, are the unit that decides how much processor a deployment needs.

## Processor

Measured at a constant offered load of roughly 26,000 deliveries per second, varying only the quota.

| Quota | Cores actually used | Median delivery | Verdict |
| --- | --- | --- | --- |
| 1 core | 0.75 | 1,305 ms | Unusable |
| 1.5 cores | 0.85 | 541 ms | Poor |
| 2 cores | 0.95 | 44 ms | Good |
| 4 cores | 1.30 | 21 ms | Better |
| 8 cores | 1.48 | 12 ms | Marginal gain |

Two things in that table are worth understanding before choosing a number.

The server never uses more than about 1.5 cores no matter how many it is offered.
Going from four cores to eight changed throughput by 0.2 percent while halving the median delay, so past two cores you are buying responsiveness rather than capacity.

At one core it used only three quarters of what it had while delivering a 1.3 second median.
It was not short of work to do, it was being stopped: a quota is enforced by freezing the process for part of every scheduling window, so a tight quota collapses latency while average utilisation still looks comfortable.
That is why one core is a cliff rather than a slope, and why the first table row says unusable rather than slow.

## Memory

Memory is generous and predictable.
The floor is about 17 MB, each connection adds 144 KB, and the connection cap means the total can never exceed about 166 MB from connection load.

A server given less than it needs is **killed by the kernel rather than degraded**.
Holding connections at the cap, a 160 MB ceiling survived and a 144 MB ceiling was killed within a second, having accepted several hundred connections it could not afford.
The memory admission guard added after this study refuses new connections when headroom runs short, but the reserve it keeps is part of what a deployment must budget for.

| Connections | Recommended memory |
| --- | --- |
| 100 | 96 MB |
| 250 | 128 MB |
| 500 | 160 MB |
| 1024 | 256 MB |

Those figures include the 64 MB the admission guard holds back.

## How many people that supports

The load a deployment generates grows with the square of its population when everybody watches the same channel, because each additional person both sends more and receives more.
So the answer depends on how chatty people are, and the table below states that assumption rather than hiding it.

| Cores | 1 message per person per minute | 2 per minute | 5 per minute |
| --- | --- | --- | --- |
| 1 | 774 | 547 | 346 |
| 2 | 1024 (connection limit) | 883 | 558 |
| 4 | 1024 (connection limit) | 883 | 558 |

Assumptions behind those numbers, all of which make them pessimistic:

- One connection per person. Somebody with a phone and a laptop counts twice.
- Everyone watching the same busy channel, which is the worst case for fan-out.
- Sustained activity, not a peak. Real deployments are idle most of the time.

Splitting people across channels helps considerably but not completely.
Measured at the same message rate, sending into a channel only the sender could see cost 2.6 percent of a core where a public channel cost 9.4 percent.
That is roughly a fourfold difference per connection, and the reason it is not larger is that the hub broadcasts every event to every connection, each of which evaluates whether it may see it.
A connection that cannot see a channel still pays to work that out.

## Compose presets

Set these under the server service in `docker-compose.yml`.

A friend group, up to about fifty people:

```yaml
deploy:
  resources:
    limits:
      cpus: '2.0'
      memory: 256M
    reservations:
      memory: 64M
```

A community up to the connection limit:

```yaml
deploy:
  resources:
    limits:
      cpus: '2.0'
      memory: 512M
    reservations:
      memory: 128M
```

Two cores appears in both because it is the first quota that behaves, not because the smaller deployment needs the capacity.
Memory is the dial worth turning with size.
Raising the processor limit above two buys lower latency and no extra capacity.

## What is measured and what is not

Measured directly, and re-measured in a second pass that reproduced every result: the connection limit, memory per connection, the memory ceiling where it is killed, latency against processor quota from a quarter core to eight, delivery throughput, and the difference visibility makes.

Two identical runs differed by 23 percent at the median and 43 percent at the tail.
Every difference reported here is far larger than that.
Differences smaller than it are not reported as findings.

Not measured, and not covered by any number above:

- Voice and video, which run through a separate media server with its own limits.
- Reconnect storms, which is how services usually fall over.
- Sustained multi-hour runs, so slow leaks would not have appeared.
- Attachment uploads, which have their own limit class and their own disk path.
- Anything above 1024 connections, which the server refuses.

## Reproducing this

```bash
cargo build --release --bin slimm-server
scripts/loadtest.py --base-url http://127.0.0.1:8080 --users 100 --per-account 3 \
  --senders 25 --messages 10 --workers 8
```

Watch the server's own processor time in the output before believing a latency number.
When the two disagree, the harness is the one that is wrong, and during this study it was wrong four times.
