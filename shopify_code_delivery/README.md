# Shopify unlock-code delivery

When a buyer pays for a 快単パーフェクト study set in KAI's Shopify store, this
sends them the app's unlock code by email. It also writes the same code onto
the order, so the packing slip prints it. It runs as a Google Apps Script
project in a Google account owned by KAI. It costs ¥0 on the Shopify Basic
plan.

```
every 5 min   poll()
                ├─ Admin API: paid (or partly refunded) orders since LAUNCH_DATE
                │  without code-issued / code-skip / code-flagged
                └─ for each order, re-read it and decide (Core.js decideOrder):
                     wait   not paid yet (konbini), or Shopify's fraud check still running
                     skip   no study set in the order: tag code-skip (listed in the daily report)
                     flag   refunded, cancelled, fraud "cancel", deleted variant, test order in
                            live mode: tag code-flagged, a person decides
                     issue  for each set: pool → ledger (flush) → metafield → email → tag code-issued
daily 09:00   dailySummary() → SUMMARY_TO (info@kai.or.jp)
```

## Rules the code keeps

- A code, once issued, cannot be revoked. So the system is careful about when
  it issues one, and it never issues twice.
- Only an order that Shopify reports as `PAID` gets a code:
  - Konbini orders stay `PENDING` until the buyer pays, and they are picked up
    on the next poll after that.
  - Card orders wait up to 30 minutes while Shopify's fraud analysis is still
    running.
  - Orders that the analysis recommends cancelling are flagged, not issued.
- The ledger sheet is the only record of what has been issued. Each (order,
  set number) pair has one row. The row is written and flushed before
  anything is sent to Shopify or the buyer. If a run fails part-way, the next
  run finds the row and finishes the missing steps with the same code.
- Tags only keep finished orders out of the search. They never decide whether
  a code was issued.
- If anything is unclear, the order is flagged and a person decides. That
  includes a refund, a cancellation, a code already typed onto the order, and
  a line whose product was deleted.
- `LAUNCH_DATE` is required. Nothing runs without it, and no order created
  before it is ever touched.
