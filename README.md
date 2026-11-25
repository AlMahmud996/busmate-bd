# BusMate BD

A bus reservation and live tracking platform for Bangladesh. Passengers search
trips, pick seats on an interactive map, pay (mocked), and share a live
tracking link with relatives. Operators manage routes, buses and trips, and
drivers send GPS positions from a mobile browser.

This is a learning project built to practise microservices, concurrency
control and event-driven design with Spring Boot.

## Status

The design of the booking core is done: requirements (SRS v0.5), diagrams 01 to
11 and the API contract for the User Service. The local infrastructure
(PostgreSQL, Redis, Kafka) runs in Docker. Application code starts with the
User Service and the API gateway.

## Planned architecture

Backend services (Java, Spring Boot): API Gateway, User, Trip, Booking,
Payment, Tracking, Notification. Each service owns its own data.
Infrastructure: PostgreSQL, Redis (seat holds), Kafka (events).
Frontends (React, Vite): passenger app, operator dashboard, driver app.

## Repository layout

- backend/: Spring Boot services
- frontend/: React applications
- infrastructure/: configuration for PostgreSQL, Redis, Kafka and monitoring
- docs/: requirements, architecture, diagrams, API contracts, ADRs
- scripts/: helper scripts
- docker-compose.yml: the local infrastructure

## Running the infrastructure

You need Docker with the Compose plugin, `openssl`, and about 2.5 GB of free
RAM. `psql` is optional and is used by the checks.

First time:

```bash
./scripts/make-env.sh        # creates .env with random passwords
./scripts/infra.sh up        # starts PostgreSQL, Redis and Kafka, creates the topics
./scripts/infra.sh check     # confirms that everything works
```

Every day:

```bash
./scripts/infra.sh status    # container health and memory use
./scripts/infra.sh down      # stop everything, keep the data
./scripts/infra.sh psql user # a psql shell in user_db (also: trip, booking, ...)
./scripts/infra.sh redis     # a redis-cli shell
./scripts/infra.sh reset     # delete all local data, asks first
```

Ports, all bound to 127.0.0.1 only:

| Service | Port on your machine | Memory limit |
|---|---|---|
| PostgreSQL (six databases) | 5433 | 512 MB |
| Redis | 6380 | 128 MB |
| Kafka | 9092 | 768 MB |

Change a port in `.env` if it clashes with something else. Services that run
on your machine connect to `localhost` with those ports. The settings for each
service are in `.env`, which is never committed.

## Documentation

- docs/requirements/SRS.md: what the system must do
- docs/diagrams/: architecture diagrams and the reasoning behind them
- docs/api/: API conventions and service contracts

## Workflow

Work happens on short-lived branches (feature/..., fix/..., docs/..., infra/...)
and is merged into main. Commits follow Conventional Commits, for example
feat(booking): add Redis seat hold.
