# BusMate BD

A bus reservation and live tracking platform for Bangladesh. Passengers search
trips, pick seats on an interactive map, pay (mocked), and share a live
tracking link with relatives. Operators manage routes, buses and trips, and
drivers send GPS positions from a mobile browser.

This is a learning project built to practise microservices, concurrency
control and event-driven design with Spring Boot.

## Status

Phase 1: repository initialization. No application code yet.

## Planned architecture

Backend services (Java, Spring Boot): API Gateway, User, Trip, Booking,
Payment, Tracking, Notification. Each service owns its own data.
Infrastructure: PostgreSQL, Redis (seat holds), Kafka (events).
Frontends (React, Vite): passenger app, operator dashboard, driver app.

## Repository layout

- backend/: Spring Boot services
- frontend/: React applications
- infrastructure/: Docker, database, Redis, Kafka and monitoring config
- docs/: requirements, architecture, diagrams, database, API, testing, ADRs
- scripts/: helper scripts

## Getting started

Setup instructions will be added once the infrastructure phase is complete.
Copy .env.example to .env before running anything.

## Workflow

Work happens on short-lived branches (feature/..., fix/..., docs/...) and is
merged into main. Commits follow Conventional Commits, for example
feat(booking): add Redis seat hold.
