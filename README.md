# LiteBridge

A light, native macOS file browser for big previews, quick culling, ratings and tags.
Built with SwiftUI. Uses macOS Quick Look, so PSD, AI, PDF, JPG, PNG, RAW etc. preview natively.

- Click = select, Cmd-click / Shift-click = multi-select, double-click = open in default app
- Arrow keys = navigate, Delete = move to Trash, Cmd+Z = undo, 0-5 = star rating
- Drag files onto a subfolder in the sidebar to move them
- Tags are real Finder tags. Ratings are stored in the Spotlight star-rating attribute.

Build: see `.github/workflows/build.yml` (runs on macos-15-intel).
