package rainy.render3d.core;

import rainy.render3d.host.R3DEnv;

import rainy.render3d.host.R3DLog;
import haxe.ds.StringMap;
import lime.graphics.opengl.GL;
import lime.utils.Float32Array;
import openfl.display3D.Context3D;
import openfl.display3D.Program3D;
import openfl.geom.Vector3D;
import openfl.utils.Assets;
import sys.FileSystem;
import sys.io.File;

typedef R3DUniform = {
	var location:Int;
	var type:Int;
	var size:Int;
}

class R3DShader
{
	public static inline var MAX_LIGHTS:Int = 16;

	public static var context:Context3D;
	public static var current(default, null):R3DShader = null;

	static var includeCache:StringMap<String> = new StringMap();
	public static var includeRoots:Array<String> = ["assets/shaders/", "shaders/"];
	public static var globalDefines:Array<String> = [];
	public static var preferDisk:Bool = true;
	public static var useCache:Bool = true;
	public static var compiled:Int = 0;
	public static var cacheHits:Int = 0;
	public static var errors:Array<String> = [];

	public static function lastErrors():String
	{
		if (errors.length < 1) return '';
		var out:String = '';
		var from:Int = errors.length > 3 ? errors.length - 3 : 0;
		var i:Int = from;
		while (i < errors.length)
		{
			out += (out.length > 0 ? ' | ' : '') + errors[i];
			i++;
		}
		return out;
	}

	static var variantCache:StringMap<R3DShader> = new StringMap();

	public var program:Program3D;
	public var vertSource:String = "";
	public var fragSource:String = "";
	public var uniformCache:StringMap<R3DUniform> = new StringMap();

	public var uniformValueCache:StringMap<Array<Float>> = new StringMap();
	public static var uniformWritesSkipped:Int = 0;
	public static var uniformWritesTotal:Int = 0;
	public var arrayLocCache:StringMap<Int> = new StringMap();
	public var defines:Array<String> = [];
	public var sourceVert:String = "";
	public var sourceFrag:String = "";
	public var flags:String = "";
	public var shared:Bool = false;
	public var failed:Bool = false;

	public var uid:Int = 0;
	public var attrPosition:Int = -1;
	public var attrTexCoord:Int = -1;
	public var attrNormal:Int = -1;
	public var attrTangent:Int = -1;
	public var attrColor:Int = -1;
	public var attrInst0:Int = -1;
	public var attrInst1:Int = -1;
	public var attrInst2:Int = -1;
	public var attrInst3:Int = -1;
	public var attrColorI:Int = -1;

	public var instanced(default, null):Bool = false;

	static var _uidSeq:Int = 0;

	public function new()
	{
		uid = ++_uidSeq;
	}

	public function glProgram():Dynamic
	{
		if (program == null) return null;
		return @:privateAccess program.__glProgram;
	}

	public function hasUniform(name:String):Bool
	{
		return uniformCache.exists(name);
	}

	public function location(name:String):Int
	{
		var u = uniformCache.get(name);
		if (u != null && u.location >= 0) return u.location;
		var l = lookupLocation(name);
		if (l >= 0) uniformCache.set(name, {location: l, type: u == null ? 0 : u.type, size: u == null ? 1 : u.size});
		return l;
	}

	function lookupLocation(name:String):Int
	{
		var gp = glProgram();
		if (gp == null) return -1;
		try
		{
			var loc = glOf(context).getUniformLocation(gp, name);
			if (loc == null) return -1;
			return cast loc;
		}
		catch (e:Dynamic)
		{
			return -1;
		}
	}

	public function hasSampler(name:String):Bool
	{
		var u = uniformCache.get(name);
		return u != null && (u.type == GL.SAMPLER_2D || u.type == GL.SAMPLER_CUBE);
	}

	public function bind():Void
	{
		if (current == this) return;
		if (program == null) return;
		R3DGLStateCache.useProgram(program);
		current = this;
	}

	public static function invalidate():Void
	{
		current = null;
	}

