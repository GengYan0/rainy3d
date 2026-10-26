package rainy.render3d.core;

import rainy.render3d.core.R3DMaterial;
import rainy.render3d.core.R3DShader;

class R3DShaders
{

	public static var FULLSCREEN_VERT:String = '
#include "r3d/inc/r3d.glsl"
#include "r3d/inc/mesh.glsl"

void main(void)
{
	r3d_TexCoordv = r3d_TexCoord;
	r3d_Colorv = vec4(1.0);
	gl_Position = vec4(r3d_Position.xy, 0.0, 1.0);
}';

	public static var UNLIT_VERT:String = '
#include "r3d/inc/r3d.glsl"
#include "r3d/inc/material.glsl"
#include "r3d/inc/mesh.glsl"

void main(void)
{
	r3d_TexCoordv = r3d_TexCoord * uUvScale + uUvOffset;
	r3d_Colorv = r3d_Color * r3d_ColorI * uTint;
	vec4 lp = r3d_skin() * vec4(r3d_Position.xyz, 1.0);
	gl_Position = uProj * uView * r3d_world() * lp;
}';

	public static var UNLIT_FRAG:String = '
#include "r3d/inc/r3d.glsl"
#include "r3d/inc/material.glsl"

void main() {
	#ifdef SOLID
	vec4 albedo = r3d_Colorv;
	#else
	vec4 albedo = texture2D(uAlbedoMap, r3d_TexCoordv) * r3d_Colorv;
	if (albedo.a < 0.35) discard;
	#endif
	gl_FragData[0] = albedo;
}';

	public static var LIT_VERT:String = '
#include "r3d/inc/r3d.glsl"
#include "r3d/inc/material.glsl"
#include "r3d/inc/mesh.glsl"

varying vec3 vWorldNormal;
varying vec3 vWorldTangent;
varying vec3 vWorldBitangent;
varying vec3 vWorldPos;

void main(void)
{
	r3d_TexCoordv = r3d_TexCoord * uUvScale + uUvOffset;
	r3d_Colorv = r3d_Color * r3d_ColorI * uTint;

	mat4 worldTransform = r3d_world();
	mat4 sk = r3d_skin();
	vec4 lp = sk * vec4(r3d_Position.xyz, 1.0);
	vec3 wp = (worldTransform * lp).xyz;
	mat3 worldBasis = r3d_worldBasis();
	mat3 skinBasis = r3d_basis3(sk);
	vec3 n = normalize(worldBasis * (skinBasis * r3d_Normal));
	vec3 t = worldBasis * (skinBasis * r3d_Tangent.xyz);
	float sgn = r3d_Tangent.w;
	float tl = length(t);
	if (tl < 0.0001)
	{
		vec3 ref = abs(n.y) > 0.99 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
		t = normalize(cross(ref, n));
		sgn = 1.0;
	}
	else
	{
		t = t / tl;
	}
	t = normalize(t - n * dot(n, t));

	vWorldPos = wp;
	vWorldNormal = n;
	vWorldTangent = t;
	vWorldBitangent = cross(n, t) * sgn;

	gl_Position = uProj * uView * worldTransform * lp;
}';

	public static var LIT_FRAG:String = '
#include "r3d/inc/r3d.glsl"
#include "r3d/inc/material.glsl"
#include "r3d/inc/lighting.glsl"

varying vec3 vWorldNormal;
varying vec3 vWorldTangent;
varying vec3 vWorldBitangent;
varying vec3 vWorldPos;

uniform float uGrain;
uniform float uBump;

void main()
{
	vec2 uv = r3d_TexCoordv;
	vec3 t1 = texture2D(uAlbedoMap, uv).rgb * 2.0;
	vec3 t2 = texture2D(uAlbedoMap, uv * 0.23 + vec2(0.37, 0.61)).rgb * 2.0;
	vec3 tex = mix(vec3(1.0), t1 * 0.85 + t2 * 0.15, uGrain);
	vec3 albedo = uAlbedo * max(tex, vec3(0.05));

	vec3 tx = texture2D(uNormalMap, uv).xyz * 2.0 - 1.0;
	vec3 nTex = r3d_tangentNormal(tx, uBump);

	vec3 Nw = normalize(vWorldNormal);
	vec3 Tw = normalize(vWorldTangent - Nw * dot(vWorldTangent, Nw));
	vec3 Bw = normalize(vWorldBitangent);
	vec3 N = normalize(Tw * nTex.x + Bw * nTex.y + Nw * nTex.z);

	vec3 V = normalize(r3d_cameraPos() - vWorldPos);
	vec3 col = r3d_shade(N, V, vWorldPos, albedo, uSpecular, uRoughness, uMetallic);
	col = r3d_fog(col, vWorldPos);
	gl_FragData[0] = vec4(col, 1.0);
}';

