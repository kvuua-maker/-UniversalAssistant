# M9 Tenant Authorization and Isolation Core

Partner isolation is enforced in the backend data-access actor. Partner principals require an exact tenant match and explicit operation permission; they cannot read or mutate another partner's dashboard or use internal finance paths. Internal administrators require distinct review and finance permissions.

Allowed and denied data operations append an audit event with subject, target tenant, operation, outcome and time. The dashboard projection intentionally exposes no credentials, webhook secrets or raw cross-tenant records. UI filtering is therefore not relied upon as a security boundary.
