package rainy.render3d.core;

import lime.graphics.opengl.GL;
import openfl.display3D.Context3DVertexBufferFormat;

enum abstract R3DPresentMode(Int) from Int to Int
{
	var OFF = 0;

	var BILINEAR = 1;

	var BOX = 2;

	var FSR = 3;
	/** `FSR` followed by a contrast adaptive sharpen pass. */
	var FSR_SHARP = 4;

	public function label():String
	{
		return switch (cast this : R3DPresentMode)
		{
			case OFF: 'off';
			case BILINEAR: 'bilinear';
			case BOX: 'box';
			case FSR: 'fsr';
			case FSR_SHARP: 'fsr+rcas';
		}
	}

	@:from public static function of(s:String):R3DPresentMode
	{
		if (s == null) return OFF;
		return switch (s.toLowerCase())
		{
			case 'bilinear' | 'linear': BILINEAR;
			case 'box' | 'area' | 'ssaa': BOX;
			case 'fsr' | 'easu': FSR;
			case 'fsr_sharp' | 'fsr+rcas' | 'rcas': FSR_SHARP;
			default: OFF;
		}
	}
}

class R3DPresent
{
	public static var mode:R3DPresentMode = R3DPresentMode.FSR;

	public static var sharpness:Float = 0.2;

	public var lastMode:R3DPresentMode = R3DPresentMode.OFF;
	public var lastSrcW:Int = 0;
	public var lastSrcH:Int = 0;
	public var lastDstW:Int = 0;
	public var lastDstH:Int = 0;
	public var passes:Int = 0;

	var dst:R3DTexture = null;
	var mid:R3DTexture = null;
	var dstW:Int = 0;
	var dstH:Int = 0;

	var ownedDst:Bool = false;
	var midW:Int = 0;
	var midH:Int = 0;
	var shaders:Map<String, R3DShader> = new Map();
	var failed:Map<String, Bool> = new Map();

	public function new() {}

	public function apply(src:R3DTexture, w:Int, h:Int, ?into:R3DTexture):R3DTexture
	{
		lastSrcW = src == null ? 0 : src.width;
		lastSrcH = src == null ? 0 : src.height;
		lastDstW = w;
		lastDstH = h;
		passes = 0;
		lastMode = R3DPresentMode.OFF;

		if (src == null || w < 2 || h < 2) return src;
		var m:R3DPresentMode = mode;
		if (m == R3DPresentMode.OFF) return src;
		if (src.width == w && src.height == h && m != R3DPresentMode.FSR_SHARP) return src;

		if (into != null)
		{
			if (into.width != w || into.height != h || into.disposed) return src;
			dst = into;
			dstW = w;
			dstH = h;
			ownedDst = false;
		}
		else if (!ensureDst(w, h)) return src;
		if (!ensureQuad()) return src;

		if (m == R3DPresentMode.FSR_SHARP)
		{
			var half = w >= 2 && h >= 2 ? ensureMid(w, h) : false;
			if (half)
			{
				if (!runPass('fsr', src, mid, src.width, src.height, w, h)) return src;
				passes++;
				if (!runPass('rcas', mid, dst, w, h, w, h))
				{
					// The sharpening pass failed but the reconstruction already landed in
					// `mid`; showing it beats dropping back to the raw source.
					lastMode = R3DPresentMode.FSR;
					return mid;
				}
				passes++;
				lastMode = R3DPresentMode.FSR_SHARP;
				return dst;
			}
			m = R3DPresentMode.FSR;
		}

		var key:String = switch (m)
		{
			case R3DPresentMode.BOX: 'box';
			case R3DPresentMode.BILINEAR: 'bilinear';
			default: 'fsr';
		}
		if (!runPass(key, src, dst, src.width, src.height, w, h)) return src;
		passes++;
		lastMode = m;
		return dst;
	}

	public function invalidate():Void
	{
		// `dst` may be a caller owned texture; dropping the reference is enough and
		// disposing it here would delete the scene's output surface.
		if (dst != null && ownedDst) dst.dispose();
		if (mid != null) mid.dispose();
		dst = null;
		ownedDst = false;
		mid = null;
		dstW = 0;
		dstH = 0;
		midW = 0;
		midH = 0;
	}

	public function dispose():Void
	{
		invalidate();
		for (k in shaders.keys())
		{
			var s = shaders.get(k);
			if (s != null) s.dispose();
		}
		shaders = new Map();
		failed = new Map();
	}

	public function info():String
	{
		return 'present ' + lastMode.label() + ' ' + lastSrcW + 'x' + lastSrcH + ' -> '
			+ lastDstW + 'x' + lastDstH + ' passes=' + passes;
	}

	function ensureDst(w:Int, h:Int):Bool
	{
		if (dst != null && dstW == w && dstH == h && !dst.disposed) return true;
		if (dst != null) dst.dispose();
		dst = R3DTexture.create(w, h);
		if (dst == null)
		{
			dstW = 0;
			dstH = 0;
			return false;
		}
		dstW = w;
		dstH = h;
		ownedDst = true;
		return true;
	}

