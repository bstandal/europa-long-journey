# EUROPA analytics administration

EUROPA uses Umami Cloud as its analytics surface. The Hobby plan is the intended
free tier: one website, up to 100,000 events per month and six months of data
retention. The tracker is cookie-free, is configured to respect Do Not Track
and is not loaded until the reader consents through EUROPA's own control.

The service has the same hard **$0 / no-card** rule as the newsletter. Never
start a Pro trial, enter payment details or enable a paid add-on. Review Usage
monthly; if collection approaches 80,000 events in a billing period, reduce or
disable optional custom events before the limit instead of upgrading.

## One-time activation

1. Create an Umami Cloud account and choose the EU region.
2. Add the production site as one website.
3. In the GitHub repository, open **Settings → Secrets and variables → Actions → Variables**.
4. Add `UMAMI_WEBSITE_ID` with the website ID from Umami.
5. Add `UMAMI_SCRIPT_URL` with the script URL shown by Umami. The current cloud
   default is `https://cloud.umami.is/script.js`.
6. Add `UMAMI_DOMAINS` as a comma-separated allowlist of production hostnames,
   for example `bstandal.github.io,www.example.com,example.com`.
7. Store the current Umami Cloud DPA and subprocessor/transfer information in
   the private admin record; never commit a signed legal record to this
   repository.
8. Run the GitHub Pages workflow or merge to `main`.

The website ID and tracker URL are public configuration, not secrets. Local and
preview builds do not send data unless their hostname is explicitly allowlisted
and the browser has granted analytics consent.

Consent is stored only as `granted` or `denied` in the site's first-party local
storage under `europa:analytics-consent:v1`. Accept and Decline have equal
prominence. The reader can reopen the choice from the footer or privacy page;
choosing Decline after a previous acceptance stops future EUROPA analytics
events and removes the loaded tracker from the page. It does not retroactively
erase data already received by Umami.

## Measurement model

Umami records one manual pageview per full page load. Autotracking is disabled
because deep chapters update the URL hash as the reader moves between movements;
letting the tracker observe those hash changes would inflate pageviews.

| Question | Metric or view | Definition |
| --- | --- | --- |
| How many people visit? | Visitors, visits and views | Visitors are pseudonymous browser/network estimates, not verified people. |
| Where do they come from? | Country and referrer | Use country as the default geographic level. Avoid conclusions from tiny city-level samples. |
| Which chapters are read? | Paths matching `/europa-long-journey/chapters/` | Compare unique visitors first, pageviews second. |
| How long do they read? | Visit duration plus active-reading milestones | Active, visible reading sends bounded milestones at 15 seconds, 1, 3, 5, 10 and 20 minutes. This gives a useful lower-bound duration for one-page chapters without spending an event every minute. |
| How far do they get? | `chapter-depth-25`, `chapter-depth-50`, `chapter-depth-75`, `chapter-complete` | A milestone is sent once per page load when that share of movements has entered the viewport. Completion means the ending entered the viewport. |
| Do they return? | Retention insight | Umami estimates repeat browsers with a rotating pseudonymous identifier. This is directional, not a permanent person-level history. |
| Do interactions help? | Events prefixed `interaction-` | Sent once per interaction type per page load after the reader first uses it. |
| Do readers ask for updates? | `signup-prompt-shown`, `signup-prompt-dismissed`, `signup-prompt-submitted`, `signup-confirmation-returned` | Counts popup activity without sending form fields. The page path distinguishes homepage and chapter prompts. Submission events are attempts. `signup-confirmation-returned` means that a consenting browser reached the return page; it is not proof that Brevo confirmed or retained the contact. |

The same depth model is used on the long road with `journey-depth-*`,
`journey-started` and `journey-complete`.

## Current admin board

The live [EUROPA · Usage board](https://cloud.umami.is/analytics/eu/boards/3a7cf7e1-c0fb-45c8-9696-fe575ac5ffd1)
contains:

1. **Audience:** visitors, visits, views, bounce rate and visit duration.
2. **Movement:** visitors and views over time.
3. **Chapters:** paths ranked by views.
4. **Reach:** a world map of visitor countries.
5. **Reading engagement:** the tracked reader and chapter-depth events.
6. **Realtime:** live views, visitors, events and countries.
7. **Goals:** `Engaged reader (15s)`, `Completed chapter`, `Inline signup
   attempt`, `Prompt signup attempt` and `Confirmed signup return`.
8. **Funnels:** the saved `Chapter reading depth` and `Prompt to confirmed
   signup` funnels.

The reading-depth funnel has a 120-minute window between successive steps:

1. Viewed `/europa-long-journey/chapters/*`.
2. Triggered `reader-engaged`.
3. Triggered `chapter-depth-25`.
4. Triggered `chapter-depth-50`.
5. Triggered `chapter-depth-75`.
6. Triggered `chapter-complete`.

The signup funnel uses a 43,200-minute (30-day) window, matching the lifetime
of Brevo's double-opt-in link:

1. Triggered `signup-prompt-shown`.
2. Triggered `signup-prompt-submitted`.
3. Triggered `signup-confirmation-returned`.

The final step remains a browser-side signal only. Use Brevo's confirmed list
and double-opt-in log as the authoritative subscriber count.

For the monthly review, select the last 28 days and compare with the previous
28 days. Use the separate **Retention** report for repeat visits.

## Operating rules

- Do not collect names, email addresses, free text, exact coordinates or other
  personal data in event properties.
- Treat individual pageviews, visits, sessions and event rows as pseudonymous
  analytics data. Dashboard totals are aggregated views of those underlying
  records; do not describe the source records as anonymous aggregate data.
- Do not enable session replay or heatmaps by default. They are unnecessary for
  the current questions and add privacy, review and event-volume costs.
- Use Umami's referrer report for source analysis. Query strings are deliberately
  excluded from analytics so arbitrary URL parameters cannot leak into reports.
- Review the 28-day board monthly. Investigate a chapter only after the same
  pattern appears across a meaningful number of readers or more than one period.
- Export any history worth preserving before the free plan's six-month retention
  window expires.

## Verification

After deployment, use fresh browser profiles and keep Do Not Track disabled for
the positive test. Confirm that:

- before a choice, no request is made for the Umami script or collection endpoint;
- Decline persists across a reload and still makes no Umami request;
- Accept loads the configured script and creates one manual view;
- reopening Analytics choices in the footer or privacy page and choosing Decline
  stops future events;
- the home page creates one view even while its hash changes;
- the chapter creates one pageview;
- `reader-engaged` appears after 15 active seconds;
- scrolling produces the depth milestones once each;
- reaching the ending produces `chapter-complete`;
- using one chapter interaction produces one matching `interaction-*` event;
- showing, dismissing and submitting the email popup produces only the
  non-personal `signup-*` events above, never an email address or name;
- a return to the confirmation page may produce `signup-confirmation-returned`
  only when analytics consent is already active. The Brevo updates list
  and its double-opt-in record remain authoritative for subscription status.