- Nothing is lost if a run is missed, Shopify is down, or the pool is empty.
  The order stays in the query until it is finished, within Shopify's 60-day
  window (see [Limits](#limits)).

## Files

| Path | What |
|---|---|
| `apps_script/Core.js` | All decisions, as pure functions (no Google or Shopify calls). |
| `apps_script/Main.js` | Apps Script code: polling, sheets, Shopify API, mail, one-time OAuth, setup and operations. |
| `apps_script/appsscript.json` | Manifest: V8, Asia/Tokyo, five scopes, web-app settings for the one-time install. |
| `test/core.test.js` | Node tests for `Core.js`. Run `node --test` in this folder (Node 18+). |

No codes, tokens or secrets are kept in this repository. The codes live in
KAI's spreadsheets and the Shopify token lives in the script's properties.

## Setup

This happens once, before launch. Steps marked **KAI** need KAI's owner
login.

**Use the robot account for everything.** Mail goes out from whichever
account runs the code, and triggers run as the account that created them. So
the contractor works in the robot account's browser profile. `poll`,
`dailySummary`, `setupSheets` and `installTriggers` refuse to run as any
account other than `ROBOT_EMAIL`.

### 1. Google side

1. **KAI** creates a Gmail account used only for this system and shares its
   login with the contractor. The robot account owns everything below, and
   the codes are sent from it.
2. As the robot account, create two spreadsheets:
   - **コード在庫** (pool): unused codes. Share it with no one.
   - **発行台帳** (ledger): issued codes and flags. Share it with the KAI staff
     who handle resends. `setupSheets()` protects the `ledger` tab so that
     they can tick `resend` and nothing else. They may delete resolved rows
     from `flags`.
3. As the robot account, create an Apps Script project. Copy in `Core.js`,
   `Main.js` and `appsscript.json`. To see `appsscript.json`, turn on
   *Project Settings → Show "appsscript.json"*.
4. Set the Script Properties (*Project Settings → Script Properties*); the
   full list is below. For now, set these four:
   - `ROBOT_EMAIL`
   - `POOL_SHEET_ID`
   - `LEDGER_SHEET_ID`
   - `SHOP_DOMAIN`
5. Run `setupSheets()`. It creates `pool`, `import` and `exclude` in the pool
   book, and `ledger` and `flags` in the ledger book. The ledger gets 10,000
   rows and its protection. The run asks for authorisation once.

### 2. Shopify app (custom distribution, one-time OAuth)

Since 2026, apps can no longer be created in the Shopify admin. On Basic
there are no staff seats, and collaborators cannot open the store's Dev
Dashboard. So the app is built in the contractor's own free Dev Dashboard
and installed on KAI's store through a custom-distribution link.

1. From the contractor's free Partner account, send KAI's store a
   collaborator request. **KAI** gives the 4-digit collaborator request code
   and approves the request. Ask for these permissions:
   - Orders
   - Draft orders: create and edit, mark as paid
   - Products
   - Settings: notifications, custom data, and shipping and delivery (the
     packing slip)
   - *Manage and install apps and channels*
   - *Approve app charges*: there are no charges, but Shopify requires this
     permission to install.
2. In the Apps Script editor, choose *Deploy → New deployment → Web app*,
   running as *Me* with access for *Anyone*. Copy its `/exec` URL into the
   Script Property `REDIRECT_URI`. Use the URL from the dialog;
   `ScriptApp.getService().getUrl()` does not return it reliably.
3. In the Dev Dashboard, create the app **KAI Unlock Codes**:
   - Its App URL and redirect URL are both the `/exec` URL.
   - It is not embedded.
   - Its scopes are `read_orders,write_orders`.
   - If the version form has a *Protected customer data* section, select
     order data and the Email field. The purpose to give is "send the
     purchased unlock code".
   - **Release** the version. Redirect URLs take effect only in a released
     version, so any later change needs a new release.
4. Choose *Distribution → Custom distribution*, enter KAI's
   `xxx.myshopify.com` and generate the install link. This choice cannot be
   changed later.
5. Set `CLIENT_ID` and `CLIENT_SECRET`. Open the install link while signed in
   to the store, either as the owner or as the collaborator. Approve the
   install, then click *Continue* on the page that opens. (Running
   `beginOAuth()` and opening the URL it logs does the same.) `doGet()` then:
   - checks the state and the HMAC,
   - exchanges the code for a non-expiring offline token,
   - saves it as `SHOPIFY_TOKEN`,
   - deletes `CLIENT_SECRET`.
6. **Archive the web-app deployment** (*Deploy → Manage deployments*).
   Once it is archived, the running system has no public URL.

Leave out `expiring=1`. Only public apps must use expiring tokens, and this is
a custom app.

### 3. Go / no-go: can we read the buyer's email?

On the Basic plan, Shopify's own documents disagree on whether a custom app
can read `Order.email` (Level 2 protected data). Before anything else:

1. Create a draft order for the set with the contractor's own email and
   *mark it as paid*.
2. Run `goNoGoCheck()`. It should log `READABLE (go)`. It also logs the
   variant id of each line in the order: this is the value to put in
   `SET_VARIANT_IDS`.

If it logs `NOT READABLE`, see [Fallbacks](#fallbacks).

### 4. Shopify admin settings

- **Metafield definition**: *Settings → Custom data → Orders → Add
  definition*. Name it アンロックコード, with namespace and key
  `custom.unlock_code` and type *Single line text*. With the definition in
  place, staff can see the code on the order page.
- **Packing slip**: *Settings → Shipping and delivery → Packing slips → Edit*.
  Add this where the slip should show the code:
  ```liquid
  {% if order.metafields.custom.unlock_code != blank %}
    アプリのアンロックコード：{{ order.metafields.custom.unlock_code }}
  {% else %}
    ※アンロックコード未発行（発送を保留してください）
  {% endif %}
  ```
  Print one real test slip before launch.
- **Notifications**: add this line to *Order confirmation* and to *Pending
  payment success* (konbini), using the robot address:
  「アプリのアンロックコードは、お支払いの確認後に ＜ロボットのアドレス＞（一般社団法人ＫＡＩ）から、
  「【快単パーフェクト】アプリのアンロックコードのお知らせ」という件名でお送りします。
  メールの受信設定をされている方は、このアドレスからのメールを受信できるよう設定してください。」
  These emails are sent before any code exists, so they cannot carry the
  code itself. Carrier addresses (docomo, au, SoftBank) often block unknown
  gmail.com senders, which is why the line names the address.
- **SET_VARIANT_IDS**: the set's variant id, taken from `goNoGoCheck()`. Use
  commas between several. The number from the admin URL works too. Only
  these variants get codes, one code per unit. A line whose variant is later
  deleted is flagged, not skipped.
- **返品特約** (no returns for the buyer's own reasons): show it on the
  product page and on the final checkout screen (特商法).

### 5. Dry run, then go live

The dry run touches only orders that carry the tag `code-dryrun`.

1. Set `LAUNCH_DATE` to today, `SET_VARIANT_IDS`, and `LIVE=false`.
2. Generate a small test batch in `kaitan_app/`:
   `python tool/generate_codes.py --count 3 --out test_batch.csv`
3. In the pool book's `import` tab, choose *File → Import → Upload*, then
   *Replace current sheet*. Run `importCodes()`.
4. Add the tag `code-dryrun` to the paid draft order from step 3 of the
   go/no-go check. Run `poll()` once by hand, then check the following:
   - A ledger row was added.
   - The order shows the code.
   - The email arrived.
   - The order has the `code-issued` tag.
   - The slip prints the code.
   - The code unlocks the app.
5. Run `dailySummary()` once and read the report. Then cancel the test order
   (no refund is needed, since no money was taken).
6. At launch:
   1. Set `LAUNCH_DATE` to the launch day.
   2. Paste every code already handed out by hand into `exclude`. KAI's
      member list can be pasted as it is, because codes are found in any
      column.
   3. Import the remaining member codes as in step 3. The run log lists every
      refused row and why.
   4. Set `LIVE=true`.
   5. Run `installTriggers()`.
7. Open the Apps Script *Triggers* page. For the `poll` trigger, set failure
   notifications to *Notify me immediately*. In the robot's Gmail, forward
   mail from `noreply-apps-scripts-notifications@google.com` to the
   contractor.

## Script Properties

| Key | Required | Meaning |
|---|---|---|
| `ROBOT_EMAIL` | yes | The robot Gmail address; mail-sending functions run only as it |
| `SHOP_DOMAIN` | yes | `xxx.myshopify.com` |
| `POOL_SHEET_ID`, `LEDGER_SHEET_ID` | yes | Spreadsheet IDs (from their URLs) |
| `SET_VARIANT_IDS` | yes | Comma-separated variant ids that earn a code |
| `LAUNCH_DATE` | yes | `YYYY-MM-DD`; older orders are never touched |
| `LIVE` | at launch | `true` for live running. Otherwise it is a dry run: only `code-dryrun` orders are handled, and test orders are issued codes. |
| `SUMMARY_TO` | no | Daily report address, default `info@kai.or.jp` |
| `LOW_POOL` | no | The report warns when unused codes fall below this, default 30 |
| `MAIL_PROVIDER` | no | `mailapp` (default) or `resend` |
| `MAIL_FROM`, `RESEND_API_KEY` | resend only | Sender, e.g. `一般社団法人ＫＡＩ <info@kai.or.jp>` |
| `REDIRECT_URI` | install only | The web app's `/exec` URL, exactly as registered |
| `CLIENT_ID`, `CLIENT_SECRET` | install only | From the Dev Dashboard. The secret is deleted after install. The client-credentials route keeps both. |
| `SHOPIFY_TOKEN` | set by `doGet` | Offline Admin API token |
| `PAUSED` | set by `pause()` | `true` stops issuing |
| `LAST_POLL_OK`, `LAST_POLL_ERROR` | set by `poll` | Shown in the daily report |
| `TOKEN_MODE`, `CC_TOKEN*` | fallback only | The `client_credentials` route (see Fallbacks) |

Anyone with edit access to the script can read these. Share the project with
no one else.

## Operations

- **Daily report**: sent at 09:00 to `SUMMARY_TO`. Each check that cannot
  run is reported as an error line, so a missing check shows up. The report
  covers:
  - whether issuing is running, with a warning if the last successful run is
    more than 30 minutes old
  - the last error
  - codes issued in the last 24 hours
  - unused codes left, with a warning below `LOW_POOL`
  - flagged orders
  - orders stopped part-way through issuing
  - paid orders still without a code after 30 minutes
  - expired konbini orders from the last 14 days: check in KOMOJU that none
    was paid late
  - orders skipped as containing no set
- **Resend**: tick `resend` on the order's rows in the ledger. The next poll
  sends the same code(s) to the order's current email and clears the tick.
  For orders older than 60 days, which Shopify no longer returns, it sends to
  the address recorded in the ledger. To use a different address, first
  change the email on the Shopify order.
- **Flagged order**: read the reason in `flags` and decide.
  - To let the system process the order again, remove the `code-flagged` tag
    from the order.
  - Then delete the row from `flags`. Every row still in `flags` is reported
    each day.
  - Rows for "pool empty" clear themselves once the order is issued.
- **A set added to an order after issue**: remove `code-issued` from the
  order. The next poll issues the extra code and emails all of the order's
  codes.
- **Refund after issue**: the code keeps working, because a code cannot be
  revoked. Deal with it by hand.
- **Refill the pool**: in `kaitan_app/`, run
  `python tool/generate_codes.py --count 100 --out batch_YYYYMMDD.csv`. The
  purchase ids continue from `tool/codes_state.json`. Import the CSV into
  `import` as in the dry run and run `importCodes()`. The import refuses
  `--standalone` codes and codes signed with an old key.
- **Pause**: run `pause()`, and run `resume()` to continue. Either works from
  any account. Orders paid in between are handled on the first run after
  resuming. `removeTriggers()` is for decommissioning only.
- **Errors**: `poll()` stops early when the cause is not the order (empty
  pool, mail quota, or three failures in a row). It saves the error for the
  daily report and throws, so Apps Script emails the robot account, which
  forwards it. The failed order is retried on the next run.
- **Never sort or edit** the `pool` and `ledger` tabs by hand. A run that
  notices a moved row stops and retries rather than writing to the wrong row.

## Limits

- **60 days**: `read_orders` sees only orders created in the last 60 days.
  An order that is still flagged or unfinished after that is no longer
  processed automatically. The daily report warns about flags older than 45
  days.
- **MailApp**: a free Gmail account can send to 100 recipients a day, and
  one is kept for the daily report. If the quota runs out, issuing pauses
  until the next day and nothing is lost.
- **Trigger time**: a free account gets 90 minutes of trigger runtime a day.
  Runs stop early when stuck, so a backlog does not use it up.
- **Order volume**: each poll handles up to 50 orders and stops after 4
  minutes, and the next poll continues.
- **Ledger size**: the ledger holds 10,000 rows. The report warns 1,000 rows
  before it is full; then run `setupSheets()` again.

## Fallbacks

- **Buyer email not readable on Basic** (the go/no-go check fails):
  - Send the staff *New order* notification to the robot Gmail, with a line
    that carries the order name and `{{ email }}`. Read it with
    `GmailApp.search`.
  - That needs the `https://mail.google.com/` scope; `gmail.readonly` works
    only through the Gmail advanced service.
  - The decision that an order is paid still comes only from the Admin API.
  - If KAI prefers, send the code only on the packing slip and in the
    *Shipping confirmation* email. That email is sent from info@kai.or.jp
    after the code exists; test-send it first.
- **From address**: MailApp sends from the robot Gmail, with replies going to
  info@kai.or.jp. To send as info@kai.or.jp, add the mail provider's DNS
  records to kai.or.jp and set `MAIL_PROVIDER=resend`. Resend's free tier
  allows 100 emails a day. Gmail's "Send mail as" for outside addresses is
  being withdrawn, so do not build on it.
- **Client credentials** (`TOKEN_MODE=client_credentials`): this works only if
  the app lives in KAI's own organization. On Basic only the owner could build
  it, and its tokens expire every 24 h (`token_()` renews them into
  `CC_TOKEN*`). To use it:
  - delete `SHOPIFY_TOKEN`,
  - keep `CLIENT_ID` and `CLIENT_SECRET`.

  Use it only if custom distribution becomes impossible.

## Why not webhooks or Flow

- Flow's *Send HTTP request* action needs the Grow plan or higher.
- Apps Script's `doPost` cannot read request headers, so it cannot check the
  webhook's HMAC.
- Apps Script answers with a 302, which Shopify counts as a failure. Shopify
  silently deletes admin webhooks that keep failing.

Polling the Admin API every 5 minutes has none of these problems. A missed
run only delays delivery.
