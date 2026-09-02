# M9 Partner Domain and Onboarding Core

The backend now models the canonical partner application states and four integration levels. A validated draft remains inactive after submission; evidence-based verification, any required technical validation, a commercial agreement reference, explicit approval, and a separate activation transition are enforced server-side.

Every state transition appends a sequenced audit event with actor reference, reason code, previous/next state and timestamp. Critical legal identity changes revoke existing evidence and approval and return the application to `VERIFICATION_REQUIRED`. The service does not perform KYC, invent country/category eligibility, or activate a submitted form automatically; production policy and verification providers remain owner-configured boundaries.
