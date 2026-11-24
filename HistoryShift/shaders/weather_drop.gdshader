shader_type spatial;
// 雨粒・雪片・水はね（weather_fx.gd の GPUParticles3D の描画）。
// 雨: 落ちる向き（風で斜め）に伸びた細い帯をカメラに向ける。根元ほど透明な筆の線（新海誠調の光る雨筋）。
// 雪: ふわっとした丸。はね: 地面に広がる輪。灯り・空の色を拾って光る（夜は街灯の色）。
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform, fog_disabled;

global uniform float world_night;
global uniform vec4 world_sky_color;
global uniform vec4 world_sun_color;
global uniform vec4 world_weather;

uniform int mode = 0;                  // 0 雨 1 雪 2 はね
uniform vec3 fall_dir = vec3(0.0, -1.0, 0.0);
uniform float width = 0.012;
uniform float length_m = 0.55;
uniform float opacity = 0.55;
uniform vec3 tint : source_color = vec3(0.82, 0.88, 1.0);

varying float v_life;
varying float v_fade;

void vertex() {
	vec3 c = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float sc = length(MODEL_MATRIX[0].xyz);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - c);
	float dist = length(CAMERA_POSITION_WORLD - c);
	// 遠い粒は 1 画素より細くならないように太らせ（その分だけ薄く）、レンズの目の前の粒は消す
	float w = max(width * sc, dist * 0.0021);
	v_fade = (width * sc / w) * 0.6 + 0.4;
	v_fade *= smoothstep(1.2, 3.5, dist);
	vec3 wp;
	if (mode == 0) {
		vec3 axis = normalize(fall_dir);
		vec3 side = normalize(cross(axis, to_cam) + vec3(1e-5));
		wp = c + side * (UV.x - 0.5) * w + axis * (0.5 - UV.y) * length_m * sc;
	} else if (mode == 1) {
		vec3 r = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam) + vec3(1e-5));
		vec3 u = cross(to_cam, r);
		wp = c + (r * (UV.x - 0.5) + u * (0.5 - UV.y)) * max(width * sc, dist * 0.003);
	} else {
		// 地面に寝かせた輪（寿命で広がる）
		wp = c + vec3(UV.x - 0.5, 0.0, UV.y - 0.5) * width * sc * (0.4 + INSTANCE_CUSTOM.y * 1.4);
	}
	v_life = INSTANCE_CUSTOM.y;
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float a = 0.0;
	vec3 col = tint;
	// 空と日の色を拾う（曇天は白っぽく、夜は暗い青＋灯りの色）
	vec3 amb = mix(world_sky_color.rgb * 1.2 + 0.25, vec3(0.75, 0.8, 0.88), world_weather.z * 0.5);
	amb = mix(amb, vec3(0.32, 0.36, 0.5), world_night * 0.7);
	if (mode == 0) {
		float across = 1.0 - abs(UV.x - 0.5) * 2.0;
		float along = smoothstep(0.0, 0.7, 1.0 - UV.y) * smoothstep(1.0, 0.85, 1.0 - UV.y);
		a = smoothstep(0.0, 0.6, across) * along;
		col = tint * amb;
	} else if (mode == 1) {
		float r = length(UV - 0.5) * 2.0;
		a = 1.0 - smoothstep(0.45, 1.0, r);
		col = mix(vec3(1.0), amb, 0.25);
	} else {
		float r = length(UV - 0.5) * 2.0;
		float ring = smoothstep(0.12, 0.0, abs(r - 0.75)) ;
		a = ring * (1.0 - v_life);
		col = tint * amb * 1.1;
	}
	// 稲光の一瞬は雨粒が白く光る
	col += vec3(0.9, 0.95, 1.0) * world_weather.w * 0.8;
	ALBEDO = col;
	ALPHA = clamp(a * opacity * COLOR.a * (mode == 2 ? 1.0 : v_fade), 0.0, 1.0);
}
