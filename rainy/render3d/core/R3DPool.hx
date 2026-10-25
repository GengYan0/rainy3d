package rainy.render3d.core;

import haxe.ds.StringMap;
import rainy.render3d.core.R3DMaterial;
import rainy.render3d.core.R3DMesh;
import rainy.render3d.core.R3DTexture;
import rainy.render3d.core.R3DShader;

class R3DPoolSlot
{
	public var key:String;
	public var refs:Int = 0;
	public var born:Float = 0;
	public var used:Float = 0;
	public var bytes:Int = 0;

	public function new(key:String, t:Float)
	{
		this.key = key;
		born = t;
		used = t;
	}

	public function alive():Bool
	{
		return refs > 0;
	}
}

class R3DPool
{
	public static var enable:Bool = true;
	public static var idleSeconds:Float = 45.0;
	public static var budgetBytes:Int = 256 * 1024 * 1024;

	public static var hits:Int = 0;
	public static var misses:Int = 0;
	public static var evicted:Int = 0;

	static var texSlots:StringMap<R3DPoolSlot> = new StringMap();
	static var texValues:StringMap<R3DTexture> = new StringMap();
	static var meshSlots:StringMap<R3DPoolSlot> = new StringMap();
	static var meshValues:StringMap<R3DMesh> = new StringMap();
	static var shaderSlots:StringMap<R3DPoolSlot> = new StringMap();
	static var shaderValues:StringMap<R3DShader> = new StringMap();

	public static function texture(path:String, ?params:{?wrapMode:R3D.R3DWrap, ?filter:R3D.R3DFilter, ?mipFilter:R3D.R3DMipFilter, ?anisotropy:Int}):R3DTexture
	{
		if (path == null || path.length == 0) return null;
		var key = "t|" + path + "|" + (params == null ? "" : sign(params));
		var slot = texSlots.get(key);
		if (slot != null)
		{
			var t = texValues.get(key);
			if (t != null && !t.disposed)
			{
				slot.refs++;
				slot.used = now();
				hits++;
				return t;
			}
		}
		misses++;
		var made = R3DTexture.fromFile(path, params);
		if (made == null) return null;
		slot = new R3DPoolSlot(key, now());
		slot.refs = 1;
		slot.bytes = made.width * made.height * 4;
		texSlots.set(key, slot);
		texValues.set(key, made);
		return made;
	}

	public static function releaseTexture(t:R3DTexture):Void
	{
		if (t == null) return;
		for (key in texSlots.keys())
		{
			if (texValues.get(key) != t) continue;
			var slot = texSlots.get(key);
			if (slot != null && slot.refs > 0) slot.refs--;
			return;
		}
	}

	public static function mesh(key:String, build:Void->R3DMesh):R3DMesh
	{
		if (key == null) return build == null ? null : build();
		var slot = meshSlots.get(key);
		if (slot != null)
		{
			var m = meshValues.get(key);
			if (m != null && !m.disposed)
			{
				slot.refs++;
				slot.used = now();
				hits++;
				return m;
			}
		}
		misses++;
		var made = build == null ? null : build();
		if (made == null) return null;
		slot = new R3DPoolSlot(key, now());
		slot.refs = 1;
		slot.bytes = made.vertices * 32 + made.indexCount * 2;
		meshSlots.set(key, slot);
		meshValues.set(key, made);
		return made;
	}

	public static function releaseMesh(m:R3DMesh):Void
	{
		if (m == null) return;
		for (key in meshSlots.keys())
		{
			if (meshValues.get(key) != m) continue;
			var slot = meshSlots.get(key);
			if (slot != null && slot.refs > 0) slot.refs--;
			return;
		}
	}

	public static function shader(key:String, build:Void->R3DShader):R3DShader
	{
		if (key == null) return build == null ? null : build();
		var slot = shaderSlots.get(key);
		if (slot != null)
		{
			var s = shaderValues.get(key);
			if (s != null && !s.failed)
			{
				slot.refs++;
				slot.used = now();
				hits++;
				return s;
			}
		}
		misses++;
		var made = build == null ? null : build();
		if (made == null) return null;
		slot = new R3DPoolSlot(key, now());
		slot.refs = 1;
		slot.bytes = (made.vertSource.length + made.fragSource.length) * 2;
		shaderSlots.set(key, slot);
		shaderValues.set(key, made);
		return made;
	}

