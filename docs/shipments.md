# Shipments and repeat despatches

An order can be physically sent more than once: out to the customer, back to us (a
customer return or a Correios bounce), and out again. Each of those trips is a
`Shipment` row. This document explains how those rows relate to the order, which one
is "the" shipment at any moment, and how a re-ship adds a new one without losing the
old ones.

## The model

Every shipment has two attributes that place it on the order:

| Column          | Meaning                                                                  |
| --------------- | ------------------------------------------------------------------------ |
| `direction`     | `outbound` (store → customer) or `inbound` (customer → store, a return)  |
| `superseded_at` | `NULL` while the row is **live**; stamped when a newer despatch replaces it |

The invariant is enforced by the database, not by the application:

```
index_shipments_on_order_id_and_direction_current
  UNIQUE (order_id, direction) WHERE superseded_at IS NULL
```

So an order has **at most one live outbound and one live inbound shipment**, which is
what stops two live pré-postagens fighting over one order, and **any number of
superseded ones**, which are history.

```
Order PG-20260901-0042
├── outbound  superseded 2026-09-10   AD111111111BR   (first trip, came back)
├── inbound   superseded 2026-09-10   AD222222222BR   (customer's return label)
└── outbound  live                    AD333333333BR   (the re-ship)
```

Superseded rows are never deleted or rewritten. They keep their pré-postagem, tracking
code, tracking read-model and `shipment_tracking_events`, exactly as they were when
they were retired.

## Associations

`Order` exposes the rows through three associations:

| Association                | Scope                                       | Used for                               |
| -------------------------- | ------------------------------------------- | -------------------------------------- |
| `shipment`                 | `outbound.current`                          | everything about the current delivery  |
| `return_shipment`          | `inbound.current`                           | the return leg in progress             |
| `past_shipments`           | `superseded.order(:superseded_at)`          | history, backoffice only               |

`shipping_label` and `return_shipping_label` go `through:` the first two, so they also
follow the live row.

Because `order.shipment` means "the live outbound despatch", every existing caller
(mailers, checkout, merge, presenters, the customer's order page) automatically moves
to the new despatch after a re-ship, without knowing re-ships exist. **Keep it that way:
code that needs history reads `past_shipments` explicitly; nothing else should look at
superseded rows.**

`Order#tracked_shipment` picks the row the backoffice label card watches:
`(return_leg? && return_shipment) || shipment`. On the return leg it is the inbound row;
otherwise, including a `returned` order that has no live inbound row (a bounce, or right
after a re-ship), it is the live outbound one.

`Shipment` scopes: `current`, `superseded`, and `superseded?` on the instance.

## Re-shipping (`Shipping::Reship`)

Triggered only by the **Reenviar pedido** button on a `returned` order's backoffice
page (`POST /admin/pedidos/:number/reenvio`, `Admin::ReshipsController`). It is not an
`Admin::OrderActions` entry, so it is unreachable from the bulk bar and from
`Admin::BulkTransition`; buying a label spends money and needs a human looking at the
order.

### Guard

`Shipping::Reship.reshippable?(order)` is true when:

1. the order is `returned`, and
2. it has a live outbound shipment, and
3. that shipment was **created before** the order's latest `status_changes` row with
   `to_status: "returned"`.

Condition 3 is "the live despatch is the one that came back". Right after a click the
order is still `returned` but its live outbound row is brand new, so the guard fails and
a second click cannot buy a second pré-postagem. The next time the guard can pass is
after the new parcel itself comes back.

### What a click does

Inside one transaction, holding `order.lock!` (which serializes concurrent clicks):

1. Re-check the guard.
2. Stamp `superseded_at` on **every live row** of the order, outbound and inbound. The
   inbound row is retired too, so a later second return can open a fresh inbound leg
   (the partial index would otherwise reject it).
3. Create a new outbound row cloning `Shipping::Reship::CLONED` from the old one:
   package dimensions and weight, receiver and address, `service`, `shipping_cents`,
   `delivery_business_days` and `receiver_obs`. The customer is not charged again; the
   price is a copy of what they paid at checkout.

After the commit, `Shipping::EmitLabel.resume(new_shipment)` starts the ordinary label
saga on the new row (see "The label pipeline is a saga" in `CLAUDE.md`).

### Order status and e-mail timing

The click **does not change the order status**. The order stays `returned` while the
pré-postagem and rótulo are bought, because the tracking code does not exist yet and the
customer e-mail needs it.

When the declaração is downloaded, `DownloadDceJob` calls `Leg::OUTBOUND.announce_label`
as it does for any first despatch, which takes the `returned → label_issued` edge in
`Order::TRANSITIONS`. That transition writes a `status_changes` row, which sends the
normal `label_issued` e-mail carrying the new tracking code. From there tracking walks
the new row through `shipped` and `delivered` exactly like a first despatch.

```
returned ──(click: new outbound row, saga starts)──► returned
         ──(DCe downloaded)──────────────────────────► label_issued   e-mail: etiqueta gerada
         ──(tracking)────────────────────────────────► shipped → delivered
```

## Tracking and superseded rows

A superseded row must never influence the order again. Two places enforce it:

- `Shipment.awaiting_tracking` is scoped to `current`, so the poller never schedules a
  sync for a retired row.
- `SyncShipmentJob` returns early for a `superseded?` shipment. This covers a sync that
  was already enqueued when the operator clicked: without it, the old parcel's
  `returned`/`delivered` tracking would reach `OrderProgress` and could walk the
  re-shipped order back to `returned`.

## What each audience sees

**Backoffice order page**

- The label card follows the new row (queued → running → done).
- "Rastreamento Correios" shows the live outbound row.
- "Rastreamento da devolução" shows the live inbound row, so it disappears after a
  re-ship and comes back if a new return is opened.
- Each superseded row gets its own timeline panel under the current ones, titled
  "Envio anterior" (outbound) or "Devolução anterior" (inbound), oldest first
  (`Admin::OrderPresenter#past_trackings`).
- The status history records `Devolvido → Etiqueta emitida` as an automatic step.

**Customer (Meus pedidos, e-mails)**

Only the live despatch. After a re-ship the tracking block, the tracking code and every
subsequent e-mail refer to the new parcel, and the earlier trips are not listed. This
is deliberate: the customer has already been told the order came back, and the order
page shows where the order is now, not where it has been.

## Re-ship vs. re-issuing an expired label

They look similar but are different operations:

|                     | `Shipping::Reship`                        | `Shipping::ReissueLabel`                      |
| ------------------- | ----------------------------------------- | --------------------------------------------- |
| When                | the parcel travelled and came back        | the pré-postagem expired before posting       |
| Order status        | `returned`                                | `label_issued`                                |
| Shipment row        | **new** row; old one superseded           | **same** row, pré-postagem columns cleared    |
| History             | kept (the old trip really happened)       | discarded (nothing was ever posted)           |
| Customer e-mail     | `label_issued` with the new code          | none (the order never leaves `label_issued`)  |

## Querying

```ruby
order.shipment              # live outbound
order.return_shipment       # live inbound, if a return is open
order.past_shipments        # retired rows, oldest first
Shipment.where(order: order).order(:created_at)  # every trip, live and past
```

```sql
-- orders that have been re-shipped at least once
SELECT o.number, count(*) AS past_outbound
FROM shipments s JOIN orders o ON o.id = s.order_id
WHERE s.direction = 0 AND s.superseded_at IS NOT NULL
GROUP BY o.number;
```