	public function dispose():Void
	{
		if (shared) return;
		uniformCache = new StringMap();
		arrayLocCache = new StringMap();
		if (program != null)
		{
			try program.dispose() catch (e:Dynamic) { R3DLog.silentFailure("R3DShader.dispose", e); }
			program = null;
		}
		if (current == this) current = null;
	}

	public static function fromSources(vert:String, frag:String, ?flags:Array<String>):R3DShader
	{
		var defs = [];
		for (d in globalDefines) defs.push(d);
		if (flags != null)
			for (f in flags)
				if (!defs.contains(f)) defs.push(f.toUpperCase());
		defs.sort(function(a, b) return a < b ? -1 : 1);

		var key = hashOf(vert) + "|" + hashOf(frag) + "|" + defs.join(",");
		if (useCache)
		{
			var hit = variantCache.get(key);
			if (hit != null && !hit.failed)
			{
				cacheHits++;
				return hit;
			}
		}

		var s = new R3DShader();
		s.defines = defs;
		s.flags = defs.join(",");
		s.sourceVert = vert;
		s.sourceFrag = frag;
		s.vertSource = inject(resolve(vert), s.defineBlock(), true);
		s.fragSource = inject(resolve(frag), s.defineBlock(), false);
		s.compile();
		if (!s.failed && useCache)
		{
			s.shared = true;
			variantCache.set(key, s);
		}
		return s;
	}

	public function defineBlock():String
	{
		var extra = "";
		for (d in defines) extra += "#define " + d + "\n";
		return extra;
	}

	public function sameVariant(vert:String, frag:String, ?flags:Array<String>):Bool
	{
		var defs = [];
		for (d in globalDefines) defs.push(d);
		if (flags != null)
			for (f in flags)
				if (!defs.contains(f)) defs.push(f.toUpperCase());
		defs.sort(function(a, b) return a < b ? -1 : 1);
		return sourceVert == vert && sourceFrag == frag && defines.join(",") == defs.join(",");
	}

	static function hashOf(s:String):String
	{
		if (s == null) return "0";
		var h = 5381;
		var i = 0;
		while (i < s.length)
		{
			h = ((h << 5) + h + StringTools.fastCodeAt(s, i)) & 0x7FFFFFFF;
			i++;
		}
		return StringTools.hex(h, 8) + ":" + s.length;
	}

	static function inject(src:String, defs:String, isVert:Bool):String
	{
		var marker = "#pragma flags";
		var tag = isVert ? "#define VERTEX\n" : "#define FRAGMENT\n";
		if (src.indexOf(marker) >= 0) return StringTools.replace(src, marker, marker + "\n" + tag + defs);
		return tag + defs + src;
	}

	public static function resolve(src:String):String
	{
		var rx = new EReg("^[ \\t]*#include[ \\t]+[\"'`]([^\"'`]+)[\"'`][ \\t]*\\r?$", "m");
		var seen = new Map<String, Bool>();
		var guard = 0;
		while (guard < 64)
		{
			guard++;
			if (!rx.match(src)) break;
			var file = rx.matched(1);
			var pos = rx.matchedPos();
			var text = seen.exists(file) ? "\n" : loadInclude(file);
			seen.set(file, true);
			src = src.substr(0, pos.pos) + text + src.substr(pos.pos + pos.len);
		}
		return src;
	}

	static function loadInclude(path:String):String
	{
		var cached = includeCache.get(path);
		if (cached != null) return cached;
		var text:String = null;
		var candidates = ["assets/shaders/" + path, path];
		if (preferDisk)
		{
			for (c in candidates)
			{
				if (text != null) continue;
				try
				{
					if (FileSystem.exists(c)) text = File.getContent(c);
				}
				catch (e:Dynamic) { R3DLog.silentFailure("R3DShader.loadInclude", e); }
			}
		}
		for (c in candidates)
		{
			if (text != null) continue;
			try
			{
				if (Assets.exists(c)) text = Assets.getText(c);
			}
			catch (e:Dynamic) { R3DLog.silentFailure("R3DShader.loadInclude", e); }
		}
		if (text == null)
			for (c in candidates)
			{
				if (text != null) continue;
				try
				{
					if (FileSystem.exists(c)) text = File.getContent(c);
				}
				catch (e:Dynamic) { R3DLog.silentFailure("R3DShader.loadInclude", e); }
			}
		if (text == null) text = "\n";
		includeCache.set(path, text);
		return text;
	}

