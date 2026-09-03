# Ukrainian Jobs Source Audit

Observed 2026-09-03 from official provider/government pages. “No verified API” means no official contract was proven during this bounded audit; it does not assert none exists. CAPTCHA/403 is classified blocked, never “no vacancy”. No provider is classified commercial/revenue without an executed agreement.

| Provider | Official observed mechanism | Auth / permitted display | Fields/freshness | Commercial/attribution | Failure and implementation state | Evidence |
|---|---|---|---|---|---|---|
| Work.ua | public job/employer pages; robots permits public areas and forbids private resume/employer/API paths | no credential for exact public handoff; private areas prohibited | only page-proven facts/timestamps | NONE VERIFIED | generic permitted discovery/exact handoff; private/API paths disabled | https://www.work.ua/ and /robots.txt, 2026-09-03 |
| robota.ua | official public site, currently Cloudflare-blocked to automated audit | no contract proven | UNKNOWN until retrievable | NONE VERIFIED | exact external handoff only; blocked != absent | https://robota.ua/, HTTP 403, 2026-09-03 |
| Jobs.ua | public vacancy/search/employer/add pages; robots allows public and blocks login/docs | no credential for public handoff | page-proven vacancy facts only | NONE VERIFIED | permitted discovery/exact vacancy handoff | https://jobs.ua/ and /robots.txt, 2026-09-03 |
| Jooble | official API-about URL exists but is Cloudflare-blocked; public search product | API contract/key not locally available | UNKNOWN until authorized contract | NONE VERIFIED | API adapter must wait for official schema/key; exact handoff fallback | https://jooble.org/api/about, HTTP 403, 2026-09-03 |
| State Employment Service | official `dcz.gov.ua` vacancy application is reachable | public government source; no private access | only official returned facts | noncommercial | authoritative government handoff/discovery; dynamic failure remains unknown | https://www.dcz.gov.ua/vacancy, HTTP 200, 2026-09-03 |
| OLX Робота | official category page currently anti-bot blocked | no partner/API contract proven | UNKNOWN | NONE VERIFIED | exact handoff only; 403 != no vacancy | https://www.olx.ua/uk/rabota/, HTTP 403, 2026-09-03 |
| Djinni | official public jobs pages; robots blocks candidate/developer/private query areas | public exact handoff only | public page-proven facts | NONE VERIFIED | public job discovery/handoff; private database prohibited | https://djinni.co/jobs/ and /robots.txt, 2026-09-03 |
| DOU Jobs | official public vacancies and company vacancy pages; robots documents crawler restrictions | public exact handoff only | public page-proven facts | NONE VERIFIED | permitted public discovery/handoff | https://jobs.dou.ua/ and /robots.txt, 2026-09-03 |
| Happy Monday | official jobs page; robots says search=yes and ai-train=no/use=reference | search links/short excerpts only; no AI ingestion | page-proven facts | NONE VERIFIED | reference/search + exact handoff, respecting content signals | https://happymonday.ua/jobs-search and /robots.txt, 2026-09-03 |

Other international/specialized sources may be added only through the same controlled registry after current official mechanism/territory/terms evidence. This audit intentionally does not infer APIs, OAuth, feeds, partnerships, affiliate eligibility or revenue from a public website.
