# Build 26 external provider audit

Audit checkpoint: source commit `85fc3815c6cc8a37cbabe3c407530750f5d16cf2`.

## Current FX

Repository and Production configuration searches found no configured FX endpoint,
credential reference, exchange-rate transport, or production coordinator. Currency
phrases are parsed locally as `currencyConversion`, but execution deliberately returns
`externalProviderRequired("current_fx_rate")`. Fixed-ratio unit conversion cannot
handle money and no rate is fabricated. A live FX response requires an owner-approved,
current, attributable provider and production credential/configuration.

## General/current information

`AssistantViewModel` supports injection of `GenericUnknownRequestCoordinator`, but its
production initializer supplies none. `UserConnectedAIConfiguration` is a persistence
contract only; the repository contains no production credential reference or active
AI/current-information transport. Current-information requests therefore use the
explicit controlled browser handoff and cannot truthfully claim an in-app current answer.

## Product/current prices

`GenericRetailWebProvider` and provider registries are injectable contracts. No active
Production endpoint/token is configured for current catalog or price retrieval. Product
requests therefore use the controlled current-web handoff while preserving the user's
query and constraints. Tests/mocks are not evidence of a live provider.

These are external integration dependencies, not permission to invent credentials,
rates, prices, availability, or provenance.
