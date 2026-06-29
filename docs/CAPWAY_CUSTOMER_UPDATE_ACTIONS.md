# Implementing `:capway_update_customer` action items

This document is the contract for the **executor** — the Trinity-side worker that
drains `:capway_update_customer` action items from DynamoDB and performs the
actual REST writes against the payment processor / Capway.

`capway-sync-ex` (this app) **only detects drift and writes action items**. It
never mutates the Capway customer record. Everything below describes what the
*consumer* must do.

---

## 1. Where the items come from

- `CompareDataV2.get_customers_to_update/3` compares each active Capway customer
  against the source of truth and, when one or more fields differ, writes an
  action item with `action: :capway_update_customer`.
- Items are stored by `ActionItemRepositoryV2.store_action_item/1` into the
  DynamoDB table named by `ACTION_ITEMS_TABLE` (default `capway-sync-action-items`).

## 2. DynamoDB item shape

| Attribute               | Type      | Notes |
|-------------------------|-----------|-------|
| `id`                    | `S`       | `"<created_at>:<action>:cref:<contract_ref>"` (other shapes for items lacking a contract ref — see `ActionItemRepositoryV2.create_id/1`). |
| `action`                | `S`       | `"capway_update_customer"` for everything in this doc. |
| `sub_action`            | **`L` of `S`** | **List** of the fields that drifted, e.g. `["update_nin","update_language"]`. ⚠️ See §5 — this used to be a single string. |
| `status`                | `S`       | `"pending"` on write. The executor advances it (§7). |
| `comment`               | `S`       | Human-readable reason, e.g. `"National ID and currency code mismatch"`. **Never** contains PII (email/national-id values). Do not parse it for logic. |
| `capway_customer_id`    | `S`/null  | Capway customer id — the target of the PATCH. |
| `capway_contract_ref`   | `S`/null  | Capway contract reference. |
| `capway_contract_guid`  | `S`/null  | Capway customer GUID. |
| `national_id`           | `S`/null  | ⚠️ The **Capway-side** (current/stale) national id, *not* the desired value. |
| `trinity_subscriber_id` | `N`/null  | Use this to look up the source-of-truth values. |
| `trinity_subscription_id` | `N`/null | |
| `created_at`            | `S`       | `YYYY-MM-DD`. |
| `timestamp`             | `N`       | Unix seconds. |

> **Key principle:** an action item is a *"go reconcile this customer"* signal,
> **not** a full diff payload. The desired values are deliberately not embedded
> (email/NIN are PII; language/currency are derivable). The executor must
> re-read the source of truth and push it — see §4 and §6.

## 3. `sub_action` values

`sub_action` is the list of fields to fix. Possible elements:

| Element            | Field to update on the Capway customer | Source of the correct value |
|--------------------|------------------------------------------|------------------------------|
| `"update_nin"`     | `idNumber` (national id)                 | **Trinity** subscriber |
| `"update_email"`   | `email`                                  | **Trinity** subscriber |
| `"update_language"`| `languageCode`                           | **Market default** (§6) |
| `"update_currency"`| `currencyCode`                           | **Market default** (§6) |

A single item can carry any combination, e.g.
`["update_nin","update_email","update_language","update_currency"]`. Apply all
of them in one customer PATCH where the API allows it.

## 4. Execution algorithm

For each `pending` item with `action == "capway_update_customer"`:

1. **Resolve the target.** `capway_customer_id` is the customer to PATCH. If it
   is null, the item cannot be executed — mark `failed` with a reason.
2. **Build the patch payload** by walking `sub_action`:
   - `update_email` / `update_nin` → read the **current** value from the Trinity
     subscriber (look it up by `trinity_subscriber_id`). Trinity is the source of
     truth for these. Do **not** use the item's `national_id` attribute as the
     target — it is the stale Capway value.
   - `update_language` / `update_currency` → use the **market default** for the
     active market (§6). These are not Trinity-derived.
3. **PATCH the Capway customer** via the payment processor REST API (the same
   customer addressed by `GET v3/capway/customers/by_customer_id/:customer_id`,
   which this app uses read-only).
4. **Re-check / advance status** (§7).

Pseudo-code:

