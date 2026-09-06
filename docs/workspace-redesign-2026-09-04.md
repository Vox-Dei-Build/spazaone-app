# Workspace redesign — local review

The Customer Activity, Products and Recorded Sales screens now give the records
more space, reduce repeated headings and use consistent navy hierarchy, quiet
surfaces and green primary actions.

## Implemented

- **Customer Activity:** one movement summary followed by a chronological list
  grouped by date. Sales and payments have explicit direction labels. Each row
  opens the matching customer ledger. The first 50 entries appear initially;
  Show more adds 50 while reconciliation continues to use all queried entries.
- **Products:** clearer product, price and availability rows; All, Low stock and
  Out of stock filters. Online status no longer hides stock warnings. Filters
  and rows share a scroll view, including on very short screens. Low stock uses
  the existing stock-report threshold of 1–5 units and excludes supplier stock
  and unknown quantities. Selected filters survive ordinary stream rebuilds.
- **Recorded Sales:** date control, one sales total and Record sale action,
  followed by simple entry rows. Details opens the complete comparison and
  product metrics in a scrollable sheet. Stock-purchase difference remains
  distinct from profit. Recording or editing a sale refreshes the selected
  period rather than changing the records to Today under an older date label.
- **Shared controls:** one compact accessible date action; preset ranges can be
  refined safely in the custom picker; large-text tabs have enough height for
  their labels. Activity ranges include the full selected final day.

## Verified locally

Flutter 3.29.2: 76 focused widget and regression tests passed, covering the
redesigned components, 320px screens with 200% text, short catalogue viewports,
landscape layout, filters, timeline ordering/paging, callbacks, date bounds,
empty states and existing customer-summary behavior. Scoped analyzer and
`git diff --check` passed. The release-mode Flutter web preview build passed.
The build retains existing web bootstrap deprecation and unused Cupertino
font warnings.

The actual presentation widgets were also inspected in a local browser:
Activity, Products, low-stock filtering, Recorded Sales and its Details sheet.

## Preview and remaining verification

Run the preview from this checkout using the pinned Flutter SDK:

```sh
flutter run -d web-server -t tool/workspace_design_preview.dart
```

Use the bottom navigation to compare the three redesigned surfaces. This
developer preview contains clearly labelled example data. Dates, stock filters
and sales Details work locally; account, add and record actions show a preview
notice. It does not initialize Firebase or mutate merchant data.

Live authenticated Firestore reads, saving records and native-device rendering
have not been exercised in this task. No deployment or release was performed.
The Activity query still reads all matching entries for reconciliation; the
new display paging limits rendering, not Firestore reads.
