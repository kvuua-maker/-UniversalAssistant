# Marketplace Commerce & Affiliate Hub — Final Complete Addendum

Статус: це доповнення є невід’ємною обов’язковою частиною Master Spec v13.2 UniversalAssistant. Воно не скасовує і не послаблює попередні вимоги v13.2. Не починати проєкт заново, не руйнувати перевірені M0/M1; Commerce Hub інтегрується в чинну модульну архітектуру.

1. **Product goal.** Єдиний красивий і швидкий інтерфейс: user intent → exact product → multi-source search → normalize → compare → premium result → exact purchase handoff → legitimate affiliate attribution.
2. **One app.** Commerce Hub — модуль UniversalAssistant, не окремий app; reuse command engine, camera/OCR/barcode, location, backend, networking, cache, security, design system, deep links.
3. **Business model.** Не продавець, reseller, fulfillment, власний checkout фізичного товару чи markup. Seller/marketplace продає; монетизація — affiliate/referral commission де дозволено.
4. **User interest first.** Ranking визначає користь користувачу, не commission: exact variant, estimated final cost, availability, delivery/ETA, seller protections, returns/warranty.
5. **User-intent only.** Не нав’язувати товари/акції/поради. Попросив — зробити. DO, DON’T NARRATE.
6. **Extensible core.** Provider/adapters без architectural limit; core, capability registry, identity/variant resolution, normalization, ranking, affiliate routing, cache/observability — мінімально необхідна modular architecture.
7. **Legitimate sources.** Official APIs/SDKs/feeds/affiliate networks/deep links/structured catalogues only. No invented API/commission, forbidden scraping, CAPTCHA/security bypass. Current official docs before production.
8. **Ukraine first.** Українські магазини/marketplaces/affiliate networks first-class; global sources теж, якщо реально доступні/корисні.
9. **Exact product identity.** Brand/model/SKU/GTIN/EAN/UPC/barcode/storage/size/color/generation/region/condition/configuration/quantity. Approximate ≠ exact.
10. **Camera to commerce.** Camera/barcode/OCR/visual search → identity → Commerce. Barcode/SKU higher confidence than visual similarity.
11. **Beautiful native Commerce UI.** Premium native iOS cards, не raw API/JSON/URL list. Image, exact variant, price/discount, source/seller, availability, delivery, returns/warranty, known taxes/duties, estimated final cost, freshness. Main info first; details on demand.
12. **Proven labels.** Best total price/fastest/best value/official store labels only when objectively supported.
13. **Real total cost.** Item price + shipping + known taxes + known/estimated duties + required known costs where determinable. Unknowns never invented.
14. **Delivery to Ukraine.** Delivery availability/cost/ETA/restrictions/customs-tax implications where legitimately available.
15. **Seller quality.** Rating/reviews/protections/returns/warranty/condition/verified official status where available. Lowest price ≠ automatically best.
16. **Purchase flow.** Search/compare/select in UniversalAssistant. Buy → exact affiliate/deep link → exact variant/offer → official app if possible → exact official page. Avoid homepage.
17. **Affiliate attribution.** Allowed tracking/campaign/sub IDs and deep-link attribution; preserve through app handoff where supported; never claim attribution without evidence.
18. **Post-purchase.** Order/tracking/delivery only through official supported data/deep links and only on user request; no invented status.
19. **Capability registry.** Per source: regions, search/catalog, exact product, price, availability, shipping, affiliate/network, deep link/app handoff, credentials, owner registration/approval, rate limits, restrictions, implementation/test/fallback, last verified. Reuse verified research.
20. **Owner-only blockers.** Registration, agreements, identity/tax/bank, CAPTCHA/2FA, approval, owner-only credentials. Build everything possible first; then report provider/what/where/what to obtain/why. One blocker never stops project.
21. **Performance is first-class.** Commerce must not make UniversalAssistant heavy, slow, battery-hungry or unstable. On-demand only; no all-provider initialization/network calls/catalog loading at launch.
22. **Fast startup.** Commerce must not materially degrade cold/warm start. Lazy initialize only required provider path.
23. **No full catalog on device.** No full marketplace catalogues/indexes on iPhone; no binary/storage bloat; on-demand/server/provider search.
24. **Progressive loading.** Show first useful verified result quickly; secondary data later without blocking UI.
25. **Parallel bounded search.** Independent providers in parallel when useful; bounded concurrency, no uncontrolled fan-out; progressive verified results.
26. **Request deduplication.** Merge identical simultaneous/in-flight requests; reuse valid in-flight/fresh results; no duplicate provider work.
27. **Bounded cache.** Bounded size/time; explicit freshness for price/availability/shipping; stale never current; bounded image cache/cleanup.
28. **Main thread protection.** Networking/normalization/images/FX/dedup/ranking/parsing off main UI thread.
29. **Timeout and partial results.** Bounded provider timeouts; one slow provider cannot block; show sufficient partial results.
30. **Cancellation.** New intent cancels obsolete commerce work where safe.
31. **Rate limit retry backoff.** Respect rate limits; bounded transient retry/backoff/jitter; no retry storms.
32. **Resource control.** Control RAM/CPU/battery/network/disk; no large retained decoded images/payloads; no polling without explicit user-enabled need.
33. **Image performance.** Thumbnails/resized cards, full-res on demand, async/progressive loading, bounded caches.
34. **Network efficiency.** Only needed fields where possible; avoid oversized payloads; compression/cache/ETag where appropriate.
35. **Server-side where better.** Aggregation/normalization/affiliate routing server-side when it improves phone load/security/performance; unrelated local commands remain independent.
36. **Secrets.** No API/affiliate/private secrets in iOS client, GitHub or logs; appropriate server/keychain/CI secret storage.
37. **Config and kill switch.** Server-config provider enable/disable, affiliate IDs, campaign/sub IDs, regions, credential refs, approval, feature flags; kill broken provider without app breakage/new release where feasible.
38. **Privacy analytics.** Where allowed: impression/search → offer selection → outbound affiliate click → provider-confirmed conversion. Data minimization, no hidden cross-service tracking, Apple privacy/ATT where applicable.
39. **Commission truth.** Purchase/conversion/commission only confirmed by real provider reporting.
40. **App Store legal disclosure.** Before production verify current Apple rules, affiliate disclosure, provider terms, consumer/privacy requirements. No misleading advertising.
41. **Honest positioning.** Promise finding/comparing available offers in connected sources and direct handoff. Never promise all products/all marketplaces/always lowest/guaranteed price without proof.
42. **No primitive comparison.** If comparison requested, use meaningful factors, not merely “500 UAH cheaper”; if not requested, don’t narrate it.
43. **Non-commerce isolation.** Commerce dependencies/cache/provider failures cannot slow or break Calendar, Reminders, Contacts, Camera, Navigation, local command parsing.
44. **Light dependencies.** Prefer lighter legitimate API/deep-link adapter over heavy SDK when outcome is equal/better.
45. **Performance budgets.** Measure baselines/regression thresholds for startup, first useful commerce result, card scrolling, memory, images, cancellation, timeout. Evidence-based targets, not arbitrary marketing numbers.
46. **Failure isolation.** Each adapter isolated; malformed/error provider cannot crash core/UI.
47. **Data validation.** Validate payloads; track source/timestamp; reject/downgrade anomalous/missing price/currency/availability.
48. **Currency normalization.** Current legitimate FX source; retain source currency where useful; don’t hide meaningful conversion uncertainty/fees.
49. **Offer dedup.** Dedup only reliable duplicates; don’t merge different seller/condition/variant.
50. **Search quality.** Prefer fewer exact/relevant offers over noisy weak matches.
51. **Stable UI updates.** Progressive results should not chaotically reorder while user interacts; stable ranking/update strategy.
52. **Purchase safety.** Affiliate click/deep link ≠ purchase. “Bought” only after real confirmation. All financial/irreversible v13.2 safety remains.
53. **Accessibility/languages.** All V1 languages, Dynamic Type/VoiceOver/accessibility; brand/model/SKU preserved.
54. **Observability.** Provider latency/failures/cache/freshness/normalization diagnostics without secrets/unnecessary private content.
55. **Test strategy.** Tests for exact/variant matching, dedup, FX, final cost, seller differentiation, commission-independent ranking, affiliate routing/fallback, stale price, timeout/partial, cancellation, duplicate requests, malformed payload, cache expiry, Ukraine shipping, exact deep link, secret leakage and performance where practical.
56. **Mock truth.** Mocks internal only; no production-complete claim without real provider verification.
57. **Provider status.** Accurate statuses: researched, adapter-ready, credential-required, approval-required, device-test-required, fully-implemented/tested, fallback, unsupported etc. Stub ≠ integration.
58. **Incremental providers.** Build core/interfaces now; connect available providers progressively; blocked providers don’t block others.
59. **No overengineering.** Use simplest maintainable architecture satisfying isolation, extensibility, performance, testability, security.
60. **Codex limit efficiency.** Reuse registry/docs/evidence; no repeated research/reads/builds without reason; batch independent checks; stop block when evidence sufficient.
61. **Git status.** Store this addendum in repository source-of-truth/docs; update architecture/status/test plans. Do not create another repo or restart M0/M1.
62. **Integration into current work.** Add necessary domain models/protocols/adapters/backend interfaces/UI/routing/tests/security/docs in correct milestones with minimal clean changes and no regressions.
63. **Acceptance.** Commerce accepted only if app remains lightweight/fast, provider failures isolated, exact identity protected, ranking independent of commission, affiliate routing preserves user outcome, UI premium/native, live claims verified.
64. **Final directive.** Read entire addendum, persist it as mandatory v13.2 requirement, then confirm in Ukrainian: “Marketplace Commerce & Affiliate Hub addendum прийнято”. Continue current implementation autonomously from current checkpoint. No owner approval for ordinary engineering/build/test/Git actions; ask only for true owner-only blockers. Communicate with owner only in Ukrainian.
