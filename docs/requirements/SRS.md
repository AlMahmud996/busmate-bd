# BusMate BD: Software Requirements Specification

Version: 0.2 (draft for architecture review)
Project: Smart Bus Reservation and Live Tracking Platform
Target market: Bangladesh

Items marked DEC need a decision before this document is approved. A proposed default is given for each, and the document is written as if the default is accepted.

## 1. Introduction

### 1.1 Purpose

BusMate BD is a web-based bus reservation and live tracking platform for intercity travel in Bangladesh. Passengers search trips, choose seats on a live seat map, pay (mocked), receive a digital ticket and share a live tracking link with relatives. Operators manage buses, routes, trips and boarding. Drivers send GPS positions from a mobile browser.

Version 1 is a learning project. It is built to stay correct under concurrent load, not to handle real money or real customers.

### 1.2 Scope

Version 1 includes: registration and login, trip search, seat map with live updates, five-minute seat holds, gender-aware seat indicators, mock payment, digital tickets, booking history, shareable tracking links, operator management screens, stop-wise boarding and drop-off counts, driver GPS with offline buffering, and in-app notifications.

### 1.3 Out of scope

Real payment gateways, SMS and email, refunds and cancellation of confirmed bookings, customer reviews, loyalty programs, automated route optimization, multi-operator financial settlement, a platform administration interface, multiple languages, native mobile apps, and seat reuse across segments of one trip.

## 2. Stakeholders and roles

| Role | Has an account | Responsibility |
|---|---|---|
| Passenger | Yes | Searches, books, pays, views tickets, shares tracking |
| Relative | No | Opens a tracking link and watches the bus |
| Operator | Yes | Manages buses, routes, stops, trips, drivers; views bookings and boarding |
| Driver / conductor | Yes | Starts a trip and shares GPS positions |
| Developer | n/a | Builds and maintains the system |

There is no platform administration interface in version 1. Operator accounts are created by a seed script. Operators create their own driver accounts. A relative never logs in, and their access comes only from a tracking token (see 6.6).

## 3. Functional requirements

### Passenger
- FR-P1: Register and log in with phone number or email and a password.
- FR-P2: Search trips by departure city, destination city and journey date.
- FR-P3: View trip details: operator, bus type, departure time, arrival estimate, stops, fare, seats left.
- FR-P4: View a seat map that updates live when seats are held, booked or released.
- FR-P5: Select up to 4 seats (DEC-1). For each passenger enter name, phone, gender, boarding stop and drop-off stop.
- FR-P6: Hold the selected seats for 5 minutes, with a visible countdown.
- FR-P7: Pay with the mock payment service. The result is success or failure.
- FR-P8: Receive a digital ticket after confirmation: booking reference, trip details, seat number, boarding stop, drop-off stop.
- FR-P9: View booking history.
- FR-P10: Create, view and revoke a tracking link for a confirmed booking.
- FR-P11: Receive in-app notifications when payment succeeds or fails and when the bus is near the boarding stop.

### Relative
- FR-R1: Open a tracking link without logging in.
- FR-R2: See the bus position on a map, the route, the next stop and the estimated arrival there.
- FR-R3: See a clear message when the link is expired or revoked.

### Operator
- FR-O1: Create and edit buses and seat layouts, including which seats are adjacent.
- FR-O2: Create routes and ordered stops with distances.
- FR-O3: Create schedules and trips, and assign a bus and a driver.
- FR-O4: View bookings for a trip.
- FR-O5: View boarding counts and drop-off counts per stop.
- FR-O6: View the passenger manifest: name, phone, gender, seat, boarding stop, drop-off stop, status.
- FR-O7: Mark passengers as boarded.
- FR-O8: View trip occupancy and basic statistics.

### Driver
- FR-D1: Log in and see only the trips assigned to them.
- FR-D2: Start a trip, then start and stop GPS sharing.
- FR-D3: See GPS status, the number of unsent points and sync status.
- FR-D4: See the route and stops.

## 4. Non-functional requirements

Performance
- NFR-1: Trip search responds within 2 seconds at the 95th percentile with 200 concurrent users (target, to be measured with k6).
- NFR-2: A seat change appears on other viewers' screens within about 2 seconds under normal load (target).
- NFR-3: GPS points are processed and pushed to viewers without batching delay on the live path.

Security and privacy
- NFR-4: Passwords are hashed with a modern password hash. APIs require a JWT except public tracking endpoints, which require a valid tracking token. Each role reaches only its own endpoints.
- NFR-5: Tracking tokens are unpredictable and revocable.
- NFR-6: Gender and phone numbers are personal data. They appear only where this document allows, and never in logs.

Reliability
- NFR-7: Under concurrent attempts on the same seat, exactly one succeeds.
- NFR-8: If Redis is unavailable, holds fall back to database-only locking. Booking stays correct but slower.
- NFR-9: If Kafka is unavailable, holds and bookings still work. Events wait in an outbox table and are sent when Kafka returns.
- NFR-10: Payment requests and Kafka consumers tolerate duplicates.
- NFR-11: The driver app keeps working through signal loss on long routes.
- NFR-12: A failed payment triggers compensation (seat released, booking cancelled).