	public static var onError:String->Void;

	static function report(msg:String):Void
	{
		errors.push(msg);
		if (onError != null) onError(msg);
		else R3DLog.error('shader', msg);
	}

	public function compile():Void
	{
		uniformValueCache = new StringMap();
		if (context == null) context = openfl.Lib.current.stage.context3D;
		R3DGLStateCache.init(context);
		failed = false;
		if (program == null) program = context.createProgram(cast 1);
		try
		{
			@:privateAccess program.__uploadFromGLSL(vertSource, fragSource);
		}
		catch (e:Dynamic)
		{
			failed = true;
			report("着色器上传异常 [" + flags + "] " + e);
			dumpSources();
			return;
		}
		var gp:Dynamic = glProgram();
		var gl:Dynamic = glOf(context);
		var link:Dynamic = gp == null ? 0 : gl.getProgramParameter(gp, gl.LINK_STATUS);
		failed = (link == null || link == 0 || link == false);
		if (failed)
		{
			report("着色器编译/链接失败 [" + flags + "] " + (gp == null ? "无程序对象" : gl.getProgramInfoLog(gp)));
			dumpSources();
			return;
		}
		compiled++;
		cacheLocations();
		if (attrPosition < 0) report("着色器缺少 r3d_Position 属性 [" + flags + "]");
	}

	public static var dumpOnFail:Bool = true;

	public function dumpSources():Void
	{
		if (!dumpOnFail) return;
		try
		{
			if (!FileSystem.exists("logs")) FileSystem.createDirectory("logs");
			var tag = flags.length == 0 ? "default" : StringTools.replace(flags, ",", "_");
			File.saveContent(R3DEnv.logPath("r3d_shader_" + tag + "_vert.glsl"), vertSource);
			File.saveContent(R3DEnv.logPath("r3d_shader_" + tag + "_frag.glsl"), fragSource);
			report("组装结果已落盘 logs/r3d_shader_" + tag + "_{vert,frag}.glsl");
		}
		catch (e:Dynamic) { R3DLog.silentFailure("R3DShader.dumpSources", e); }
	}

	public function reload():Void
	{
		invalidateIncludeCache();
		var v = resolve(sourceVert);
		var f = resolve(sourceFrag);
		vertSource = inject(v, defineBlock(), true);
		fragSource = inject(f, defineBlock(), false);
		compile();
	}

	public function cacheLocations():Void
	{
		uniformCache = new StringMap();
		arrayLocCache = new StringMap();
		var gp = glProgram();
		if (gp == null) return;
		var gl:Dynamic = glOf(context);
		var count:Int = gl.getProgramParameter(gp, gl.ACTIVE_UNIFORMS);
		for (i in 0...count)
		{
			var info = gl.getActiveUniform(gp, i);
			if (info == null) continue;
			var name:String = info.name;
			if (StringTools.endsWith(name, "[0]")) name = name.substr(0, name.length - 3);
			var loc = gl.getUniformLocation(gp, info.name);
			var l:Int = -1;
			if (loc != null) l = cast loc;
			uniformCache.set(name, {location: l, type: info.type, size: info.size});
		}
		attrPosition = attrib(gp, "r3d_Position");
		attrTexCoord = attrib(gp, "r3d_TexCoord");
		attrNormal = attrib(gp, "r3d_Normal");
		attrTangent = attrib(gp, "r3d_Tangent");
		attrColor = attrib(gp, "r3d_Color");
		attrInst0 = attrib(gp, "r3d_Instance0");
		attrInst1 = attrib(gp, "r3d_Instance1");
		attrInst2 = attrib(gp, "r3d_Instance2");
		attrInst3 = attrib(gp, "r3d_Instance3");
		attrColorI = attrib(gp, "r3d_ColorI");
		instanced = attrInst0 >= 0 && attrInst1 >= 0 && attrInst2 >= 0 && attrInst3 >= 0;
	}

	function attrib(gp:Dynamic, name:String):Int
	{
		var loc = glOf(context).getAttribLocation(gp, name);
		return loc == null ? -1 : cast loc;
	}

