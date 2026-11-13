# Cinematic menu pass (UI and atmosphere)

Done (godot/ui/theme/title_screen.gd, backdrop.gd):
- **Mode identities.** Classic (steel blue), Battle (ember red) and Online (azure) each have a one-line promise shown under the menu
  while the button is hovered or focused (mouse, touch, pad), and the 3D scene gets a soft coloured wash at its edges that eases in
  and out (0.35 s; jumps when "reduce motion" is on).
- **Vignette.** A restrained radial corner darkening over the 3D castle so the eye rests on the castle and the menu.
- Screenshot: `docs/ui/cinematic/menu-online-identity.png` (software GL).

Already present and kept: moonlit castle, embers, fog, flames, glow, quality tiers, opening camera glide.

Not done (time-box): staggered button entry, mouse parallax, per-mode emblems, new page transitions, board/pit lighting changes.
Audio and combat VFX/camera are other forks' areas.

Tests: `npm run test:ui` theme 234, layout 182, overlap 551, opening 151, screen mode 62, application 85, views 345 all 0 failures.
The ONLINE UI step fails on one check ("real network touch duel commits once and returns to both boards") with and without these
changes: it comes from the merged battle-pacing checkpoint, not from this pass.