	public static var LIT_NAME:String = "r3d_lit";
	public static var UNLIT_NAME:String = "r3d_unlit";

	public static var SHADOW_VERT:String = '
#include "r3d/inc/r3d.glsl"
#include "r3d/inc/mesh.glsl"

uniform mat4 uLightVP;

void main(void)
{
	vec4 lp = r3d_skin() * vec4(r3d_Position.xyz, 1.0);
	gl_Position = uLightVP * r3d_world() * lp;
}';

	public static var SHADOW_FRAG:String = '
#include "r3d/inc/r3d.glsl"
#include "r3d/inc/shadow.glsl"

void main()
{
	gl_FragData[0] = r3d_packDepth(gl_FragCoord.z);
}';

	public static var SHADOW_NAME:String = "r3d_shadow";

	public static function shadowShader():R3DShader
	{
		return R3DShader.fromSources(SHADOW_VERT, SHADOW_FRAG, ["SHADOW_PASS"]);
	}

	public static var INSTANCE_FLAG:String = "VERTEX_INSTANCE";
	public static var INSTANCE_COLOR_FLAG:String = "INSTANCE_COLOR";
	public static var SKINNED_FLAG:String = "SKINNED";

	public static function skinnedLit(?flags:Array<String>):R3DShader
	{
		var f:Array<String> = [SKINNED_FLAG];
		if (flags != null)
			for (x in flags)
				f.push(x);
		return R3DShader.fromSources(LIT_VERT, LIT_FRAG, f);
	}

	public static function skinnedUnlit(solid:Bool = false, ?extra:Array<String>):R3DShader
	{
		var f:Array<String> = [SKINNED_FLAG];
		if (solid) f.push("SOLID");
		if (extra != null)
			for (x in extra)
				f.push(x);
		return R3DShader.fromSources(UNLIT_VERT, UNLIT_FRAG, f);
	}

	public static function unlitShader(?flags:Array<String>):R3DShader
	{
		return R3DShader.fromSources(UNLIT_VERT, UNLIT_FRAG, flags);
	}

	public static function litShader(?flags:Array<String>):R3DShader
	{
		return R3DShader.fromSources(LIT_VERT, LIT_FRAG, flags);
	}

	public static function instFlags(solid:Bool = false, color:Bool = false, ?extra:Array<String>):Array<String>
	{
		var f:Array<String> = [INSTANCE_FLAG];
		if (solid) f.push("SOLID");
		if (color) f.push(INSTANCE_COLOR_FLAG);
		if (extra != null)
			for (e in extra)
				f.push(e);
		return f;
	}

	public static function instLitShader(?flags:Array<String>):R3DShader
	{
		return R3DShader.fromSources(LIT_VERT, LIT_FRAG, flags == null ? instFlags() : flags);
	}

	public static function instUnlitShader(solid:Bool = false, color:Bool = false):R3DShader
	{
		return R3DShader.fromSources(UNLIT_VERT, UNLIT_FRAG, instFlags(solid, color));
	}

	public static function lineShader():R3DShader
	{
		return R3DShader.fromSources(UNLIT_VERT, UNLIT_FRAG, ["SOLID", "VERTEX_COLORS"]);
	}

	public static function defaultMaterials():Array<R3DMaterial>
	{
		var l = litShader();
		var u = unlitShader();
		var solid = unlitShader(["SOLID"]);
		var out:Array<R3DMaterial> = [];
		var m = new R3DMaterial(l);
		m.name = "默认受光材质";
		out.push(m);
		var m2 = new R3DMaterial(u);
		m2.name = "默认无光材质";
		out.push(m2);
		var m3 = new R3DMaterial(solid);
		m3.name = "纯色材质";
		out.push(m3);
		return out;
	}
}