	public function arrayLocation(base:String, index:Int):Int
	{
		var key = base + "#" + index;
		if (arrayLocCache.exists(key)) return arrayLocCache.get(key);
		var gp = glProgram();
		var l = -1;
		if (gp != null && index >= 0 && index < MAX_LIGHTS * 4)
		{
			try
			{
				var loc = glOf(context).getUniformLocation(gp, base + "[" + index + "]");
				if (loc != null) l = cast loc;
			}
			catch (e:Dynamic) { R3DLog.silentFailure("R3DShader.arrayLocation", e); }
			if (l < 0)
			{
				var u = uniformCache.get(base);
				if (u != null && u.location >= 0) l = u.location + index;
			}
		}
		arrayLocCache.set(key, l);
		return l;
	}

	public function setFloat(name:String, v:Float):Bool
	{
		var l = location(name);
		if (l < 0) return false;
		uniformWritesTotal++;
		var prev = uniformValueCache.get(name);
		if (prev != null && prev.length == 1 && prev[0] == v)
		{
			uniformWritesSkipped++;
			return true;
		}
		var store:Array<Float> = prev;
		if (store == null || store.length != 1) store = [v];
		else store[0] = v;
		uniformValueCache.set(name, store);
		GL.uniform1f(cast l, v);
		return true;
	}

	public function setInt(name:String, v:Int):Bool
	{
		var l = location(name);
		if (l < 0) return false;
		uniformWritesTotal++;
		// Same value cache as the float setters. `setTexture` routes through here, so an
		// unchanged sampler unit was still rewriting the uniform on every draw call.
		var prev = uniformValueCache.get(name);
		if (prev != null && prev.length == 1 && prev[0] == v)
		{
			uniformWritesSkipped++;
			return true;
		}
		var store:Array<Float> = prev;
		if (store == null || store.length != 1) store = [v];
		else store[0] = v;
		uniformValueCache.set(name, store);
		GL.uniform1i(cast l, v);
		return true;
	}

	public function setVec2(name:String, x:Float, y:Float):Bool
	{
		var l = location(name);
		if (l < 0) return false;
		uniformWritesTotal++;
		var prev = uniformValueCache.get(name);
		if (prev != null && prev.length == 2 && prev[0] == x && prev[1] == y)
		{
			uniformWritesSkipped++;
			return true;
		}
		// Reuse the cached array: allocating a fresh literal per write made every changed
		// uniform a garbage object per frame.
		var store:Array<Float> = prev;
		if (store == null || store.length != 2)
		{
			store = [x, y];
		}
		else
		{
			store[0] = x;
			store[1] = y;
		}
		uniformValueCache.set(name, store);
		GL.uniform2f(cast l, x, y);
		return true;
	}

	public function setVec3(name:String, x:Float, y:Float, z:Float):Bool
	{
		var l = location(name);
		if (l < 0) return false;
		uniformWritesTotal++;
		var prev = uniformValueCache.get(name);
		if (prev != null && prev.length == 3 && prev[0] == x && prev[1] == y && prev[2] == z)
		{
			uniformWritesSkipped++;
			return true;
		}
		var store:Array<Float> = prev;
		if (store == null || store.length != 3)
		{
			store = [x, y, z];
		}
		else
		{
			store[0] = x;
			store[1] = y;
			store[2] = z;
		}
		uniformValueCache.set(name, store);
		GL.uniform3f(cast l, x, y, z);
		return true;
	}

	public function setVec4(name:String, x:Float, y:Float, z:Float, w:Float):Bool
	{
		var l = location(name);
		if (l < 0) return false;
		uniformWritesTotal++;
		var prev = uniformValueCache.get(name);
		if (prev != null && prev.length == 4 && prev[0] == x && prev[1] == y && prev[2] == z && prev[3] == w)
		{
			uniformWritesSkipped++;
			return true;
		}
		var store:Array<Float> = prev;
		if (store == null || store.length != 4)
		{
			store = [x, y, z, w];
		}
		else
		{
			store[0] = x;
			store[1] = y;
			store[2] = z;
			store[3] = w;
		}
		uniformValueCache.set(name, store);
		GL.uniform4f(cast l, x, y, z, w);
		return true;
	}