	public static function releaseShader(s:R3DShader):Void
	{
		if (s == null) return;
		for (key in shaderSlots.keys())
		{
			if (shaderValues.get(key) != s) continue;
			var slot = shaderSlots.get(key);
			if (slot != null && slot.refs > 0) slot.refs--;
			return;
		}
	}

	public static function sweep(?budget:Int):Int
	{
		var limit = budget == null ? budgetBytes : budget;
		var t = now();
		var freed = 0;
		var total = usedBytes();
		for (key in keysOf(texSlots))
		{
			var slot = texSlots.get(key);
			if (slot == null || slot.alive()) continue;
			if (total - freed <= limit && t - slot.used < idleSeconds) continue;
			var v = texValues.get(key);
			if (v != null) v.dispose();
			texValues.remove(key);
			texSlots.remove(key);
			freed += slot.bytes;
			evicted++;
		}
		for (key in keysOf(meshSlots))
		{
			var slot = meshSlots.get(key);
			if (slot == null || slot.alive()) continue;
			if (total - freed <= limit && t - slot.used < idleSeconds) continue;
			var v = meshValues.get(key);
			if (v != null) v.dispose();
			meshValues.remove(key);
			meshSlots.remove(key);
			freed += slot.bytes;
			evicted++;
		}
		return freed;
	}

	public static function usedBytes():Int
	{
		var n = 0;
		for (key in texSlots.keys())
		{
			var s = texSlots.get(key);
			if (s != null) n += s.bytes;
		}
		for (key in meshSlots.keys())
		{
			var s = meshSlots.get(key);
			if (s != null) n += s.bytes;
		}
		for (key in shaderSlots.keys())
		{
			var s = shaderSlots.get(key);
			if (s != null) n += s.bytes;
		}
		return n;
	}

	public static function usedByKind():Array<Int>
	{
		var a:Array<Int> = [0, 0, 0, 0, 0, 0];
		for (key in texSlots.keys())
		{
			var s = texSlots.get(key);
			if (s == null) continue;
			a[0] += 1;
			a[3] += s.bytes;
		}
		for (key in meshSlots.keys())
		{
			var s = meshSlots.get(key);
			if (s == null) continue;
			a[1] += 1;
			a[4] += s.bytes;
		}
		for (key in shaderSlots.keys())
		{
			var s = shaderSlots.get(key);
			if (s == null) continue;
			a[2] += 1;
			a[5] += s.bytes;
		}
		return a;
	}

	public static function stats():String
	{
		var a = usedByKind();
		return "池 贴图" + a[0] + "/" + Std.int(a[3] / 1024) + "KB"
			+ " 网格" + a[1] + "/" + Std.int(a[4] / 1024) + "KB"
			+ " 着色器" + a[2] + " 命中" + hits + " 未命中" + misses + " 淘汰" + evicted;
	}

	public static function clear():Void
	{
		for (key in texValues.keys())
		{
			var v = texValues.get(key);
			if (v != null) v.dispose();
		}
		for (key in meshValues.keys())
		{
			var v = meshValues.get(key);
			if (v != null) v.dispose();
		}
		texSlots = new StringMap();
		texValues = new StringMap();
		meshSlots = new StringMap();
		meshValues = new StringMap();
		shaderSlots = new StringMap();
		shaderValues = new StringMap();
	}

	static function keysOf(m:StringMap<R3DPoolSlot>):Array<String>
	{
		var out:Array<String> = [];
		for (k in m.keys()) out.push(k);
		return out;
	}

	static inline function now():Float
	{
		return haxe.Timer.stamp();
	}

	static function sign(p:Dynamic):String
	{
		var s = "";
		if (p.wrapMode != null) s += "w" + (cast p.wrapMode : Int);
		if (p.filter != null) s += "f" + (cast p.filter : Int);
		if (p.mipFilter != null) s += "m" + (cast p.mipFilter : Int);
		if (p.anisotropy != null) s += "a" + (cast p.anisotropy : Int);
		return s;
	}
}
