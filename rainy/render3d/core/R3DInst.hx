package rainy.render3d.core;

import rainy.render3d.host.R3DLog;
import lime.graphics.opengl.GL;
import lime.utils.Float32Array;
import rainy.render3d.core.R3D.R3DBounds;
import rainy.render3d.core.R3DMaterial;
import rainy.render3d.core.R3DMesh;
import rainy.render3d.core.R3DModel;
import rainy.render3d.core.R3DShader;

class R3DInstBatch
{
	public static inline var FLOATS:Int = 20;

	public var name:String = "";
	public var mesh:R3DMesh;
	public var material:R3DMaterial;
	public var visible:Bool = true;
	public var colorEnabled:Bool = false;
	public var bounds:R3DBounds = new R3DBounds();
	public var count(default, null):Int = 0;
	public var capacity(default, null):Int = 0;

	var capacityDirty:Bool = true;
	var dataDirty:Bool = true;
	var vbo:Dynamic = null;
	var buf:Float32Array = null;
	var scratch:Array<Float> = [0.0, 0.0, 0.0];

	public function new(mesh:R3DMesh, material:R3DMaterial, capacity:Int = 64)
	{
		this.mesh = mesh;
		this.material = material;
		reserve(capacity);
	}

	public function reserve(n:Int):Void
	{
		if (n <= capacity) return;
		var cap = capacity < 64 ? 64 : capacity;
		while (cap < n) cap = cap * 2;
		var nb = new Float32Array(cap * FLOATS);
		if (buf != null)
		{
			var keep = capacity * FLOATS;
			var i = 0;
			while (i < keep)
			{
				nb[i] = buf[i];
				i++;
			}
		}
		buf = nb;
		capacity = cap;
		capacityDirty = true;
		dataDirty = true;
	}

	public function clear():Void
	{
		count = 0;
		dataDirty = true;
		bounds.empty();
	}

	public function add(m:R3DModel, r:Float = 1, g:Float = 1, b:Float = 1, a:Float = 1):Int
	{
		var i = count;
		reserve(i + 1);
		count = i + 1;
		setMatrixAt(i, m);
		if (colorEnabled) setColorAt(i, r, g, b, a);
		addBounds(m);
		return i;
	}

	public function setMatrixAt(i:Int, m:R3DModel):Void
	{
		if (i < 0 || i >= capacity) return;
		m.updateWorld();
		var o = i * FLOATS;
		var w = m.world;
		var k = 0;
		while (k < 16)
		{
			buf[o + k] = k < w.length ? w[k] : 0;
			k++;
		}
		dataDirty = true;
	}

	public function setMatrixRaw(i:Int, w:Array<Float>):Void
	{
		if (i < 0 || i >= capacity) return;
		var o = i * FLOATS;
		var k = 0;
		while (k < 16)
		{
			buf[o + k] = k < w.length ? w[k] : 0;
			k++;
		}
		dataDirty = true;
	}

	public function setColorAt(i:Int, r:Float, g:Float, b:Float, a:Float = 1):Void
	{
		if (i < 0 || i >= capacity) return;
		var o = i * FLOATS + 16;
		buf[o] = r;
		buf[o + 1] = g;
		buf[o + 2] = b;
		buf[o + 3] = a;
		dataDirty = true;
	}

	public function addBounds(m:R3DModel):Void
	{
		var b = m.worldBounds();
		if (!b.valid()) return;
		for (c in 0...8)
		{
			R3DMat4.transformPoint(m.world, (c & 1) != 0 ? b.maxX : b.minX, (c & 2) != 0 ? b.maxY : b.minY,
				(c & 4) != 0 ? b.maxZ : b.minZ, scratch);
			bounds.addPoint(scratch[0], scratch[1], scratch[2]);
		}
	}

	static var m16:Array<Float> = [
		0.0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	];

	public function rebuildBounds():Void
	{
		bounds.empty();
		for (i in 0...count)
		{
			var o = i * FLOATS;
			var k = 0;
			while (k < 16)
			{
				m16[k] = buf[o + k];
				k++;
			}
			for (c in 0...8)
			{
				R3DMat4.transformPoint(m16, (c & 1) != 0 ? mesh.bounds.maxX : mesh.bounds.minX,
					(c & 2) != 0 ? mesh.bounds.maxY : mesh.bounds.minY,
					(c & 4) != 0 ? mesh.bounds.maxZ : mesh.bounds.minZ, scratch);
				bounds.addPoint(scratch[0], scratch[1], scratch[2]);
			}
		}
	}

