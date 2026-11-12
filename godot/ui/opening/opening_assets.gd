extends RefCounted
## Procedural textures, shaders and materials for the opening scene. Nothing is loaded from disk and nothing is cached in
## statics (a cached Resource would still be alive at engine shutdown): the scene owns what it builds and frees it with itself.
## Everything is Compatibility-renderer friendly: no screen-space effects, no storage buffers, no compute.

# ------------------------------------------------------------------ textures
## 2 m x 2 m of dressed stone blocks (1 m x 0.5 m) with mortar joints and noise; mipmapped, seamless.
static func stone_texture() -> ImageTexture:
	var n := 128
	var image := Image.create(n, n, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.11
	noise.fractal_octaves = 3
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var grain := FastNoiseLite.new()
	grain.seed = 5
	grain.frequency = 0.55
	for y in n:
		var course := y / 32
		var yy := y % 32
		for x in n:
			var xo := (x + (course % 2) * 32) % n   # alternate courses are offset half a block
			var block := xo / 64
			var xx := xo % 64
			var tone := 0.78 + 0.15 * noise.get_noise_2d(float(x) * 1.0, float(y)) + 0.04 * grain.get_noise_2d(float(x), float(y))
			tone += (fposmod(sin(float(course * 7 + block * 13) * 12.9898) * 43758.5453, 1.0) - 0.5) * 0.10   # per-block tone
			if yy < 2 or xx < 2:
				tone = 0.55 + 0.05 * grain.get_noise_2d(float(x), float(y))   # mortar
			elif yy < 4 or xx < 4:
				tone *= 1.05   # lit edge
			elif yy > 29 or xx > 61:
				tone *= 0.92   # shaded edge
			var v := clampf(tone, 0.0, 1.0)
			image.set_pixel(x, y, Color(v * 1.0, v * 0.985, v * 0.96))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

## Rough rock for the crag and distant hills (large-scale blotches, no joints).
static func rock_texture() -> ImageTexture:
	var n := 128
	var image := Image.create(n, n, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 23
	noise.frequency = 0.045
	noise.fractal_octaves = 4
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var crack := FastNoiseLite.new()
	crack.seed = 3
	crack.noise_type = FastNoiseLite.TYPE_CELLULAR
	crack.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	crack.frequency = 0.05
	for y in n:
		for x in n:
			# wrap-around blend so the texture tiles: sample at the four torus offsets
			var v := 0.70 + 0.30 * noise.get_noise_2d(float(x), float(y))
			var c := crack.get_noise_2d(float(x), float(y))
			v *= 1.0 - 0.35 * clampf(1.0 - absf(c) * 6.0, 0.0, 1.0)
			var g := clampf(v, 0.0, 1.0)
			image.set_pixel(x, y, Color(g, g, g * 1.02))
	# make it seamless by cross-fading the edges
	var seam := 12
	for y in n:
		for s in seam:
			var a := image.get_pixel(s, y)
			var b := image.get_pixel(n - 1 - s, y)
			var w := float(s) / float(seam)
			image.set_pixel(s, y, b.lerp(a, 0.5 + 0.5 * w))
			image.set_pixel(n - 1 - s, y, a.lerp(b, 0.5 + 0.5 * w))
	for x in n:
		for s in seam:
			var a2 := image.get_pixel(x, s)
			var b2 := image.get_pixel(x, n - 1 - s)
			var w2 := float(s) / float(seam)
			image.set_pixel(x, s, b2.lerp(a2, 0.5 + 0.5 * w2))
			image.set_pixel(x, n - 1 - s, a2.lerp(b2, 0.5 + 0.5 * w2))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

## Slate roof tiles: staggered rows with a dark lower edge (u around the cone, v up the slope).
static func slate_texture() -> ImageTexture:
	var n := 64
	var image := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		var row := y / 8
		var yy := y % 8
		for x in n:
			var xo := (x + (row % 2) * 4) % n
			var xx := xo % 8
			var tone := 0.86 - 0.10 * fposmod(sin(float(row * 5 + xo / 8) * 12.9898) * 43758.5453, 1.0)
			if yy >= 6:
				tone *= 0.62   # shadow under the tile above
			if xx == 0:
				tone *= 0.78
			image.set_pixel(x, y, Color(tone, tone, tone * 1.04))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

## Soft radial blob (white centre, black edge) used by the halo and ember quads (alpha comes from the red channel).
static func glow_texture(size: int = 64) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var d := Vector2(float(x) + 0.5 - float(size) * 0.5, float(y) + 0.5 - float(size) * 0.5).length() / (float(size) * 0.5)
			var v := clampf(1.0 - d, 0.0, 1.0)
			v = v * v * (3.0 - 2.0 * v)
			v = pow(v, 1.6)
			image.set_pixel(x, y, Color(v, v, v))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

## Seamless soft noise used for the drifting mist cards.
static func mist_texture(size: int = 96) -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.03
	noise.fractal_octaves = 4
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var image := noise.get_seamless_image(size, size, false, false, 0.2)
	image.convert(Image.FORMAT_RGB8)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

# ------------------------------------------------------------------ shaders
const SKY_SHADER := """
shader_type sky;
uniform vec3 moon_dir = vec3(0.342, 0.407, -0.847);
uniform float t = 0.0;
uniform float clouds = 1.0;
uniform float star_density = 0.93;
uniform vec3 zenith : source_color = vec3(0.006, 0.010, 0.040);
uniform vec3 upper : source_color = vec3(0.020, 0.040, 0.130);
uniform vec3 horizon_col : source_color = vec3(0.40, 0.16, 0.18);
uniform vec3 afterglow : source_color = vec3(1.0, 0.42, 0.14);
uniform vec3 under_col : source_color = vec3(0.02, 0.03, 0.07);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return s;
}
void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	float up = clamp(h, 0.0, 1.0);
	vec3 col = mix(upper, zenith, smoothstep(0.05, 0.75, up));
	col = mix(horizon_col, col, smoothstep(0.0, 0.35, up));
	// afterglow of the set sun low behind the castle (looking toward -Z)
	float az = clamp(dot(normalize(vec2(d.x, d.z) + vec2(0.0001)), vec2(-0.25, -0.97)), 0.0, 1.0);
	col += afterglow * (pow(az, 5.0) * exp(-up * 9.0) * 0.62 + pow(az, 2.0) * exp(-up * 14.0) * 0.12);
	// stars, fading toward the horizon
	vec3 g = d * 70.0;
	vec3 id = floor(g);
	vec3 f = fract(g) - 0.5;
	float r = hash13(id);
	vec3 o = (vec3(hash13(id + 1.3), hash13(id + 7.7), hash13(id + 3.1)) - 0.5) * 0.6;
	float star = smoothstep(0.075, 0.0, length(f - o)) * step(star_density, r);
	float twinkle = 0.65 + 0.35 * sin(t * (0.8 + r * 3.0) + r * 60.0);
	col += vec3(0.85, 0.9, 1.0) * star * (0.5 + 1.8 * fract(r * 31.7)) * twinkle * smoothstep(0.04, 0.45, h);
	// moon: disc with maria, soft halo
	vec3 m = normalize(moon_dir);
	float md = dot(d, m);
	vec3 tu = normalize(cross(m, vec3(0.0, 1.0, 0.0)));
	vec3 tv = cross(tu, m);
	vec2 mp = vec2(dot(d, tu), dot(d, tv)) / 0.0575;
	float rad = length(mp);
	float disc = smoothstep(1.0, 0.94, rad);
	float maria = vnoise(mp * 2.6 + 3.0) * 0.6 + vnoise(mp * 7.0) * 0.4;
	vec3 moon_col = vec3(1.0, 0.95, 0.82) * (0.78 + 0.34 * smoothstep(0.35, 0.7, maria)) * (1.0 - 0.18 * smoothstep(0.5, 1.0, rad));
	float halo = pow(max(md, 0.0), 220.0) * 0.55 + pow(max(md, 0.0), 28.0) * 0.16 + pow(max(md, 0.0), 6.0) * 0.045;
	col += vec3(0.55, 0.66, 1.0) * halo;
	// clouds drift slowly; they catch the moonlight near the moon
	if (clouds > 0.5 && h > 0.0) {
		vec2 uv = d.xz / (h + 0.18) * 0.7 + vec2(t * 0.006, t * 0.0025);
		float c = fbm(uv * 1.7);
		float body = smoothstep(0.46, 0.78, c) * smoothstep(0.0, 0.16, h);
		float rim = smoothstep(0.50, 0.70, c) - smoothstep(0.70, 0.9, c);
		vec3 cloud_col = vec3(0.035, 0.05, 0.11) + vec3(0.55, 0.62, 0.9) * (pow(max(md, 0.0), 6.0) * 0.6 + 0.05) * (0.4 + 0.8 * rim);
		col = mix(col, cloud_col, body * 0.85);
		disc *= 1.0 - body * 0.55;
	}
	col = mix(col, moon_col * 1.6, disc);
	if (h < 0.0) {
		col = mix(horizon_col * 0.55, under_col, smoothstep(0.0, 0.22, -h));
	}
	COLOR = col;
}
"""

## Banners and pennants: waved by the wind in the vertex stage (no CPU), gold border + diamond + swallow-tail drawn in the
## fragment stage. Vertex colour: rgb = cloth colour, a = how much the free end moves; UV.y = 0 at the pole, 1 at the tail.
const BANNER_SHADER := """
shader_type spatial;
render_mode cull_disabled, specular_disabled;
uniform float wind = 1.0;
uniform vec3 trim : source_color = vec3(0.88, 0.68, 0.28);
varying vec3 cloth;
varying float stiff;
void vertex() {
	float along = UV.y;
	float ph = VERTEX.x * 0.37 + VERTEX.z * 0.29;
	float w = sin(TIME * 1.7 + ph + along * 4.2) * 0.62 + sin(TIME * 3.3 + ph * 1.9 + along * 7.5) * 0.2;
	float disp = COLOR.a > 0.5 ? (0.45 + 0.55 * w) : w;   // wall banners only billow outward, pennants fly both ways
	VERTEX += NORMAL * disp * wind * COLOR.a * along * along * 0.9;
	VERTEX.y -= abs(w) * wind * COLOR.a * along * 0.06;
	cloth = COLOR.rgb;
	stiff = COLOR.a;
}
void fragment() {
	vec2 uv = UV;
	vec3 base = cloth;
	if (stiff < 0.5) {
		// pennants are plain; banners carry the heraldry
		ALBEDO = base;
	} else {
		float u = uv.x;
		float v = uv.y;
		vec3 c = base;
		float border = step(u, 0.075) + step(0.925, u) + step(0.965, v);
		float diamond = step(abs(u - 0.5) + abs(v - 0.3) * 0.26, 0.33);
		float inner = step(abs(u - 0.5) + abs(v - 0.3) * 0.26, 0.20);
		float chevron = step(abs(v - (0.62 + abs(u - 0.5) * 0.35)), 0.025);
		c = mix(c, trim, clamp(border + diamond * (1.0 - inner) + chevron, 0.0, 1.0));
		c = mix(c, c * 0.55, inner * diamond);
		ALBEDO = c;
		if (v > 0.86 && abs(u - 0.5) < (v - 0.86) / 0.14 * 0.5) {
			discard;
		}
	}
	ROUGHNESS = 0.92;
}
"""

## Additive billboards: torch / brazier / window halos. Instance transform carries position and size; INSTANCE_CUSTOM.x = flicker
## phase, .y = 1 for flickering sources. `speed` 0 freezes the flicker (reduce motion).
const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float speed = 1.0;
varying vec4 vcol;
void vertex() {
	float ph = INSTANCE_CUSTOM.x;
	float fl = 1.0;
	if (INSTANCE_CUSTOM.y > 0.5) {
		fl = 0.80 + 0.14 * sin(TIME * speed * (5.5 + ph * 3.0) + ph * 31.0) + 0.09 * sin(TIME * speed * 13.0 + ph * 9.0);
	}
	float sc = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX *= sc * (0.94 + 0.10 * fl);
	vcol = COLOR * fl;
}
void fragment() {
	float a = texture(tex, UV).r;
	ALBEDO = vcol.rgb;
	ALPHA = a * vcol.a;
}
"""

## Embers: a particle system evaluated entirely in the vertex stage. Each MultiMesh instance is one ember with a random
## seed in INSTANCE_CUSTOM; its position is a function of TIME, so there is no CPU cost and nothing to leak.
const EMBER_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float speed = 1.0;
uniform float rise = 9.0;
uniform vec3 wind = vec3(1.6, 0.0, -0.9);
varying vec4 vcol;
void vertex() {
	vec4 r = INSTANCE_CUSTOM;
	float life = fract(TIME * speed * (0.045 + 0.05 * r.x) + r.y);
	vec3 off;
	off.y = life * rise * (0.6 + 0.8 * r.z);
	off.x = sin(life * 9.0 + r.x * 30.0) * 0.7 * life + wind.x * life * life * 3.0;
	off.z = cos(life * 7.0 + r.z * 30.0) * 0.7 * life + wind.z * life * life * 3.0;
	vec3 pos = MODEL_MATRIX[3].xyz + off;
	float fade = smoothstep(0.0, 0.06, life) * (1.0 - smoothstep(0.5, 1.0, life));
	float tw = 0.7 + 0.3 * sin(TIME * 9.0 * (0.5 + r.x) + r.z * 40.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], vec4(pos, 1.0));
	VERTEX *= 0.16 * (0.55 + 0.9 * r.x) * fade;
	vcol = vec4(mix(vec3(1.0, 0.78, 0.34), vec3(1.0, 0.24, 0.05), life), fade * tw);
}
void fragment() {
	float a = texture(tex, UV).r;
	ALBEDO = vcol.rgb * 1.6;
	ALPHA = a * vcol.a;
}
"""

## Flames: a procedural teardrop billboard anchored at its base. INSTANCE_CUSTOM.x = phase; instance scale = height in metres.
const FLAME_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
uniform float speed = 1.0;
varying vec2 vuv;
varying float vph;
void vertex() {
	vph = INSTANCE_CUSTOM.x;
	float sc = length(MODEL_MATRIX[0].xyz);
	float fl = 0.88 + 0.12 * sin(TIME * speed * (9.0 + vph * 5.0) + vph * 40.0) + 0.06 * sin(TIME * speed * 23.0 + vph * 7.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	vec3 v = VERTEX;
	v.y += 0.5;
	v.x *= 0.62;
	VERTEX = v * sc * (0.92 + 0.16 * fl);
	vuv = UV;
}
void fragment() {
	float y = 1.0 - vuv.y;
	float sway = sin(y * 7.0 + TIME * speed * (6.0 + vph * 3.0) + vph * 20.0) * 0.10 * y;
	float x = (vuv.x - 0.5 + sway) * 2.0;
	float width = pow(max(1.0 - y, 0.0), 0.65) * (0.55 + 0.45 * smoothstep(0.0, 0.3, y));
	float body = smoothstep(width, width * 0.35, abs(x)) * smoothstep(0.0, 0.05, y);
	float core = smoothstep(width * 0.55, 0.0, abs(x)) * (1.0 - y);
	vec3 col = mix(vec3(1.0, 0.28, 0.04), vec3(1.0, 0.82, 0.35), core);
	ALBEDO = col * (0.9 + 0.5 * core);
	ALPHA = body * 0.95;
}
"""

## Low mist cards: big soft quads drifting slowly through the valley (distance fog alone is flat).
const MIST_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(0.22, 0.28, 0.46, 0.5);
uniform vec2 drift = vec2(0.004, 0.0015);
uniform float speed = 1.0;
varying float dist;
void vertex() {
	dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}
void fragment() {
	float n = texture(tex, UV * 3.0 + drift * TIME * speed).r;
	float n2 = texture(tex, UV * 7.0 - drift * TIME * speed * 1.7 + 0.37).r;
	float a = smoothstep(0.30, 0.78, n * 0.65 + n2 * 0.35);
	float edge = smoothstep(0.0, 0.18, UV.x) * smoothstep(1.0, 0.82, UV.x) * smoothstep(0.0, 0.18, UV.y) * smoothstep(1.0, 0.82, UV.y);
	ALBEDO = tint.rgb;
	ALPHA = a * tint.a * edge * smoothstep(45.0, 170.0, dist);
}
"""

static func shader(code: String) -> Shader:
	var value := Shader.new()
	value.code = code
	return value

# ------------------------------------------------------------------ materials
static func textured(texture: Texture2D, roughness: float, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.albedo_color = tint
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = roughness
	material.metallic = 0.0
	material.metallic_specular = 0.25
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return material

static func plain(roughness: float, emission: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = roughness
	material.metallic_specular = 0.2
	if emission:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

static func shader_material(code: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader(code)
	return material
