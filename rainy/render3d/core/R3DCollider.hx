package rainy.render3d.core;

enum abstract R3DColliderKind(Int) from Int to Int
{
	var BOX = 0;
	var SPHERE = 1;

	public function label():String
	{
		return this == BOX ? "盒" : "球";
	}
}

class R3DCollider
{
	public var kind:R3DColliderKind = R3DColliderKind.BOX;
	public var sx:Float = 1.0;
	public var sy:Float = 1.0;
	public var sz:Float = 1.0;
	public var radius:Float = 0.5;
	public var ox:Float = 0;
	public var oy:Float = 0;
	public var oz:Float = 0;
	public var trigger:Bool = false;
	public var layer:Int = 0;

	public function new() {}

	public function copy(o:R3DCollider):Void
	{
		if (o == null) return;
		kind = o.kind;
		sx = o.sx;
		sy = o.sy;
		sz = o.sz;
		radius = o.radius;
		ox = o.ox;
		oy = o.oy;
		oz = o.oz;
		trigger = o.trigger;
		layer = o.layer;
	}

	public function toJson():Dynamic
	{
		return {k: kind, sx: sx, sy: sy, sz: sz, r: radius, ox: ox, oy: oy, oz: oz, t: trigger, l: layer};
	}

	public static function fromJson(o:Dynamic):R3DCollider
	{
		if (o == null) return null;
		var c = new R3DCollider();
		c.kind = cast Std.int(num(Reflect.field(o, "k"), 0));
		c.sx = num(Reflect.field(o, "sx"), 1);
		c.sy = num(Reflect.field(o, "sy"), 1);
		c.sz = num(Reflect.field(o, "sz"), 1);
		c.radius = num(Reflect.field(o, "r"), 0.5);
		c.ox = num(Reflect.field(o, "ox"), 0);
		c.oy = num(Reflect.field(o, "oy"), 0);
		c.oz = num(Reflect.field(o, "oz"), 0);
		c.trigger = Reflect.field(o, "t") == true;
		c.layer = Std.int(num(Reflect.field(o, "l"), 0));
		return c;
	}

	static function num(v:Dynamic, d:Float):Float
	{
		if (v == null) return d;
		if (Std.isOfType(v, Float)) return cast v;
		if (Std.isOfType(v, Int)) return cast v;
		return d;
	}

	public function sizeText():String
	{
		if (kind == R3DColliderKind.SPHERE) return "r " + Std.int(radius * 100) / 100;
		return Std.int(sx * 100) / 100 + " x " + Std.int(sy * 100) / 100 + " x " + Std.int(sz * 100) / 100;
	}
}