	function ensureMid(w:Int, h:Int):Bool
	{
		if (mid != null && midW == w && midH == h && !mid.disposed) return true;
		if (mid != null) mid.dispose();
		mid = R3DTexture.create(w, h);
		if (mid == null)
		{
			midW = 0;
			midH = 0;
			return false;
		}
		midW = w;
		midH = h;
		return true;
	}

	function ensureQuad():Bool
	{
		return R3DFullscreen.mesh() != null;
	}

	function shaderFor(key:String):R3DShader
	{
		if (failed.exists(key)) return null;
		var s = shaders.get(key);
		if (s != null) return s;
		var frag:String = switch (key)
		{
			case 'box': BOX_FRAG;
			case 'bilinear': BILINEAR_FRAG;
			case 'rcas': RCAS_FRAG;
			default: FSR_FRAG;
		};
		s = R3DShader.fromSources(R3DShaders.UNLIT_VERT, frag, ["SOLID"]);
		if (s == null || s.failed)
		{
			failed.set(key, true);
			return null;
		}
		shaders.set(key, s);
		return s;
	}

	function runPass(key:String, src:R3DTexture, dstTex:R3DTexture, srcW:Int, srcH:Int, dstWi:Int, dstHi:Int):Bool
	{
		var ctx = R3DShader.context;
		if (ctx == null || src == null || dstTex == null) return false;
		var sh = shaderFor(key);
		if (sh == null) return false;

		@:privateAccess
		{
			ctx.__state.renderToTexture = dstTex.glTexture;
			ctx.__state.renderToTextureDepthStencil = false;
			ctx.__flushGLFramebuffer();
		}
		GL.viewport(0, 0, dstWi, dstHi);
		R3DGLStateCache.invalidateOpenfl();
		GL.disable(GL.DEPTH_TEST);
		GL.disable(GL.CULL_FACE);
		GL.disable(GL.BLEND);
		GL.clearColor(0.0, 0.0, 0.0, 1.0);
		GL.clear(GL.COLOR_BUFFER_BIT);

		R3DGLStateCache.program = null;
		R3DShader.invalidate();
		sh.bind();
		if (ident == null) ident = R3DMat4.identity();
		sh.setMat4("uProj", ident);
		sh.setMat4("uView", ident);
		sh.setMat4("uModel", ident);
		sh.setVec2("iResolution", dstWi, dstHi);
		// Source and destination sizes are separate uniforms: every kernel below needs the
		// source texel to place its taps and the destination texel to know the output
		// footprint, and deriving one from the other breaks as soon as they differ.
		sh.setVec2("uSrcSize", srcW, srcH);
		sh.setVec2("uDstSize", dstWi, dstHi);
		sh.setFloat("uSharpness", Math.max(0.0, Math.min(1.0, sharpness)));

		R3DScene.bindTexture(0, src);
		sh.setTexture("uSrc", 0);

		return R3DFullscreen.draw(ctx, sh);
	}

	static var ident:Array<Float> = null;

	static var BILINEAR_FRAG:String = '
#include "r3d/inc/r3d.glsl"
#include "r3d/inc/material.glsl"

uniform sampler2D uSrc;

void main()
{
	gl_FragData[0] = texture2D(uSrc, r3d_TexCoordv);
}';

	static var BOX_FRAG:String = '
#include "r3d/inc/r3d.glsl"
#include "r3d/inc/material.glsl"

uniform sampler2D uSrc;
uniform vec2 uSrcSize;

// Box filter for supersampled sources. Each destination pixel covers
// `uSrcSize / uDstSize` source pixels, so the footprint is measured rather than assumed
// and a 2x2 or 3x3 factor both come out as a true average instead of a guess.
void main()
{
	vec2 uv = r3d_TexCoordv;
	vec2 span = uSrcSize / uDstSize;
	vec2 step = 1.0 / uSrcSize;

	// Five taps per axis covers a factor of four with the endpoints clamped; wider
	// factors fall back to a strided sample which is still an unbiased average.
	int nx = int(clamp(floor(span.x), 1.0, 5.0));
	int ny = int(int(clamp(floor(span.y), 1.0, 5.0)));
	int mx = (nx - 1) / 2;
	int my = (ny - 1) / 2;

	vec4 acc = vec4(0.0);
	float n = 0.0;
	for (int y = -2; y <= 2; y++)
	{
		if (y < -my || y > (ny - 1 - my)) continue;
		for (int x = -2; x <= 2; x++)
		{
			if (x < -mx || x > (nx - 1 - mx)) continue;
			acc += texture2D(uSrc, uv + vec2(float(x), float(y)) * step);
			n += 1.0;
		}
	}
	gl_FragData[0] = acc / max(n, 1.0);
}';

