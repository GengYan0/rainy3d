package rainy.render3d.core;

import lime.graphics.opengl.GL;

enum abstract R3DAAMode(Int) from Int to Int
{
	var OFF = 0;
	/** One edge directed pass at display resolution. */
	var FXAA = 1;

	public function label():String
	{
		return switch (cast this : R3DAAMode)
		{
			case OFF: 'off';
			case FXAA: 'fxaa';
		}
	}

	@:from public static function of(s:String):R3DAAMode
	{
		if (s == null) return OFF;
		return switch (s.toLowerCase())
		{
			case 'fxaa' | 'on' | 'true': FXAA;
			default: OFF;
		}
	}
}

class R3DAA
{
	public static var mode:R3DAAMode = R3DAAMode.FXAA;

	public static var strength:Float = 0.75;

	public static var threshold:Float = 0.055;

	public var passes:Int = 0;

	var dst:R3DTexture = null;
	var dstW:Int = 0;
	var dstH:Int = 0;
	var shader:R3DShader = null;
	var shaderFailed:Bool = false;

	public function new() {}

	public function apply(src:R3DTexture, w:Int, h:Int, ?into:R3DTexture):R3DTexture
	{
		if (src == null || w < 2 || h < 2) return src;
		if (mode == R3DAAMode.OFF) return src;

		var target:R3DTexture = into;
		if (target == null)
		{
			if (dst == null || dstW != w || dstH != h || dst.disposed)
			{
				if (dst != null) dst.dispose();
				dst = R3DTexture.create(w, h);
				dstW = w;
				dstH = h;
			}
			target = dst;
		}
		if (target == null) return src;

		var ctx = R3DShader.context;
		if (ctx == null) return src;
		var sh = ensureShader();
		if (sh == null) return src;

		@:privateAccess
		{
			ctx.__state.renderToTexture = target.glTexture;
			ctx.__state.renderToTextureDepthStencil = false;
			ctx.__flushGLFramebuffer();
		}
		GL.viewport(0, 0, w, h);
		R3DGLStateCache.invalidateOpenfl();
		GL.disable(GL.DEPTH_TEST);
		GL.disable(GL.CULL_FACE);
		GL.disable(GL.BLEND);
		GL.clearColor(0.0, 0.0, 0.0, 1.0);
		GL.clear(GL.COLOR_BUFFER_BIT);

		R3DGLStateCache.program = null;
		R3DShader.invalidate();
		sh.bind();
		var ident = R3DFullscreen.identity();
		sh.setMat4("uProj", ident);
		sh.setMat4("uView", ident);
		sh.setMat4("uModel", ident);
		sh.setVec2("iResolution", w, h);
		sh.setVec2("uSrcSize", src.width, src.height);
		sh.setFloat("uThreshold", Math.max(0.001, threshold));
		sh.setFloat("uStrength", Math.max(0.0, Math.min(1.0, strength)));
		R3DScene.bindTexture(0, src);
		sh.setTexture("uSrc", 0);
		R3DFullscreen.draw(ctx, sh);
		passes++;
		return target;
	}

	public function dispose():Void
	{
		if (dst != null) dst.dispose();
		dst = null;
		dstW = 0;
		dstH = 0;
		if (shader != null) shader.dispose();
		shader = null;
		shaderFailed = false;
	}

	public function info():String
	{
		return 'aa ' + mode.label() + ' strength ' + strength + ' threshold ' + threshold + ' passes ' + passes;
	}

	function ensureShader():R3DShader
	{
		if (shader != null && !shader.failed) return shader;
		if (shaderFailed) return null;
		var s = R3DShader.fromSources(R3DShaders.UNLIT_VERT, FXAA_FRAG, ["SOLID"]);
		if (s == null || s.failed)
		{
			shaderFailed = true;
			return null;
		}
		shader = s;
		return shader;
	}

	static var FXAA_FRAG:String = '
#include "r3d/inc/r3d.glsl"
#include "r3d/inc/material.glsl"

uniform sampler2D uSrc;
uniform vec2 uSrcSize;
uniform float uThreshold;
uniform float uStrength;

float luma(vec3 c)
{
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void main()
{
	vec2 uv = r3d_TexCoordv;
	vec2 t = 1.0 / uSrcSize;

	vec4 c = texture2D(uSrc, uv);
	float lC = luma(c.rgb);
	float lL = luma(texture2D(uSrc, uv - vec2(t.x, 0.0)).rgb);
	float lR = luma(texture2D(uSrc, uv + vec2(t.x, 0.0)).rgb);
	float lU = luma(texture2D(uSrc, uv - vec2(0.0, t.y)).rgb);
	float lD = luma(texture2D(uSrc, uv + vec2(0.0, t.y)).rgb);

	float lMin = min(lC, min(min(lL, lR), min(lU, lD)));
	float lMax = max(lC, max(max(lL, lR), max(lU, lD)));
	float range = lMax - lMin;

	// Flat neighbourhood: nothing to blend, and blending anyway is how detail dies.
	if (range < uThreshold)
	{
		gl_FragData[0] = c;
		return;
	}

	// Already an extremum: this is a one pixel line, a dot, a highlight tip. Averaging it
	// with its neighbours would thin or erase it.
	if (lC >= lMax - 1e-5 || lC <= lMin + 1e-5)
	{
		gl_FragData[0] = c;
		return;
	}

	// Second derivative along each axis tells which way the edge runs. The axis with the
	// larger curvature is the one crossing the edge, so the average is taken along the
	// other one.
	float curvX = abs(lL + lR - 2.0 * lC);
	float curvY = abs(lU + lD - 2.0 * lC);

	vec3 blend;
	if (curvX > curvY)
		blend = (texture2D(uSrc, uv - vec2(0.0, t.y * 0.5)).rgb
			+ texture2D(uSrc, uv + vec2(0.0, t.y * 0.5)).rgb) * 0.5;
	else
		blend = (texture2D(uSrc, uv - vec2(t.x * 0.5, 0.0)).rgb
			+ texture2D(uSrc, uv + vec2(t.x * 0.5, 0.0)).rgb) * 0.5;

	// High contrast edges get less blend so silhouettes stay crisp.
	float w = uStrength * clamp(range * 4.5, 0.0, 1.0);
	gl_FragData[0] = vec4(mix(c.rgb, blend, w), c.a);
}';
}
