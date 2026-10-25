package rainy.render3d.core;

import haxe.ds.StringMap;
import lime.graphics.opengl.GL;
import openfl.display3D.Context3DVertexBufferFormat;
import rainy.render3d.core.R3DMat4;
import rainy.render3d.core.R3DGLStateCache;
import rainy.render3d.core.R3DMesh;
import rainy.render3d.core.R3DTexture;
import rainy.render3d.core.R3DShader;
import rainy.render3d.core.R3DShaders;

class R3DPostPass
{
	public var name:String;
	public var shader:R3DShader;
	public var enabled:Bool = true;
	public var floats:StringMap<Float> = new StringMap();
	public var vec2s:StringMap<Array<Float>> = new StringMap();
	public var vec3s:StringMap<Array<Float>> = new StringMap();
	public var textures:StringMap<R3DTexture> = new StringMap();

	public function new(name:String, shader:R3DShader)
	{
		this.name = name;
		this.shader = shader;
	}

	public function set(k:String, v:Float):R3DPostPass
	{
		floats.set(k, v);
		return this;
	}

	public function setVec2(k:String, a:Float, b:Float):R3DPostPass
	{
		vec2s.set(k, [a, b]);
		return this;
	}

	public function setVec3(k:String, a:Float, b:Float, c:Float):R3DPostPass
	{
		vec3s.set(k, [a, b, c]);
		return this;
	}

	public function setTex(k:String, t:R3DTexture):R3DPostPass
	{
		textures.set(k, t);
		return this;
	}

	public function clearParams():Void
	{
		floats = new StringMap();
		vec2s = new StringMap();
		vec3s = new StringMap();
	}
}

class R3DPostChain
{
	public var passes:Array<R3DPostPass> = [];
	public var name:String = "post";
	public var invertY:Bool = true;

	var texA:R3DTexture = null;
	var texB:R3DTexture = null;
	var w:Int = 0;
	var h:Int = 0;
	static var ident:Array<Float> = null;

	public function new(?nm:String)
	{
		if (nm != null) name = nm;
	}

	public function add(p:R3DPostPass):R3DPostPass
	{
		passes.push(p);
		return p;
	}

	public function remove(nm:String):Void
	{
		var out:Array<R3DPostPass> = [];
		for (p in passes)
			if (p.name != nm) out.push(p);
		passes = out;
	}

	public function find(nm:String):R3DPostPass
	{
		for (p in passes)
			if (p.name == nm) return p;
		return null;
	}

	public function clear():Void
	{
		passes = [];
	}

	public function activeCount():Int
	{
		var n = 0;
		for (p in passes)
			if (p.enabled && p.shader != null) n++;
		return n;
	}

	public function ensure(wid:Int, hei:Int):Void
	{
		if (wid <= 0 || hei <= 0) return;
		if (this.w == wid && this.h == hei && texA != null && texB != null) return;
		if (texA != null) texA.dispose();
		if (texB != null) texB.dispose();
		this.w = wid;
		this.h = hei;
		texA = R3DTexture.create(wid, hei);
		texB = R3DTexture.create(wid, hei);
	}

	function ensureQuad():Bool
	{
		return R3DFullscreen.mesh() != null;
	}

	function runPass(p:R3DPostPass, src:R3DTexture, dst:R3DTexture):Void
	{
		var ctx = R3DShader.context;
		if (ctx == null || p.shader == null || src == null || dst == null) return;
		@:privateAccess
		{
			ctx.__state.renderToTexture = dst.glTexture;
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
		if (ident == null) ident = R3DMat4.identity();
		var sh = p.shader;
		R3DGLStateCache.program = null;
		R3DShader.invalidate();
		sh.bind();
		sh.setMat4("uProj", ident);
		sh.setMat4("uView", ident);
		sh.setMat4("uModel", ident);
		sh.setVec2("iResolution", w, h);
		R3DScene.bindTexture(0, src);
		sh.setTexture("uSrc", 0);
		for (k in p.floats.keys())
			sh.setFloat(k, p.floats.get(k));
		for (k in p.vec2s.keys())
		{
			var a = p.vec2s.get(k);
			sh.setVec2(k, a[0], a[1]);
		}
		for (k in p.vec3s.keys())
		{
			var a = p.vec3s.get(k);
			sh.setVec3(k, a[0], a[1], a[2]);
		}
		var unit = 1;
		for (k in p.textures.keys())
		{
			R3DScene.bindTexture(unit, p.textures.get(k));
			sh.setTexture(k, unit);
			unit++;
		}
		R3DFullscreen.draw(ctx, sh);
	}

	public function process(src:R3DTexture):R3DTexture
	{
		if (src == null || activeCount() == 0) return src;
		ensure(src.width, src.height);
		if (texA == null || texB == null) return src;
		if (!ensureQuad()) return src;
		var read = src;
		var slot = 0;
		for (p in passes)
		{
			if (!p.enabled || p.shader == null) continue;
			var dst = slot == 0 ? texA : texB;
			runPass(p, read, dst);
			read = dst;
			slot = 1 - slot;
		}
		return read;
	}

	public function dispose():Void
	{
		if (texA != null) texA.dispose();
		if (texB != null) texB.dispose();
		texA = null;
		texB = null;
		w = 0;
		h = 0;
	}

	public function info():String
	{
		return name + " 通道 " + activeCount() + "/" + passes.length + " " + w + "x" + h;
	}
}

class R3DPostShaders
{
	public static var COPY_FRAG:String = '
#include "r3d/inc/r3d.glsl"
#include "r3d/inc/material.glsl"

uniform sampler2D uSrc;

void main()
{
	gl_FragData[0] = texture2D(uSrc, r3d_TexCoordv);
}';

