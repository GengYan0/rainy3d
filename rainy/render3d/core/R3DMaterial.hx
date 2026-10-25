package rainy.render3d.core;

import rainy.render3d.host.R3DLog;
import haxe.ds.StringMap;
import openfl.display3D.Context3D;
import openfl.display3D.Context3DBlendFactor;
import rainy.render3d.core.R3D.R3DBlend;
import rainy.render3d.core.R3D.R3DFace;

class R3DMaterial
{
	public var shader:R3DShader;
	public var baseShader:R3DShader;
	public var colorR:Float = 1;
	public var colorG:Float = 1;
	public var colorB:Float = 1;
	public var colorA:Float = 1;
	public var blendMode:R3DBlend = R3DBlend.MIX;
	public var culling:R3DFace = R3DFace.BACK;
	public var depthTest:Bool = true;
	public var depthWrite:Bool = true;
	public var opaque:Bool = true;
	public var alphaScissor:Float = 0;
	public var priority:Int = 0;
	public var textures:StringMap<R3DTexture> = new StringMap();
	public var params:StringMap<Dynamic> = new StringMap();
	public var roughness:Float = 0.6;
	public var metallic:Float = 0.0;
	public var specStrength:Float = 1.0;
	public var specularR:Float = 1.0;
	public var specularG:Float = 1.0;
	public var specularB:Float = 1.0;
	public var emissiveR:Float = 0.0;
	public var emissiveG:Float = 0.0;
	public var emissiveB:Float = 0.0;
	public var normalScale:Float = 1.0;
	public var occlusion:Float = 1.0;
	public var uvScaleU:Float = 1.0;
	public var uvScaleV:Float = 1.0;
	public var uvOffsetU:Float = 0.0;
	public var uvOffsetV:Float = 0.0;
	public var lightSkip:Array<Int> = null;
	public var graph:R3DMaterialGraph;
	public var graphShader:R3DShader;
	public var name:String = "";
	public var disposed:Bool = false;
	public var ownsShader:Bool = false;

	public function new(?shader:R3DShader)
	{
		this.shader = shader;
		this.baseShader = shader;
	}

	public function setColor(value:Int):Void
	{
		colorA = ((value >> 24) & 0xFF) / 255.0;
		colorR = ((value >> 16) & 0xFF) / 255.0;
		colorG = ((value >> 8) & 0xFF) / 255.0;
		colorB = (value & 0xFF) / 255.0;
	}

	public function uvTile(tile:Float):Void
	{
		var s = 1.0 / Math.max(tile, 0.01);
		uvScaleU = s;
		uvScaleV = s;
	}

	public function useGraph(g:R3DMaterialGraph, vertSource:String):Bool
	{
		if (g == null || vertSource == null) return false;
		graph = g;
		var sh = R3DShader.fromSources(vertSource, g.fragSource(), null);
		if (sh == null || sh.failed) return false;
		graphShader = sh;
		shader = sh;
		return true;
	}

	public function clearGraph():Void
	{
		graph = null;
		graphShader = null;
		shader = baseShader;
	}

	public function bind():Void
	{
		if (shader == null) return;
		shader.bind();
		shader.setVec4("uTint", colorR, colorG, colorB, colorA);
		shader.setFloat("uAlphaScissor", alphaScissor);
		shader.setVec3("uSpecular", specularR, specularG, specularB);
		shader.setVec3("uEmissive", emissiveR, emissiveG, emissiveB);
		shader.setFloat("uRoughness", roughness);
		shader.setFloat("uMetallic", metallic);
		shader.setFloat("uSpecStrength", specStrength);
		shader.setFloat("uNormalScale", normalScale);
		shader.setFloat("uOcclusion", occlusion);
		shader.setVec2("uUvScale", uvScaleU, uvScaleV);
		shader.setVec2("uUvOffset", uvOffsetU, uvOffsetV);
		for (k in params.keys())
			shader.setValue(k, params.get(k));
		if (lightSkip != null)
			for (i in lightSkip)
				shader.setFloatAt("uLightMask", i, 0.0);
		var unit = 0;
		for (k in textures.keys())
		{
			var t = textures.get(k);
			if (t == null || t.handle() == null || !shader.hasSampler(k)) continue;
			R3DScene.bindTexture(unit, t);
			shader.setTexture(k, unit);
			unit++;
		}
	}

	public function toJson():Dynamic
	{
		var tex = {};
		for (k in textures.keys())
			Reflect.setField(tex, k, textures.get(k).path);
		return {
			name: name, r: colorR, g: colorG, b: colorB, a: colorA,
			rough: roughness, metal: metallic, spec: specStrength, normalScale: normalScale,
			occlusion: occlusion, scissor: alphaScissor, priority: priority,
			uvs: [uvScaleU, uvScaleV, uvOffsetU, uvOffsetV], tex: tex
		};
	}

	public function destroy():Void
	{
		if (disposed) return;
		disposed = true;
		textures = new StringMap();
		params = new StringMap();
		graph = null;
		graphShader = null;
	}

	public static function blendFactors(mode:R3DBlend, out:Array<Int>):Void
	{
		switch (mode)
		{
			case R3DBlend.ADD:
				out[0] = cast Context3DBlendFactor.SOURCE_ALPHA;
				out[1] = cast Context3DBlendFactor.ONE;
			case R3DBlend.SCREEN:
				out[0] = cast Context3DBlendFactor.SOURCE_ALPHA;
				out[1] = cast Context3DBlendFactor.ONE_MINUS_SOURCE_COLOR;
			case R3DBlend.MULTIPLY:
				out[0] = cast Context3DBlendFactor.DESTINATION_COLOR;
				out[1] = cast Context3DBlendFactor.ZERO;
			case R3DBlend.NONE:
				out[0] = cast Context3DBlendFactor.ONE;
				out[1] = cast Context3DBlendFactor.ZERO;
			default:
				out[0] = cast Context3DBlendFactor.SOURCE_ALPHA;
				out[1] = cast Context3DBlendFactor.ONE_MINUS_SOURCE_ALPHA;
		}
	}
}
