# Nuzi Trade

Trade math for people who would rather move packs than build spreadsheets in the field.

`Nuzi Trade` gives you a cleaner way to browse pack values and time your runs:

- browse routes by origin, pack, destination, and vehicle type
- see destination zone-state status when the live client exposes it
- enter a live percent value to estimate current trade value
- track route times for `Hauler`, `Car`, and `Boat`
- keep a separate route timer window
- save route timings between sessions

## Install

1. Drop the `nuzi-trade` folder into your AAClassic `Addon` directory.
2. Make sure the addon is enabled in game.
3. Click the on-screen trade button to open the browser.

Saved data lives in `nuzi-trade/.data` so route timers and settings survive updates.

## Quick Start

1. Open the trade browser.
2. Pick an origin.
3. Pick a pack and destination.
4. Set the percent you want to evaluate.
5. Switch the vehicle type if needed.
6. Start the route timer if you want to save your actual travel time.

This is much nicer than pretending your memory is a market tool.

## How To

### Browse Trade Values

Use the main window to filter by:

- origin
- pack
- destination
- zone state, shown per destination when available on the live client
- vehicle type
- percent

The results update so you can compare routes without manually recalculating everything.

### Route Timer

The timer window lets you time a specific route and save the result.

Saved route times are remembered per route and per vehicle type, which is the important part if you want the addon to be useful instead of decorative.

### Vehicle Types

`Nuzi Trade` supports:

- `Hauler`
- `Car`
- `Boat`

That keeps timing comparisons honest instead of pretending every pack run happens under identical conditions.

## Notes

- Route timing data is stored separately under `.data/route_times.txt`.
- Destination zone-state data is read from the live client when available and falls back cleanly when it is not.
- The addon uses bundled pack price data, so browsing still works without a live web dependency.
- If you change a route time, it is meant to reflect your route and your vehicle, not universal truth.

## Version

Current version: `0.2.4`
