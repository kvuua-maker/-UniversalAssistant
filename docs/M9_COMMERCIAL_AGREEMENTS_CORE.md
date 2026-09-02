# M9 Commercial Agreements Core

Commercial models are typed configuration values covering every canonical model; no price or rate is embedded in business logic. Agreement versions preserve partner, effective period, qualifying event, currency, attribution window, refund/settlement references, geography, scope and optional floor/cap.

The server registry is append-only: duplicate versions and overlapping effective periods are rejected. A conversion can resolve the exact active immutable version applicable at its qualifying-event timestamp, so later terms never rewrite historical commission rules. Production values and templates remain owner-controlled configuration.
