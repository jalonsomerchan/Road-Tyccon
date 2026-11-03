# Design QA · Menú de inicio

**Final result: blocked**

## Comparison target

- Source visual: `/Users/jorgealonso/.codex/generated_images/01a19cfa-496e-7f93-964d-4ef8098e070e/exec-30ce0039-54d2-40e9-9888-39cf3f57cd19.png`
- Source dimensions: 1600 × 1000 px. Intended game viewport: 1280 × 800 px.
- Implementation: Godot title screen in `scripts/visuals.gd`.
- Implementation screenshot: unavailable. The currently running Godot debug view is already in an active game session with a saved region. I left it running to avoid closing the session and triggering its save-on-close behavior.
- State in the design: title screen, no saved game, “Nueva partida” selected, “Cargar partida” disabled.
- Density normalization: none; the selected design preserves a 16:10 composition for the 1280 × 800 viewport. No matching implementation capture was available.

## Visual comparison

- Full view: blocked because the implementation could not be captured in its title-screen state.
- Focused regions: blocked; the generated menu and game-map regions cannot be compared to a current title-screen capture.

## Findings

- [P1] Rendered title-screen comparison is unavailable.
  - Location: complete title screen.
  - Evidence: the selected design is available, but the running game window is displaying an active session, not the title screen.
  - Impact: map framing, menu contrast, text fitting, and button alignment have not been confirmed at runtime.
  - Fix: start a fresh Godot run from the editor to display the title screen, then capture it at 1280 × 800 and compare it with the source visual.

## Fidelity surfaces

- Typography, spacing, colors, and copy are implemented from the selected reference but remain visually unverified in a live title-screen capture.
- The map uses existing terrain, road, building, prop, bridge, and vehicle sprites from the game. No new raster assets were introduced.
- The title options retain their existing keyboard, controller, mouse, save-availability, and confirmation behavior.

## Comparison history

- First implementation. No title-screen capture or comparison iteration was completed.
- Godot's headless editor scan completed with exit code 0. It reported environment warnings about macOS certificate retrieval and writing editor settings outside the workspace.

## Implementation checklist

- [x] Replace the framed map preview with a full-screen pixel-art region.
- [x] Add a dark left menu surface, title hierarchy, selected action, disabled load state, save status, and input hint.
- [x] Reuse the existing pixel-art road, terrain, building, prop, and vehicle sprites.
- [x] Preserve the existing new-game confirmation overlay and title input handling.
- [ ] Capture the title screen at 1280 × 800 and complete the visual comparison.
- [ ] Confirm mouse and keyboard/controller selection in the live title screen.

**Final result: blocked** — a matching rendered title-screen screenshot is required for visual sign-off.
