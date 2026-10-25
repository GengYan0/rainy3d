package rainy.render3d.stage3d;

import rainy.render3d.core.R3DShader;

class Stage3DShaders
{
	public static var FLOOR_VERT:String = '
#include "r3d/inc/r3d.glsl"
#include "r3d/inc/material.glsl"
#include "r3d/inc/mesh.glsl"

uniform mat4 uMirrorVP;

varying vec4 vMirrorUVW;
varying vec4 vFloorColor;

void main(void)
{
	r3d_TexCoordv = r3d_TexCoord * uUvScale + uUvOffset;
	r3d_Colorv = r3d_Color * r3d_ColorI * uTint;
	vFloorColor = r3d_Colorv;
	vec4 lp = r3d_skin() * vec4(r3d_Position.xyz, 1.0);
	vec4 wp = r3d_world() * lp;
	gl_Position = uProj * uView * wp;
	vMirrorUVW = uMirrorVP * wp;
}';

	public static var FLOOR_FRAG:String = '
#include "r3d/inc/r3d.glsl"
#include "r3d/inc/material.glsl"

uniform sampler2D uMirrorMap;
uniform float uMirrorStr;
uniform vec3 uMirrorTint;

varying vec4 vMirrorUVW;
varying vec4 vFloorColor;

void main()
{
	vec4 base = texture2D(uAlbedoMap, r3d_TexCoordv) * vFloorColor;
	vec2 uv = vMirrorUVW.xy / max(0.0001, vMirrorUVW.w) * 0.5 + 0.5;
	vec3 refl = texture2D(uMirrorMap, uv).rgb * uMirrorTint;
	float k = clamp(uMirrorStr, 0.0, 1.0);
	vec3 col = mix(base.rgb, refl, k);
	gl_FragData[0] = vec4(col, 1.0);
}';

	public static var ENV_VERT:String = '
#include "r3d/inc/r3d.glsl"
#include "r3d/inc/material.glsl"
#include "r3d/inc/mesh.glsl"

varying vec3 vEnvN;
varying vec3 vEnvP;
varying vec2 vEnvUV;
varying vec4 vEnvColor;

void main(void)
{
	r3d_TexCoordv = r3d_TexCoord * uUvScale + uUvOffset;
	r3d_Colorv = r3d_Color * r3d_ColorI * uTint;
	vEnvUV = r3d_TexCoordv;
	vEnvColor = r3d_Colorv;
	vec4 lp = r3d_skin() * vec4(r3d_Position.xyz, 1.0);
	vec4 wp = r3d_world() * lp;
	vEnvP = wp.xyz;
	vEnvN = normalize(r3d_basis3(r3d_world()) * r3d_Normal);
	gl_Position = uProj * uView * wp;
}';

	public static var ENV_FRAG:String = '
#include "r3d/inc/r3d.glsl"
#include "r3d/inc/material.glsl"

uniform sampler2D uMirrorMap;
uniform float uMirrorStr;
uniform vec3 uMirrorTint;

varying vec3 vEnvN;
varying vec3 vEnvP;
varying vec2 vEnvUV;
varying vec4 vEnvColor;

void main()
{
	vec3 n = normalize(vEnvN);
	vec3 v = normalize(vEnvP - r3d_cameraPos());
	vec3 r = reflect(v, n);
	vec2 uv = vec2(atan(r.z, r.x) / 6.2831853 + 0.5, acos(clamp(r.y, -1.0, 1.0)) / 3.14159265);
	vec3 refl = texture2D(uMirrorMap, uv).rgb * uMirrorTint;
	vec3 base = texture2D(uAlbedoMap, vEnvUV).rgb * vEnvColor.rgb;
	float fres = pow(1.0 - clamp(dot(-v, n), 0.0, 1.0), 2.0);
	float k = clamp(uMirrorStr * (0.42 + fres * 0.65), 0.0, 1.0);
	gl_FragData[0] = vec4(mix(base, refl, k), 1.0);
}';

	public static function floorShader():R3DShader
	{
		return R3DShader.fromSources(FLOOR_VERT, FLOOR_FRAG, ["MIRROR_FLOOR"]);
	}

	public static function envShader():R3DShader
	{
		return R3DShader.fromSources(ENV_VERT, ENV_FRAG, ["MIRROR_ENV"]);
	}
}