	public function setFloatAt(name:String, i:Int, v:Float):Bool
	{
		var l = arrayLocation(name, i);
		if (l < 0) return false;
		GL.uniform1f(cast l, v);
		return true;
	}

	public function setIntAt(name:String, i:Int, v:Int):Bool
	{
		var l = arrayLocation(name, i);
		if (l < 0) return false;
		GL.uniform1i(cast l, v);
		return true;
	}

	public function setVec2At(name:String, i:Int, x:Float, y:Float):Bool
	{
		var l = arrayLocation(name, i);
		if (l < 0) return false;
		GL.uniform2f(cast l, x, y);
		return true;
	}

	public function setVec3At(name:String, i:Int, x:Float, y:Float, z:Float):Bool
	{
		var l = arrayLocation(name, i);
		if (l < 0) return false;
		GL.uniform3f(cast l, x, y, z);
		return true;
	}

	public function setVec4At(name:String, i:Int, x:Float, y:Float, z:Float, w:Float):Bool
	{
		var l = arrayLocation(name, i);
		if (l < 0) return false;
		GL.uniform4f(cast l, x, y, z, w);
		return true;
	}

	static var matTmp:Float32Array = new Float32Array(16);

	public function setMat4(name:String, m:Array<Float>):Bool
	{
		var l = location(name);
		if (l < 0) return false;
		var a = matTmp;
		var r = 0;
		while (r < 4)
		{
			var c = 0;
			while (c < 4)
			{
				var src = r * 4 + c;
				a[c * 4 + r] = src < m.length ? m[src] : 0;
				c++;
			}
			r++;
		}
		uniformWritesTotal++;
		var prev = uniformValueCache.get(name);
		var same:Bool = prev != null && prev.length == 16;
		if (same)
		{
			var i:Int = 0;
			while (i < 16)
			{
				if (prev[i] != a[i])
				{
					same = false;
					break;
				}
				i++;
			}
		}
		if (same)
		{
			uniformWritesSkipped++;
			return true;
		}
		var store:Array<Float> = prev;
		if (store == null || store.length != 16) store = [for (i in 0...16) a[i]];
		else for (i in 0...16) store[i] = a[i];
		uniformValueCache.set(name, store);
		GL.uniformMatrix4fv(cast l, 1, false, a);
		return true;
	}

	public function setTexture(name:String, sampler:Int):Bool
	{
		return setInt(name, sampler);
	}

	public function setValue(name:String, value:Dynamic):Bool
	{
		if (value == null) return false;
		if (Std.isOfType(value, Bool)) return setInt(name, (cast value) ? 1 : 0);
		if (Std.isOfType(value, Float)) return setFloat(name, cast value);
		if (Std.isOfType(value, Int)) return setInt(name, cast value);
		if (Std.isOfType(value, Vector3D))
		{
			var v:Vector3D = cast value;
			return setVec3(name, v.x, v.y, v.z);
		}
		if (Std.isOfType(value, Array))
		{
			var a:Array<Dynamic> = cast value;
			if (a.length >= 16) return setMat4(name, cast a);
			if (a.length == 2) return setVec2(name, a[0], a[1]);
			if (a.length == 3) return setVec3(name, a[0], a[1], a[2]);
			if (a.length == 4) return setVec4(name, a[0], a[1], a[2], a[3]);
		}
		return false;
	}

	public static function glOf(ctx:Context3D):Dynamic
	{
		return @:privateAccess ctx.gl;
	}

	public static function invalidateIncludeCache():Void
	{
		includeCache = new StringMap();
	}

	public static function clearCache():Void
	{
		includeCache = new StringMap();
		for (k in variantCache.keys())
		{
			var s = variantCache.get(k);
			if (s != null)
			{
				s.shared = false;
				s.dispose();
			}
		}
		variantCache = new StringMap();
		current = null;
		compiled = 0;
		cacheHits = 0;
		errors = [];
	}

	public static function variantCount():Int
	{
		return Lambda.count(variantCache);
	}
}
