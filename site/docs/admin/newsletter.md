# EUROPA newsletter administration

EUROPA uses Brevo for consented email updates. The site posts its native
signup form to Brevo's public form action; it does not use a Brevo API or SMTP
key in the browser. The intended free plan stores up to 100,000 contacts, sends
up to 300 emails per day and has no time limit.

## Free-tier guardrail

This service has a hard **$0 / no-card** rule. A new Brevo account starts on
Free automatically. The account dashboard should show `300` daily email sends
and an optional `Upgrade now` control.

- Never select Starter, Standard, Professional, Enterprise, an add-on or a paid
  trial for this project.
- Never enter payment details.
- If Brevo opens `/billing/account/plans/selection`, use the Brevo logo to
  return to the account dashboard. That page is an optional upgrade flow, not a
  requirement for using Free.
- Recheck the current Free limits before any material account change. If Free is
  ever withdrawn or becomes inadequate, disable the form and review another
  free provider; do not silently create a paid subscription.

## One-time Brevo setup

1. Accept Brevo's current Data Processing Agreement with the account terms and
   record its version/date in the private admin record. Name Brevo as processor
   in EUROPA's privacy notice before collecting a real address.
2. Create a list named `EUROPA · Updates`. Keep the existing
   `EUROPA · Chapter updates` list separate for addresses collected under the
   earlier, narrower disclosure.
3. Keep the data model minimal: collect only the required email address. Do not
   add a name, inferred interests, location or reading history to contact
   records. Use Brevo's standard `EMAIL` field, a new custom Boolean named
   `EUROPA_UPDATES_CONSENT`, and Brevo's automatically maintained
   `DOUBLE_OPT-IN` status. Do not reuse `CHAPTER_UPDATES_CONSENT`; it identifies
   the earlier chapter-only scope.
4. Create a **Full page/embedded** signup form assigned only to that list.
5. In the setup/design step, turn on **Enable GDPR fields** so Brevo adds both
   its GDPR field and declaration. EUROPA's native form records the Boolean when
   the reader clicks the clearly labelled Send me updates button; it does not
   add a second checkbox. Keep this disclosure beside the button: “By subscribing,
   you agree to emails from Bård Standal about EUROPA and new work on European
   history. Unsubscribe at any time.” Link `Privacy` to EUROPA's published
   privacy notice.
6. Enable **Double confirmation email**. State what will be sent and how often.
   Do not add a contact to the list until the confirmation link is clicked.
   Include the consent wording above in the double-opt-in template so the text
   accepted by the reader can be documented with the confirmation event.
7. Customize the double-opt-in email and messages in English. Redirect a
   submitted form to
   `https://bstandal.github.io/europa-long-journey/subscribe/check-email/` and
   the confirmation link to
   `https://bstandal.github.io/europa-long-journey/subscribe/confirmed/`. The
   native site owns immediate field validation because Simple HTML does not
   carry Brevo's JavaScript messages. Do not enable a final confirmation email
   or a welcome automation; the double-opt-in email is the only automatic
   message before an editorial update.
8. In Brevo's share step, choose **Simple HTML** and copy the exact public URL
   from the generated form's `action` attribute. Do not copy an API key, SMTP
   key or account secret. Brevo CAPTCHA requires its JavaScript embed and is not
   available in Simple HTML; double opt-in is the primary bot control for this
   deliberately script-free integration.
9. In GitHub, open **Settings → Secrets and variables → Actions → Variables**
   and add `BREVO_FORM_ACTION` with that action URL.
10. Deploy from `main`. To disable signup without a code change, delete or empty
   `BREVO_FORM_ACTION` and redeploy.

The workflow exposes the value as `PUBLIC_BREVO_FORM_ACTION`. This URL is public
by design and can be present in the built HTML. The native form mirrors Brevo's
generated `email_address_check`, `locale=en` and `html_type=simple` fields. If
Brevo regenerates the form, compare its generated field names and hidden
anti-bot fields with the native form before replacing the action. Treat such
field changes as a reviewed code change rather than additional repository
variables.

## Sender and email updates

- The verified sender is `Bård Standal · EUROPA <bard.standal@gmail.com>`.
  Keep that recognizable name unless the project later moves to an
  authenticated address on its own domain.
- Verify the sender address in Brevo. Before larger sends, use a domain owned by
  the project and authenticate it with DKIM and DMARC. `bstandal.github.io`
  cannot be authenticated because its DNS is not controlled by the project.
  Until then, Brevo may rewrite a public Gmail sender to a Brevo sending domain.
- Keep Brevo's required sender details, physical address and unsubscribe link in
  every campaign. Never hide or soften the unsubscribe link.
- Do not create a welcome or nurture sequence. Send only updates about EUROPA
  and new work on European history.
- Addresses collected under the previous “only new chapters” disclosure remain
  in the chapter-updates list and are limited to chapter announcements. Do not
  add them to the updates list or send broader messages unless they give fresh
  consent under the current wording.

## Privacy and tracking

- Do not install the Brevo website tracker, Conversations widget or Brevo popup
  script. The public form action is sufficient for signup.
