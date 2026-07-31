# Apple platform contract audit

Checked: 25 July 2026

Scope: the local iOS 26.4 architecture and configuration. This record does not
claim a signed distribution build, a live transaction, a hosted-pack transfer,
a CloudKit production subscription or APNs delivery.

## Device boundary

Apple defines `iphone-performance-gaming-tier` as the graphics-performance and
gaming-feature class of iPhone 15 Pro and iPhone 15 Pro Max. The app declares
that capability together with `arm64` and `metal`, targets iPhone only and
exposes portrait as its sole launch orientation.

The capability is enforced by `native/tooling/src/ios-config.mjs`. Apple allows
an update to maintain or relax a required capability, but not to add a stricter
requirement after customers have already installed the app. It therefore has to
be present in the first distributed version.

Primary source:
[UIRequiredDeviceCapabilities](https://developer.apple.com/documentation/bundleresources/information-property-list/uirequireddevicecapabilities)

## Apple-hosted Background Assets

The app and downloader extension share
`group.com.thelongwest.journey.assets`. The app declares `BAAppGroupID`,
`BAHasManagedAssetPacks = true` and `BAUsesAppleHosting = true`. The extension
uses `com.apple.background-asset-downloader-extension`. Its custom policy
declines unsolicited automatic downloads; the app starts the user-selected
pack or `Download all` operation.

Apple currently permits 200 GB and 200 Apple-hosted asset packs per app. App
Review accepts at most ten different packs in one submission. The launch plan
uses eight packs, so the review grouping is within the current limit. The
planned complete installation ceiling of 6 GB is also within the hosting
allowance. These figures do not prove that any production pack has been built,
uploaded or reviewed.

Primary sources:

- [Downloading Apple-hosted asset packs](https://developer.apple.com/documentation/BackgroundAssets/downloading-apple-hosted-asset-packs)
- [Apple-hosted asset pack size limits](https://developer.apple.com/help/app-store-connect/reference/app-uploads/apple-hosted-asset-pack-size-limits/)
- [Submit Apple-hosted asset packs](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-apple-hosted-asset-packs/)

## StoreKit 2

`StoreKit2Provider` loads the one product, rejects any product that is not a
non-consumable, maps `pending` and cancellation separately, accepts only
verified transactions, listens to `Transaction.updates`, finishes delivered
transactions and uses the current-entitlements sequence for restoration.

Apple states that current entitlements include non-consumables and exclude
refunded or revoked purchases. The local entitlement controller also keeps a
sealed offline ownership record; that project record never substitutes for
StoreKit verification when the store is reachable.

Primary sources:

- [Transaction](https://developer.apple.com/documentation/storekit/transaction)
- [Transaction.currentEntitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements)

## CloudKit and the single release notification

The public-database adapter creates one `CKQuerySubscription` for newly
available release records. It requests a content-available notification only.
The push payload is treated as a coalescible hint: the controller refetches the
complete paginated catalog, verifies the release record and durable notification
claim, then schedules the authored local notification. A notification tap is
resolved through the authenticated local release entry rather than through
untrusted push fields.

This matches Apple's rule that query-subscription notifications can be
coalesced or omit fields and that the app must fetch current records. The app
declares `fetch` and `remote-notification` background modes and the CloudKit
container `iCloud.com.thelongwest.journey`.

Primary source:
[CKQuerySubscription](https://developer.apple.com/documentation/CloudKit/CKQuerySubscription)

## Included service capacity

Apple Developer Program membership currently includes up to 1 PB of CloudKit
storage per app and 200 GB of Apple-hosted Background Assets. The architecture
does not require a separate paid server for the launch release catalog,
entitlement edge or content hosting.

Primary source:
[Apple Developer Program membership details](https://developer.apple.com/programs/whats-included/)

## Automated local enforcement

`native/tooling/src/ios-config.mjs` now rejects drift in:

- the iOS 26.4 deployment target;
- iPhone-only portrait configuration;
- the three required device capabilities;
- the three Apple-hosted Background Assets keys;
- the shared app/extension group;
- the downloader extension point;
- the CloudKit container and service entitlement;
- the APNs entitlement environment;
- the two background modes required by the release-hint route.

The focused contract suite passed `8/8` on 25 July 2026. The complete native
suite must still be rerun after the active narration, audio and migration work
settles.

## Deferred live evidence

The following remain in the final Apple-service gate:

- inspect the signed distribution app's effective `aps-environment` and iCloud
  entitlements; the checked source entitlement is currently `development`;
- create the real non-consumable product and exercise purchase, pending,
  restore, refund and revocation;
- package, upload, review, interrupt, update and roll back real hosted packs;
- deploy the CloudKit schema and subscription in the production environment;
- receive one actual APNs hint, refetch the release and present the single
  local notification;
- repeat complete installed-content use in airplane mode on the floor device.