	public function upload():Void
	{
		if (buf == null || count <= 0) return;
		if (vbo == null)
		{
			vbo = GL.createBuffer();
			capacityDirty = true;
		}
		if (!capacityDirty && !dataDirty) return;
		GL.bindBuffer(GL.ARRAY_BUFFER, vbo);
		var bytes = count * FLOATS * 4;
		GL.bufferData(GL.ARRAY_BUFFER, bytes, buf, GL.DYNAMIC_DRAW);
		capacityDirty = false;
		dataDirty = false;
	}

	public function bind(sh:R3DShader):Bool
	{
		if (sh == null || !sh.instanced || vbo == null || count <= 0) return false;
		var stride = FLOATS * 4;
		GL.bindBuffer(GL.ARRAY_BUFFER, vbo);
		setAttr(sh.attrInst0, stride, 0);
		setAttr(sh.attrInst1, stride, 16);
		setAttr(sh.attrInst2, stride, 32);
		setAttr(sh.attrInst3, stride, 48);
		if (colorEnabled) setAttr(sh.attrColorI, stride, 64);
		else clearAttr(sh.attrColorI);
		return true;
	}

	public function unbind(sh:R3DShader):Void
	{
		if (sh == null) return;
		clearAttr(sh.attrInst0);
		clearAttr(sh.attrInst1);
		clearAttr(sh.attrInst2);
		clearAttr(sh.attrInst3);
		clearAttr(sh.attrColorI);
	}

	static function setAttr(loc:Int, stride:Int, offset:Int):Void
	{
		if (loc < 0) return;
		GL.enableVertexAttribArray(loc);
		GL.vertexAttribPointer(loc, 4, GL.FLOAT, false, stride, cast offset);
		GL.vertexAttribDivisor(loc, 1);
	}

	static function clearAttr(loc:Int):Void
	{
		if (loc < 0) return;
		GL.vertexAttribDivisor(loc, 0);
		GL.disableVertexAttribArray(loc);
	}

	public function bytes():Int
	{
		return capacity * FLOATS * 4;
	}

	public function info():String
	{
		return name + " " + count + "/" + capacity + "  " + Std.int(bytes() / 1024) + "KB";
	}

	public function dispose():Void
	{
		if (vbo != null)
		{
			try GL.deleteBuffer(vbo) catch (e:Dynamic) { R3DLog.silentFailure("R3DInstSet.dispose", e); }
			vbo = null;
		}
		buf = null;
		count = 0;
		capacity = 0;
	}
}

class R3DInstSet
{
	public var batches:Array<R3DInstBatch> = [];
	var byKey:haxe.ds.StringMap<R3DInstBatch> = new haxe.ds.StringMap();

	public function new() {}

	public function batch(key:String, mesh:R3DMesh, material:R3DMaterial, capacity:Int = 64):R3DInstBatch
	{
		var b = byKey.get(key);
		if (b != null) return b;
		b = new R3DInstBatch(mesh, material, capacity);
		b.name = key;
		byKey.set(key, b);
		batches.push(b);
		return b;
	}

	public function get(key:String):R3DInstBatch
	{
		return byKey.get(key);
	}

	public function remove(key:String):Void
	{
		var b = byKey.get(key);
		if (b == null) return;
		byKey.remove(key);
		batches.remove(b);
		b.dispose();
	}

	public function clear():Void
	{
		for (b in batches) b.clear();
	}

	public function totalInstances():Int
	{
		var n = 0;
		for (b in batches)
			n += b.count;
		return n;
	}

	public function totalBytes():Int
	{
		var n = 0;
		for (b in batches)
			n += b.bytes();
		return n;
	}

	public function info():String
	{
		return "实例批 " + batches.length + " · 实例 " + totalInstances() + " · " + Std.int(totalBytes() / 1024) + "KB";
	}

	public function dispose():Void
	{
		for (b in batches) b.dispose();
		batches = [];
		byKey = new haxe.ds.StringMap();
	}
}