	static var FSR_FRAG:String = '
#include "r3d/inc/r3d.glsl"
#include "r3d/inc/material.glsl"

uniform sampler2D uSrc;
uniform vec2 uSrcSize;
uniform vec2 uDstSize;

float luma(vec3 c)
{
	return dot(c, vec3(0.299, 0.587, 0.114));
}

vec3 tap(vec2 uv)
{
	return texture2D(uSrc, uv).rgb;
}

// Lanczos-2 window. Used instead of a tent because the point of this pass is to keep
// edge slope: a tent already lost that in the bilinear path we are replacing.
float lanczos2(float x)
{
	x = abs(x);
	if (x < 1e-5) return 1.0;
	if (x >= 2.0) return 0.0;
	float px = 3.14159265 * x;
	return (sin(px) / px) * (sin(px * 0.5) / (px * 0.5));
}

void main()
{
	vec2 uv = r3d_TexCoordv;
	vec2 texel = 1.0 / uSrcSize;
	vec2 scale = uSrcSize / uDstSize;

	// Structure tensor over the 3x3 neighbourhood. Its dominant eigenvector is the local
	// edge normal, so the kernel below can be stretched along the edge and narrowed
	// across it instead of being isotropic.
	float gx = 0.0;
	float gy = 0.0;
	float c0 = luma(tap(uv));
	for (int y = -1; y <= 1; y++)
	{
		for (int x = -1; x <= 1; x++)
		{
			if (x == 0 && y == 0) continue;
			float l = luma(tap(uv + vec2(float(x), float(y)) * texel));
			// Sobel weights folded into the accumulation.
			float wx = float(x) * (1.0 + float(y == 0)) ;
			float wy = float(y) * (1.0 + float(x == 0)) ;
			gx += (l - c0) * wx;
			gy += (l - c0) * wy;
		}
	}

	float gmag = length(vec2(gx, gy));
	vec2 dir = gmag > 1e-5 ? vec2(gx, gy) / gmag : vec2(0.0, 0.0);
	vec2 perp = vec2(-dir.y, dir.x);

	// Anisotropy is bounded: full stretch along a perfectly straight edge would smear
	// text and fine texture, so the ratio is capped at 2.5:1.
	float aniso = 1.0 + clamp(gmag * 12.0, 0.0, 1.5);
	vec2 axisAlong = dir / max(aniso, 1.0);
	vec2 axisAcross = perp * aniso;

	// Four taps along each axis, two per direction. Total sixteen samples including the
	// centre, which is the same budget the hardware path uses for a 4x4 gather.
	vec4 acc = vec4(c0, 1.0) * 4.0;
	float wsum = 4.0;
	for (int i = 1; i <= 4; i++)
	{
		float t = float(i) * 0.5;
		float w = lanczos2(t);
		vec2 oa = axisAlong * t * texel * scale;
		vec2 ob = axisAcross * t * texel * scale;
		acc += vec4(tap(uv + oa), 1.0) * w;
		acc += vec4(tap(uv - oa), 1.0) * w;
		acc += vec4(tap(uv + ob), 1.0) * w * 0.85;
		acc += vec4(tap(uv - ob), 1.0) * w * 0.85;
		wsum += w * 2.0 + w * 0.85 * 2.0;
	}
	gl_FragData[0] = acc / max(wsum, 1e-3);
}';

	static var RCAS_FRAG:String = '
#include "r3d/inc/r3d.glsl"
#include "r3d/inc/material.glsl"

uniform sampler2D uSrc;
uniform vec2 uSrcSize;
uniform float uSharpness;

// Contrast adaptive sharpening. The per-pixel gain is limited by how much local contrast
// already exists, which is the difference between this and a fixed unsharp mask: flat
// areas stay flat instead of growing noise halos.
void main()
{
	vec2 uv = r3d_TexCoordv;
	vec2 texel = 1.0 / uSrcSize;
	vec4 c = texture2D(uSrc, uv);
	vec3 n = texture2D(uSrc, uv + vec2(0.0, -texel.y)).rgb;
	vec3 s = texture2D(uSrc, uv + vec2(0.0, texel.y)).rgb;
	vec3 w = texture2D(uSrc, uv + vec2(-texel.x, 0.0)).rgb;
	vec3 e = texture2D(uSrc, uv + vec2(texel.x, 0.0)).rgb;

	vec3 mn = min(c.rgb, min(min(n, s), min(w, e)));
	vec3 mx = max(c.rgb, max(max(n, s), max(w, e)));
	// Higher local contrast -> smaller gain. The 0.25 floor keeps hard edges from being
	// over-sharpened into visible outlines.
	vec3 range = mx - mn;
	vec3 gain = uSharpness * (1.0 - min(range * 1.6, 0.75));

	vec3 blur = (n + s + w + e) * 0.25;
	vec3 sharp = c.rgb + (c.rgb - blur) * gain * 4.0;
	gl_FragData[0] = vec4(clamp(sharp, mn, mx), c.a);
}';
}
