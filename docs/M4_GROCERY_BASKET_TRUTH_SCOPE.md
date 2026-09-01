# M4 Grocery Basket Parsing and Total Truth

- Grocery list parsing creates stable basket items and normalizes kg/g to grams, l/ml to millilitres and unqualified items to pieces.
- Quote matches distinguish exact product, equivalent quantity, substitute, unavailable and unverified states.
- Unit prices use normalized supplied quantity so different pack sizes can be compared without misleading arithmetic.
- Per-store subtotal retains only actual quoted line prices and explicitly exposes unavailable, unverified and substitute item IDs.
- A basket is complete only when every requested item has an exact/equivalent match and a same-currency real price. A partial subtotal is never presented as a complete total.
- Store comparison ranks complete baskets before cheaper incomplete baskets and keeps mixed/non-comparable currencies stable rather than inventing conversion.

Verification: Development build and simulator suite passed 87 tests in 22 suites on 2026-09-01. Two-store and route-cost optimization are intentionally the next independent block.
