package rainy.render3d.core;

import rainy.render3d.host.R3DEnv;

import lime.graphics.opengl.GL;
import openfl.display3D.Context3D;

enum abstract R3DVendor(String) from String to String
{
	var UNKNOWN = "unknown";
	var NVIDIA = "nvidia";
	var AMD = "amd";
	var INTEL = "intel";
	var APPLE = "apple";
	var QUALCOMM = "qualcomm";
	var ARM = "arm";
	var MICROSOFT = "microsoft";
}

class R3DCaps
{
	static inline var GL_VENDOR:Int = 0x1F00;
	static inline var GL_RENDERER:Int = 0x1F01;
	static inline var GL_VERSION:Int = 0x1F02;
	static inline var GL_SL_VERSION:Int = 0x8B8C;
	static inline var GL_MAX_TEXTURE_SIZE:Int = 0x0D33;
	static inline var GL_MAX_TEXTURE_IMAGE_UNITS:Int = 0x8872;
	static inline var GL_MAX_VERTEX_ATTRIBS:Int = 0x8869;
	static inline var GL_MAX_COMBINED_TEX_UNITS:Int = 0x8B4D;
	static inline var GL_MAX_SAMPLES:Int = 0x8D57;
	static inline var GL_MAX_FRAGMENT_UNIFORM_VECTORS:Int = 0x8DFD;
	static inline var GL_MAX_VARYING_VECTORS:Int = 0x8DFC;
	static inline var GL_ANISO_EXT:Int = 0x84FE;
	static inline var GL_MAX_ANISO_EXT:Int = 0x84FF;
	static inline var GL_NVX_DEDICATED_VMEM:Int = 0x9047;
	static inline var GL_NVX_TOTAL_AVAILABLE:Int = 0x9048;
	static inline var GL_NVX_CURRENT_AVAILABLE:Int = 0x9049;
	static inline var GL_NVX_EVICTIONS:Int = 0x904B;

	public static var vendorId:String = "";
	public static var vendor:R3DVendor = R3DVendor.UNKNOWN;
	public static var renderer:String = "";
	public static var version:String = "";
	public static var shaderVersion:String = "";
	public static var detected:Bool = false;

	public static var maxTextureSize:Int = 2048;

	public static var npotSupported:Bool = true;

	public static var npotMipmap:Bool = true;
	public static var maxTextureUnits:Int = 16;
	public static var maxVertexAttribs:Int = 16;
	public static var maxCombinedTexUnits:Int = 16;
	public static var maxSamples:Int = 0;
	public static var maxUniformVectors:Int = 256;
	public static var maxVaryings:Int = 8;

	public static var anisoSupported:Bool = false;
	public static var maxAnisotropy:Int = 1;

	public static var vramSupported:Bool = false;
	public static var vramDedicatedMB:Float = 0;
	public static var vramTotalMB:Float = 0;
	public static var vramFreeMB:Float = 0;
	public static var vramEvictions:Int = 0;

	public static var presetName:String = "default";
	public static var presetAniso:Int = 1;
	public static var presetMipmaps:Bool = true;
	public static var presetDepthWrite:Bool = true;
	public static var presetHint:Bool = true;

	static var ctx:Context3D;

	public static function init(context:Context3D):Void
	{
		if (context == null) return;
		ctx = context;
		if (!detected) detect();
		applyPreset();
	}

	public static function detect():Void
	{
		// `detected` is published at the end, not here: it is the flag that tells callers
		// `maxTextureSize` is trustworthy, and until the probes below run it still holds
		// the conservative default.
		vendorId = glString(GL_VENDOR);
		renderer = glString(GL_RENDERER);
		version = glString(GL_VERSION);
		shaderVersion = glString(GL_SL_VERSION);
		var probe = (vendorId + " " + renderer).toLowerCase();
		if (probe.indexOf("nvidia") >= 0)
			vendor = R3DVendor.NVIDIA;
		else if (probe.indexOf("ati") >= 0 || probe.indexOf("amd") >= 0 || probe.indexOf("radeon") >= 0)
			vendor = R3DVendor.AMD;
		else if (probe.indexOf("intel") >= 0)
			vendor = R3DVendor.INTEL;
		else if (probe.indexOf("apple") >= 0)
			vendor = R3DVendor.APPLE;
		else if (probe.indexOf("qualcomm") >= 0 || probe.indexOf("adreno") >= 0)
			vendor = R3DVendor.QUALCOMM;
		else if (probe.indexOf("arm") >= 0 || probe.indexOf("mali") >= 0)
			vendor = R3DVendor.ARM;
		else if (probe.indexOf("microsoft") >= 0)
			vendor = R3DVendor.MICROSOFT;

		maxTextureSize = glInt(GL_MAX_TEXTURE_SIZE, 2048);
		maxTextureUnits = glInt(GL_MAX_TEXTURE_IMAGE_UNITS, 16);
		maxVertexAttribs = glInt(GL_MAX_VERTEX_ATTRIBS, 16);
		maxCombinedTexUnits = glInt(GL_MAX_COMBINED_TEX_UNITS, 16);
		maxSamples = glInt(GL_MAX_SAMPLES, 0);
		maxUniformVectors = glInt(GL_MAX_FRAGMENT_UNIFORM_VECTORS, 256);
		maxVaryings = glInt(GL_MAX_VARYING_VECTORS, 8);

		detectNpot();

		anisoSupported = hasExtension("EXT_texture_filter_anisotropic");
		maxAnisotropy = anisoSupported ? Std.int(Math.max(1, glInt(GL_MAX_ANISO_EXT, 1))) : 1;

		vramSupported = hasExtension("NVX_gpu_memory_info");
		if (vramSupported) pollVram();

		detected = true;

		// Caps are only known now, so the quality preset is re-clamped against them.
		R3DEnv.applyQuality();
	}

