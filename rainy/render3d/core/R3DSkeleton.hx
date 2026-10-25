package rainy.render3d.core;

import rainy.render3d.host.R3DLog;
import rainy.render3d.core.R3DMat4;

class R3DBone
{
	public var name:String;
	public var parent:Int = -1;
	public var bind:Array<Float>;
	public var px:Float = 0;
	public var py:Float = 0;
	public var pz:Float = 0;
	public var rx:Float = 0;
	public var ry:Float = 0;
	public var rz:Float = 0;
	public var sx:Float = 1;
	public var sy:Float = 1;
	public var sz:Float = 1;
	public var local:Array<Float>;
	public var world:Array<Float>;
	public var skin:Array<Float>;

	public function new(?nm:String, parentIdx:Int = -1)
	{
		name = nm == null ? "bone" : nm;
		parent = parentIdx;
		bind = R3DMat4.identity();
		local = R3DMat4.identity();
		world = R3DMat4.identity();
		skin = R3DMat4.identity();
	}

	public function setRTS(px:Float, py:Float, pz:Float, rx:Float, ry:Float, rz:Float, s:Float):R3DBone
	{
		this.px = px;
		this.py = py;
		this.pz = pz;
		this.rx = rx;
		this.ry = ry;
		this.rz = rz;
		sx = s;
		sy = s;
		sz = s;
		local = R3DMat4.compose(px, py, pz, rx, ry, rz, s, s, s);
		return this;
	}

	public function setScale(s:Float):R3DBone
	{
		return setRTS(px, py, pz, rx, ry, rz, s);
	}
}

class R3DSkeleton
{
	public static var MAX_BONES:Int = 64;

	public var bones:Array<R3DBone> = [];
	public var name:String = "armature";

	public var version:Int = 0;

	var packed:Array<Float> = [];
	var packedCount:Int = 0;

	public function new(?nm:String)
	{
		if (nm != null) name = nm;
	}

	public function count():Int
	{
		return bones.length;
	}

	public function clear():Void
	{
		bones = [];
		packedCount = 0;
	}

	public function add(name:String, parent:Int = -1):Int
	{
		bones.push(new R3DBone(name, parent));
		return bones.length - 1;
	}

	public function find(name:String):Int
	{
		for (i in 0...bones.length)
			if (bones[i].name == name) return i;
		return -1;
	}

	public function boneAt(i:Int):R3DBone
	{
		return (i < 0 || i >= bones.length) ? null : bones[i];
	}

	public function compute():Void
	{
		for (i in 0...bones.length)
		{
			var b = bones[i];
			// A parent that comes later in the array has not been computed for this pose yet,
			// so this would read the previous pose's matrix (identity on the first call). GLTF
			// and most exporters happen to order parents first, which is why that ordering
			// looked mandatory; detect the violation instead of silently producing a wrong pose.
			if (b.parent >= i)
				R3DLog.warn('r3d', 'skeleton "' + name + '": 骨骼 ' + b.name + ' 的父索引 ' + b.parent + ' 未排在它之前，该帧姿态会用上一帧的父矩阵');
			if (b.parent < 0 || b.parent >= bones.length)
				b.world = b.local;
			else
				b.world = R3DMat4.multiplication(bones[b.parent].world, b.local);
		}
		for (b in bones)
			b.skin = R3DMat4.multiplication(b.world, b.bind);
		version++;
	}

	public function captureBindPose():Void
	{
		compute();
		for (b in bones)
			b.bind = R3DMat4.inverse(b.world);
		compute();
	}

	public function setBindFromCurrent():Void
	{
		for (b in bones)
			b.bind = R3DMat4.inverse(b.world);
		compute();
	}

	public function pack():Array<Float>
	{
		var n = bones.length;
		if (n > MAX_BONES) n = MAX_BONES;
		var need = n * 16;
		if (packed.length < need)
		{
			packed.resize(need);
			var i = 0;
			while (i < need)
			{
				packed[i] = 0;
				i++;
			}
		}
		for (i in 0...n)
		{
			var s = bones[i].skin;
			var o = i * 16;
			var c = 0;
			while (c < 4)
			{
				var r = 0;
				while (r < 4)
				{
					packed[o + c * 4 + r] = s[r * 4 + c];
					r++;
				}
				c++;
			}
		}
		packedCount = n;
		return packed;
	}

	public function packedSize():Int
	{
		return packedCount;
	}

	public function flat():Array<Float>
	{
		return pack();
	}

	public function toJson():Dynamic
	{
		var bs:Array<Dynamic> = [];
		for (b in bones)
			bs.push({
				name: b.name, parent: b.parent,
				px: b.px, py: b.py, pz: b.pz,
				rx: b.rx, ry: b.ry, rz: b.rz, s: b.sx
			});
		return {name: name, bones: bs};
	}

	public function fromJson(o:Dynamic):Bool
	{
		if (o == null) return false;
		try
		{
			if (o.name != null) name = o.name;
			bones = [];
			var bs:Array<Dynamic> = o.bones;
			if (bs == null) return false;
			for (d in bs)
			{
				var i = add(d.name, d.parent == null ? -1 : Std.int(d.parent));
				var s = d.s == null ? 1.0 : cast d.s;
				bones[i].setRTS(cast d.px, cast d.py, cast d.pz, cast d.rx, cast d.ry, cast d.rz, s);
			}
			compute();
			captureBindPose();
			return true;
		}
		catch (e:Dynamic)
		{
			// The loop above adds bones as it parses, so a malformed entry left the skeleton in
			// a half-filled state that looks valid to every later caller. Reset it.
			clear();
			return false;
		}
	}
}