Maintainability and scalability
- NFR-13: Services keep separate responsibilities and separate data, use documented API contracts and versioned events, and are independently deployable.
- NFR-14: Application services are stateless so they can scale horizontally. Redis supports temporary seat locking and Kafka supports asynchronous communication.
- NFR-15: Every request carries a correlation ID that appears in all services' logs.
- NFR-16: The system can be developed on a 7 GB RAM machine. Infrastructure runs in Docker and only the services in use run at once.

## 5. External dependencies

PostgreSQL, Redis, Apache Kafka, OpenStreetMap, Leaflet, the browser Geolocation API, Docker.

## 6. Business rules

### 6.1 Seat holds and booking states
- BR-1: A seat can be held by only one passenger at a time for a given trip.
- BR-2: A hold lasts 5 minutes from creation and is not extended. An expired hold cannot be used to confirm a booking.
- BR-3: Booking states are HELD, PENDING_PAYMENT, CONFIRMED, CANCELLED, EXPIRED. The transition diagram is part of the architecture documents.
- BR-4: When a hold expires or payment fails, the seat becomes available again.
- BR-5: Two bookings in an active state (HELD, PENDING_PAYMENT, CONFIRMED) never share a seat on the same trip. In version 1 this holds for the whole trip, even when passengers have different drop-off stops. The database enforces this, not only Redis.
- BR-6: Each booking stores boarding and drop-off stop positions, so seat reuse across segments can be added later.
- BR-7: Fare, trip details and stop names are copied into the booking at creation time (snapshot), so later changes to the trip do not alter existing tickets.

### 6.2 Payment
- BR-8: A booking becomes CONFIRMED only after successful payment.
- BR-9: A repeated payment request with the same idempotency key must not charge twice.
- BR-10: If payment succeeds after the hold has expired, the system confirms the seat only if it is still free. Otherwise the payment is marked for reversal and the passenger is told (DEC-2).

### 6.3 Gender display and women-only neighbours
These rules need your decision (DEC-3 to DEC-5). The text below is my proposal.
- BR-11: Gender is self-declared per passenger at booking. It is not verified, and the screen says so.
- BR-12: Passengers choose male, female or prefer not to say. "Prefer not to say" shows a neutral icon and counts as unrestricted for adjacency rules.
- BR-13: Other passengers see only a gender icon, and only on CONFIRMED seats. Held seats show as taken with no icon. Names, phone numbers, ages and stops are never shown to other passengers (DEC-3).
- BR-14: A woman can choose "keep my neighbouring seat for women". The adjacent free seat then accepts bookings from women and "prefer not to say" only.
- BR-15: That restriction is lifted 2 hours before departure so the seat can still be sold (DEC-4).
- BR-16: There is no opt-out of the gender icon in version 1, because the safety feature depends on it. The booking page says so before submission (DEC-5).
- BR-17: The operator sees full passenger details in the manifest.

### 6.4 Stop-wise boarding
- BR-18: Boarding stop must come before drop-off stop in the route order.
- BR-19: Boarding and drop-off counts use only CONFIRMED bookings and valid boarding records.

### 6.5 GPS
- BR-20: Only the driver assigned to a trip can send GPS updates for it.
- BR-21: The driver app sends a position every 5 to 10 seconds while sharing is on. Default is 5 seconds.
- BR-22: Every point carries a GPS timestamp and a sequence number per trip session.
- BR-23: The server rejects impossible coordinates, points outside Bangladesh's bounding box, and points implying a speed above 150 km/h from the previous point (defaults, tunable).
- BR-24: Duplicate points (same session and sequence number) are ignored without error.
- BR-25: When the connection drops, the app keeps points locally and uploads them in batches when it returns.

### 6.6 Tracking links
- BR-26: A link carries a long random token. The server stores only a hash of it.
- BR-27: A token belongs to one trip and is created by a passenger with a confirmed booking on that trip.
- BR-28: A token expires 2 hours after the trip is completed (DEC-6). The creator can revoke it at any time.
- BR-29: A token shows the bus position, route, next stop and ETA. It never shows passenger names, phone numbers, seats or other bookings.

## 7. Open decisions

| ID | Question | Proposal |
|---|---|---|
| DEC-1 | Maximum seats per booking | 4 |
| DEC-2 | Payment succeeds after the hold expired | Confirm only if the seat is still free, otherwise reverse and notify |
| DEC-3 | When the gender icon appears | Only on CONFIRMED seats |
| DEC-4 | When the women-only neighbour restriction is lifted | 2 hours before departure |
| DEC-5 | Can passengers hide their gender icon | No, with a notice at booking |
| DEC-6 | How long tracking links stay valid after the trip ends | 2 hours |

## 8. Acceptance criteria

Version 1 is complete when all of these hold:

1. Passengers can search trips, select seats and hold them.
2. Two passengers cannot both reserve the same seat on the same trip, even under concurrent requests.
3. An expired hold makes the seat available again.
4. Mock payments can succeed or fail. A duplicate payment request does not create a second successful charge.
5. A failed payment releases the seat and cancels the booking.
6. Confirmed bookings generate digital tickets.
7. GPS points recorded offline reach the server after the connection returns.
8. Tracking viewers see authorized location information only. An expired or revoked link stops working.
9. Users without the right role cannot reach protected trip, booking or admin data.
10. Operators can manage trips, and boarding counts match the CONFIRMED booking records.
11. Security and integration tests pass.
12. The whole application starts from the documented setup procedure.