- In **Settings → Campaigns → Default settings → Tracking & reports**, activate
  per-contact pixel-tracking consent and set unknown consent to **No**. EUROPA
  does not request separate pixel-tracking consent, so email updates must not
  receive recipient-level tracking pixels. Apply the same no-tracking posture
  to transactional mail and retain only delivery, bounce and unsubscribe
  records.
- Include Brevo's revoke-pixel-tracking link as well as the unsubscribe link in
  future email footers, even though EUROPA does not enable tracking for unknown
  contacts.
- Never send a name, email address, Brevo contact ID or consent text to Umami.
  Signup UI events may contain only non-personal values such as the page path and
  whether the prompt was shown, dismissed or submitted.
- Use `signup-prompt-submitted` for the popup. The page path distinguishes the
  homepage from a chapter. A
  `signup-confirmation-returned` event records only that a consenting browser
  reached EUROPA's return page. Analytics may be declined or blocked, and the
  return URL may be revisited, so the Brevo list and double-opt-in record are the
  sole authoritative source for confirmed subscription status.
- Brevo's double-opt-in link expires after 30 days. An unconfirmed address is not
  added to the subscriber list, but the attempt remains in transactional logs.
  Review and delete unconfirmed-request logs no later than 90 days after
  submission.

## Routine operations

Before each email update:

1. Match the audience to the message. Broader updates go only to the updates
   list; chapter announcements may include both lists. Exclude blocklisted
   contacts and stay within the consent held for each recipient.
2. Check sender name/address, subject, preview text, destination URL, English
   unsubscribe text and required footer details.
3. Link directly to the chapter's canonical URL. Do not add campaign query
   parameters: EUROPA deliberately excludes all URL query strings from Umami to
   prevent arbitrary values from entering analytics.
4. Send tests to desktop and mobile inboxes, then verify the chapter link,
   double-check dark mode and proofread the plain-text version.
5. Keep the free plan's 300-emails-per-day limit in mind. If the confirmed list
   exceeds 300, do not silently omit readers and do not upgrade automatically.
   Requeue the remaining recipients in daily batches, recording which batch was
   sent on each day.

Brevo may delete an inactive Free account after four months. An ordinary login,
campaign, automation or transactional send resets the inactivity period. Brevo
sends warnings before deletion, but the account owner should still verify the
account at least quarterly while no chapters are being released.

Export the confirmed list and its subscription status from **CRM → Contacts →
More actions → Export** on a regular schedule and before material account
changes. Export double-opt-in event and transactional logs often enough to
retain proof of consent, while deleting logs for requests that were never
confirmed within the 90-day limit above. Store exports encrypted outside the
repository with access limited to the account owner; never commit subscriber
data.

An unsubscribe should remain blocklisted so it cannot be accidentally reimported
and mailed. For a verified erasure request, open the contact in **CRM → Contacts**
and use **Delete permanently**, then remove the same person from any private
exports or backups where deletion is still possible. Permanent deletion is
irreversible.

## Launch QA

Use a fresh test address and verify the complete production flow:

- with `BREVO_FORM_ACTION` empty, no signup prompt or form is rendered;
- with it configured, no API/SMTP key appears in page source or built assets;
- dismissing the prompt is immediate and keyboard-accessible;
- invalid and empty fields stay on the site with a clear error;
- a valid submission reaches Brevo without exposing data to Umami;
- the address remains unconfirmed and outside the sendable list until the
  double-opt-in link is clicked;
- confirming once adds exactly one contact without a welcome sequence;
- with analytics consent already active, the confirmation return records one
  non-personal `signup-confirmation-returned` event in that browser session;
- resubmitting an existing address does not duplicate the contact;
- the unsubscribe link blocklists the test contact;
- a permanent-delete test removes the contact and its Brevo history;
- the production page works at mobile and desktop sizes and the Pages deployment
  completes successfully.

Record the launch date, Brevo form name, list name, sender address, last consent
log export and the person responsible for deletion requests in the private
admin record. Do not put subscriber data in that record.

## Brevo references

- [Terms and Data Processing Agreement](https://www.brevo.com/legal/termsofuse/)
- [Free-plan limits](https://help.brevo.com/hc/en-us/articles/208580669-FAQs-What-are-the-limits-of-the-Free-plan)
- [Inactive Free-account deletion](https://help.brevo.com/hc/en-us/articles/4410311028626-About-the-deletion-of-inactive-Free-plan-accounts)
- [Create and share a signup form](https://help.brevo.com/hc/en-us/articles/208771869-Create-a-sign-up-form-in-Brevo)
- [Double opt-in logs and proof of consent](https://help.brevo.com/hc/en-us/articles/208733449-Double-opt-in-DOI-What-it-is-and-how-to-track-user-sign-ups)
- [Per-contact pixel-tracking consent](https://help.brevo.com/hc/en-us/articles/37114679474706-About-email-tracking-pixels-and-the-CNIL-recommendation-in-Brevo)
- [Export contacts](https://help.brevo.com/hc/en-us/articles/5310065850642-Export-your-contacts-from-Brevo)
- [Permanently delete contacts](https://help.brevo.com/hc/en-us/articles/5313915904914-Delete-contacts)