```elixir
def execute(%{"action" => "capway_update_customer"} = item) do
  customer_id = item["capway_customer_id"] || throw(:no_customer_id)
  trinity = Trinity.get_subscriber!(item["trinity_subscriber_id"])

  patch =
    Enum.reduce(item["sub_action"], %{}, fn
      "update_email",    acc -> Map.put(acc, :email, trinity.email)
      "update_nin",      acc -> Map.put(acc, :idNumber, trinity.national_id)
      "update_language", acc -> Map.put(acc, :languageCode, Market.language_code())
      "update_currency", acc -> Map.put(acc, :currencyCode, Market.currency_code())
      _unknown,          acc -> acc   # forward-compat: ignore unrecognised values
    end)

  PaymentProcessor.patch_capway_customer(customer_id, patch)
end
```

## 5. ⚠️ Migration: `sub_action` is now a list

Previously `sub_action` was a single string (`"update_email"`, `"update_nin"`,
`"update_email_and_nin"`). It is now a **list of strings**. The combination atom
`"update_email_and_nin"` no longer exists — it is now `["update_nin","update_email"]`.

The executor MUST:
- read `sub_action` as a list (DynamoDB attribute type `L`);
- tolerate (ignore) unrecognised elements, so future fields don't break it;
- if any old single-string items may still be in the table, normalise with a
  "wrap in a list if it's a string" shim before processing.

## 6. Market defaults

Language and currency are not compared against Trinity — they are compared
against the expected value for the active market (`MARKET` env var; case is
normalised). The executor needs the **same mapping** as `CapwaySync.Market`:

| Market (`MARKET`) | `languageCode` | `currencyCode` |
|-------------------|----------------|----------------|
| `se`              | `sv`           | `SEK`          |
| `no`              | `nb`           | `NOK`          |

Keep this table in sync with `lib/capway_sync/market.ex` — that module is the
authoritative source. Unknown markets have no defined values and this app never
emits language/currency sub-actions for them.

**Why blank counts as wrong:** the detector flags a Capway customer whose
`languageCode`/`currencyCode` is present-but-wrong **or** fetched-but-blank.
A customer that could not be fetched at all is treated as "unknown" and is not
flagged, so a `update_language`/`update_currency` item always means "set this to
the market default."

> **`update_currency` is billing-sensitive.** Changing a live contract's currency
> can affect invoicing. Gate it behind whatever review/guardrails your billing
> rules require before issuing the PATCH — do not blindly apply it.

## 7. Status lifecycle & idempotency

- Items are written with `status: "pending"`.
- The executor should move an item to `"completed"` on a successful PATCH, or
  `"failed"` (with a reason) on an unrecoverable error.
- **Idempotency:** the sync runs daily and re-detects drift. If an item is still
  `pending` when the next sync runs, a fresh item for the same customer may be
  written (ids include `created_at`, so they don't collide). Make execution
  idempotent: re-applying the same patch must be a no-op, and you should skip /
  dedupe items for a customer that has already been reconciled in this cycle.
- After a successful PATCH, the next day's `FetchCapwayEmails` will read the new
  value and the detector will stop flagging it — this is the closed loop that
  confirms the fix landed.

## 8. Reporting

`GeneralSyncReportRepositoryV2` writes a per-run summary to `SYNC_REPORTS_TABLE`.
The `capway.actions.update_customers.sub_action_breakdown` block is a **per-field
tally** (an item updating two fields counts once toward each):

```json
{ "update_email": 3, "update_nin": 1, "update_language": 12, "update_currency": 0 }
```

Use it to monitor drift volume per field over time.

## 9. Checklist for the executor implementation

- [ ] Read `sub_action` as a list; ignore unknown elements.
- [ ] Look up Trinity for `update_email` / `update_nin` target values (don't use the item's `national_id`).
- [ ] Use the market-default table for `update_language` / `update_currency`.
- [ ] PATCH by `capway_customer_id`; fail cleanly when it's missing.
- [ ] Make PATCH application idempotent and dedupe per customer per cycle.
- [ ] Add explicit guardrails for `update_currency`.
- [ ] Advance `status` to `completed` / `failed`.
- [ ] Keep the market-default table in sync with `CapwaySync.Market`.
