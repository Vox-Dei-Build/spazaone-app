# Spaza One design directions

A local concept comparison of the three choices originally offered:

1. **Clean and approachable — chosen direction:** calm layouts, friendly rounded details.
2. Bold and distinctive — stronger type and more brand character.
3. Minimal and compact — prioritise speed and dense information.

Login, Products, Activity and Recorded sales share example data across all
three directions. Search, stock filters, detail sheets and demo phone/OTP forms
operate locally. Clean and approachable is the user's chosen direction and is
being applied through the Flutter app's shared components. Bold and distinctive
and Minimal and compact remain available as comparison concepts. This standalone
folder does not modify the Flutter app; its production-component preview is
served separately on port 8765.

Run from the repository root:

```sh
python3 -m http.server 8766 --bind 127.0.0.1 --directory tool/design_directions
```

Open http://127.0.0.1:8766/ . The query parameters `view` (all, approachable,
bold, compact) and `screen` (login, products, activity, sales) support direct links.
No external dependencies or service calls are used. Logo and licensed Roboto
fonts were copied from the project's existing assets; the font license is
included with them.

Before the approachable selection, all 12 screen/direction combinations were
verified to render without horizontal overflow at the available local browser
width, plus low-stock filtering, sales-details values and demo OTP continuation.
JavaScript syntax checked with Node. No full
Flutter suite was rerun for that initial comparison because it only added the
standalone preview. The selection update changes concept copy only; its
JavaScript syntax and whitespace diff are checked separately from the Flutter
implementation.