	public static function hasExtension(name:String):Bool
	{
		if (extList == null)
		{
			extList = [];
			try
			{
				var a:Array<String> = GL.getSupportedExtensions();
				if (a != null) extList = a;
			}
			catch (e:Dynamic)
			{
				extList = [];
			}
		}
		if (name == null) return false;
		var n:String = StringTools.startsWith(name, "GL_") ? name.substr(3) : name;
		return extList.indexOf(n) >= 0;
	}

	static var extList:Array<String> = null;

	static function detectNpot():Void
	{
		npotSupported = true;
		npotMipmap = true;
		try
		{
			var v:String = version == null ? "" : version.toLowerCase();
			var major:Int = 0;
			if (v.indexOf("opengl es") >= 0)
			{
				var m = ~/opengl es\s+(\d+)/;
				if (m.match(v)) major = Std.parseInt(m.matched(1));
				npotMipmap = major >= 3;
				npotSupported = npotMipmap || hasExtension("OES_texture_npot");
			}
			else
			{
				var m = ~/^\s*(\d+)/;
				if (m.match(v)) major = Std.parseInt(m.matched(1));
				npotSupported = major >= 2;
				npotMipmap = npotSupported;
				if (!npotSupported && hasExtension("ARB_texture_non_power_of_two"))
				{
					npotSupported = true;
					npotMipmap = true;
				}
			}
			if (major == 0)
			{
				npotSupported = true;
				npotMipmap = true;
			}
		}
		catch (e:Dynamic)
		{
			npotSupported = true;
			npotMipmap = true;
		}
	}

	public static function pollVram():Void
	{
		if (!vramSupported) return;
		vramDedicatedMB = glInt(GL_NVX_DEDICATED_VMEM, 0) / 1024.0;
		vramTotalMB = glInt(GL_NVX_TOTAL_AVAILABLE, 0) / 1024.0;
		vramFreeMB = glInt(GL_NVX_CURRENT_AVAILABLE, 0) / 1024.0;
		vramEvictions = glInt(GL_NVX_EVICTIONS, 0);
	}

	public static function applyPreset():Void
	{
		switch (vendor)
		{
			case R3DVendor.NVIDIA:
				presetName = "nvidia";
				presetAniso = vramSupported ? clampAniso(16) : clampAniso(8);
				presetMipmaps = true;
				presetDepthWrite = true;
				presetHint = true;
			case R3DVendor.AMD:
				presetName = "amd";
				presetAniso = clampAniso(8);
				presetMipmaps = true;
				presetDepthWrite = true;
				presetHint = true;
			case R3DVendor.INTEL:
				presetName = "intel";
				presetAniso = clampAniso(4);
				presetMipmaps = true;
				presetDepthWrite = true;
				presetHint = false;
			default:
				presetName = "generic";
				presetAniso = clampAniso(4);
				presetMipmaps = true;
				presetDepthWrite = true;
				presetHint = false;
		}
	}

	public static function clampAniso(want:Int):Int
	{
		if (!anisoSupported) return 1;
		var m = maxAnisotropy < 1 ? 1 : maxAnisotropy;
		return want < 1 ? 1 : (want > m ? m : want);
	}

	public static function setAniso(level:Int):Int
	{
		presetAniso = clampAniso(level);
		return presetAniso;
	}

	static function glString(name:Int):String
	{
		try
		{
			var s = GL.getString(name);
			return s == null ? "" : s;
		}
		catch (e:Dynamic)
		{
			return "";
		}
	}

	static function glInt(name:Int, fallback:Int):Int
	{
		try
		{
			var v:Dynamic = GL.getParameter(name);
			if (v == null) return fallback;
			if (Std.isOfType(v, Int)) return cast v;
			if (Std.isOfType(v, Float)) return Std.int(cast v);
			var i = Std.parseInt("" + v);
			return i == null ? fallback : i;
		}
		catch (e:Dynamic)
		{
			return fallback;
		}
	}

	public static function isNvidia():Bool
	{
		return vendor == R3DVendor.NVIDIA;
	}

	public static function describe():String
	{
		return vendor + " / " + (renderer.length > 0 ? renderer : "?") + " / GL " + version
			+ " / maxTex " + maxTextureSize + " / units " + maxTextureUnits
			+ " / aniso " + presetAniso + (anisoSupported ? "" : " (n/a)")
			+ (vramSupported ? (" / vram " + Std.int(vramFreeMB) + "MB free of " + Std.int(vramDedicatedMB) + "MB") : "");
	}
}
