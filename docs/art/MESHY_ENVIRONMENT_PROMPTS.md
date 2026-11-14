# Peepeechess — environment image prompts for Meshy

Use the player's supplied castle/chess reference images for all three concepts. Create the pit, board and surroundings as separate assets. These are visual concepts: exact grid, hole, collisions and scale will be aligned in Godot against the existing game systems. Do not replace gameplay hitboxes, the trapdoor or the ladder with AI-generated geometry.

## 1. Underground combat pit

> A realistic fantasy-medieval underground dueling chamber beneath a castle chessboard, designed as a game environment. Circular stone arena with a flat, unobstructed combat floor, warm weathered sandstone and darker worn flagstones, four substantial round stone pillars arranged symmetrically around the outside of the fighting area, arched alcoves, iron torch sconces, subtle crimson and navy heraldic banners, and a small square shaft opening high in the center of the ceiling with a wooden ladder leading up. Cinematic warm torchlight balanced with cool ambient light, readable silhouettes, grounded proportions, detailed masonry, premium medieval fantasy game art. Show the whole chamber from a slightly elevated three-quarter angle, with its architecture clearly separated and the floor fully visible. No people, weapons, furniture or rubble in the fighting area; no text, UI, dramatic fog or baked-in shadows.

Existing layout reference: 7.1 m inner wall radius, four pillars at (±3.4, ±3.4) m with 0.55 m radius, 1 m square shaft, chamber ceiling bottom 5 m above the floor. Treat the generated image as art direction, not a reliable dimensional blueprint; fit separate visual sections to these constraints when integrating.

## 2. Chessboard and frame

> A single square medieval fantasy chessboard built into a castle courtyard floor, shown from a high three-quarter view. Exactly eight by eight equal, precisely aligned squares, alternating light warm limestone and dark muted blue-gray stone, with clear but restrained contrast. A thin, elegant carved stone frame with subtle worn gold inlay surrounds the board; the playing surface is level and completely flat. Realistic weathered stone, fine handcrafted edge detail, cinematic but even lighting, premium game-ready asset concept. No chess pieces, characters, raised decorations on the squares, text, numbers, letters, environment, perspective distortion or baked shadows.

Existing layout reference: 8 × 8 one-meter squares; outer frame approximately 8.8 m square. Keep the 64 existing separate tiles and their interactive trapdoor: use the generated asset for the frame/materials and adapt visual geometry as needed. Image generators may not produce a correct grid.

## 3. Courtyard surroundings

> A realistic fantasy-medieval castle courtyard environment surrounding a large empty square space reserved for a chessboard. Warm aged sandstone walls, open stone arcades and arches, four distant round towers with slate roofs and crenellations, modest crimson and navy banners, climbing ivy, cypress trees, stone planters and a few wall-mounted torches. Paved stone ground connects naturally to the board area. A sophisticated, atmospheric castle inspired by realistic medieval architecture, warm cinematic daylight with soft cool ambient fill, rich but believable detail. Show a clear high three-quarter overview with the empty center completely unobstructed and all decorative structures set well outside it. No chessboard, pieces, people, floating objects, text or UI.

Existing layout reference: keep the 8.8 m board frame and playable squares clear; avoid decorative collision and split walls/towers into independently fadeable sections. Retain room for the camera, trapdoor sequence and ladder.