	public static var GRAY_FRAG:String = '
#include "r3d/inc/r3d.glsl"
#include "r3d/inc/material.glsl"

uniform sampler2D uSrc;
uniform float uAmount;

void main()
{
	vec4 c = texture2D(uSrc, r3d_TexCoordv);
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	gl_FragData[0] = vec4(mix(c.rgb, vec3(g), uAmount), c.a);
}';

	public static var FISHEYE_FRAG:String = '
#include "r3d/inc/r3d.glsl"
#include "r3d/inc/material.glsl"

uniform sampler2D uSrc;
uniform float uAmount;
uniform vec2 uCenter;

void main()
{
	vec2 uv = r3d_TexCoordv - uCenter;
	float r = length(uv);
	float k = 1.0 + uAmount * r * r;
	uv = uv * k + uCenter;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
	{
		gl_FragData[0] = vec4(0.0, 0.0, 0.0, 1.0);
		return;
	}
	gl_FragData[0] = texture2D(uSrc, uv);
}';

	public static var CHROMA_FRAG:String = '
#include "r3d/inc/r3d.glsl"
#include "r3d/inc/material.glsl"

uniform sampler2D uSrc;
uniform float uAmount;

void main()
{
	vec2 uv = r3d_TexCoordv;
	vec2 d = (uv - vec2(0.5)) * uAmount;
	vec4 c;
	c.r = texture2D(uSrc, uv + d).r;
	c.g = texture2D(uSrc, uv).g;
	c.b = texture2D(uSrc, uv - d).b;
	c.a = 1.0;
	gl_FragData[0] = c;
}';

	public static var VIGNETTE_FRAG:String = '
#include "r3d/inc/r3d.glsl"
#include "r3d/inc/material.glsl"

uniform sampler2D uSrc;
uniform float uAmount;
uniform float uRound;

void main()
{
	vec4 c = texture2D(uSrc, r3d_TexCoordv);
	vec2 q = r3d_TexCoordv - vec2(0.5);
	float v = 1.0 - uAmount * dot(q, q) * (1.0 + uRound);
	if (v < 0.0) v = 0.0;
	gl_FragData[0] = vec4(c.rgb * v, c.a);
}';

	public static var CHAIN_NAME:String = "r3d_post";

	public static function passShader(frag:String):R3DShader
	{
		return R3DShader.fromSources(R3DShaders.UNLIT_VERT, frag, ["SOLID"]);
	}

	public static function copy():R3DPostPass
	{
		return new R3DPostPass("copy", passShader(COPY_FRAG));
	}

	public static function gray(amount:Float = 1.0):R3DPostPass
	{
		var p = new R3DPostPass("gray", passShader(GRAY_FRAG));
		p.set("uAmount", amount);
		return p;
	}

	public static function fisheye(amount:Float = 0.35):R3DPostPass
	{
		var p = new R3DPostPass("fisheye", passShader(FISHEYE_FRAG));
		p.set("uAmount", amount);
		p.setVec2("uCenter", 0.5, 0.5);
		return p;
	}

	public static function chroma(amount:Float = 0.004):R3DPostPass
	{
		var p = new R3DPostPass("chroma", passShader(CHROMA_FRAG));
		p.set("uAmount", amount);
		return p;
	}

	public static function vignette(amount:Float = 0.8, round:Float = 0.2):R3DPostPass
	{
		var p = new R3DPostPass("vignette", passShader(VIGNETTE_FRAG));
		p.set("uAmount", amount);
		p.set("uRound", round);
		return p;
	}
}
