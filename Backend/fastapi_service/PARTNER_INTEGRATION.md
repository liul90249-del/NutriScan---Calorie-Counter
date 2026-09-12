# Current deployment decision: shared backend

The user selected reuse of the existing paid SquadLive service. Do not upgrade NutriScan's Free AI service or attach a new disk. The Python inbox below is retained as an alternative implementation, not the selected deployment.

NutriScan App uploads now target `https://squadlive.onrender.com/v1/partners/nutriscan/transactions`. The selected notification target will be `https://squadlive.onrender.com/v1/partners/nutriscan/notifications` after the Node inbox is deployed. Existing SquadLive `/var/data` disk is 1 GB with daily snapshots; product/environment files are isolated.

The Node implementation passed 25 tests and 4 local HTTP checks; the changed NutriScan upload target passed a full simulator build. Production main push was blocked by automatic approval review and still requires owner approval. No Apple notification configuration has been changed. No new recurring cost has been accepted or incurred. Referral binding and commission export are still incomplete.

---

## Previous alternative (not selected)

# NutriScan transaction inbox — integration status

The FastAPI app now mounts `/v1/partner/transactions` and `/v1/partner/notifications`.
Both accept Apple-signed input and verify it with Apple's Python library and bundled Apple root certificates. Verification includes the production App ID 6786940107 and bundle `com.liuzhigang.NutriScan`, confirmed in App Store Connect on 2026-09-12. Only the three configured NutriScan subscription SKUs are accepted.

## Required deployment configuration

The existing Render service `srv-d92sc3ugvqtc739frplg` is on the Free instance. It has no persistent disk support. Do not store the inbox in its temporary filesystem.

1. Obtain approval for the additional recurring cost: $7/month instance plus 1 GB disk at $0.25/month, excluding extra usage.
2. Attach the persistent disk at `/var/data` and set `NUTRISCAN_PARTNER_DB_PATH=/var/data/partner-transactions.sqlite3`.
3. Deploy the reviewed backend changes. The Dockerfile copies both the new module and public Apple certificates.
4. Only after the endpoint is deployed, configure both Apple production and sandbox notifications to `https://nutriscan-ai-backend-1hq0.onrender.com/v1/partner/notifications`. Both are currently empty; no settings changed during the read-only inspection.
5. Confirm a real Apple test notification and sandbox transaction, including replay, renewal, refund and restart.

Missing storage configuration returns HTTP 503. The new routes never use the existing shared AI client token as a personal account identity. A receipt proves a transaction, not the caller's personal identity.

## App integration

`PartnerTransactionOutbox` persists locally verified JWS data before finishing purchases and transaction updates. It retries pending files at launch and after new transactions. Acknowledged files are removed only if they have not changed during transmission. Network failures retain files. The queue is excluded from device backups and uses iOS file protection. No food logs or profile data are transmitted.

The separate integration checkout restores missing Firebase package references from the user's Downloads project configuration, corrects the bundle ID, restores the existing ProgressClamping helper, and fixes a missing SwiftUI return in DashboardView. The local Firebase plist is ignored by Git and must not be committed.

## Not yet implemented

- Referral identity registration, trustworthy migration of the existing first-use date, automatic link binding, and account-token creation for purchases.
- Attribution/commission export to the partner portal. Every inbox response intentionally reports `commission_eligible:false` and `attribution_status:not_bound`.
- Server-controlled entitlement delivery or membership offers. This inbox does not change existing App membership state.
- Automatic recovery of Apple notification history or offline subscriptions that predate deployment. Real notification delivery still needs acceptance testing.
- App Store/TestFlight submission and production rollout. Do not interpret source-level tests as successful live payments.

The persistent SQLite design is for one service instance; do not horizontally scale it into independent disks.
