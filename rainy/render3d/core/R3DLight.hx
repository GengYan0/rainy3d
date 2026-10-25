package rainy.render3d.core;

enum abstract R3DLightType(Int) from Int to Int
{
	var DIRECTIONAL = 0;
	var POINT = 1;
	var SPOT = 2;

	public function label():String
	{
		return switch (cast this : Int)
		{
			case 0: "方向光";
			case 1: "点光";
			default: "聚光";
		}
	}
}

class R3DLight
{
	public var name:String;
	public var type:R3DLightType = R3DLightType.POINT;
	public var enabled:Bool = true;

	public var x:Float = 0;
	public var y:Float = 0;
	public var z:Float = 0;

	public var dirX:Float = 0;
	public var dirY:Float = -1;
	public var dirZ:Float = 0;

	public var r:Float = 1;
	public var g:Float = 1;
	public var b:Float = 1;
	public var energy:Float = 1;
	public var range:Float = 5;
	public var spot:Float = 0.55;
	public var castShadow:Bool = false;

	public function new(name:String = "light")
	{
		this.name = name;
	}

	public function setPos(px:Float, py:Float, pz:Float):R3DLight
	{
		x = px;
		y = py;
		z = pz;
		return this;
	}

	public function setDir(dx:Float, dy:Float, dz:Float):R3DLight
	{
		dirX = dx;
		dirY = dy;
		dirZ = dz;
		return this;
	}

	public function setColor(cr:Float, cg:Float, cb:Float):R3DLight
	{
		r = cr;
		g = cg;
		b = cb;
		return this;
	}

	public function aimAt(tx:Float, ty:Float, tz:Float):R3DLight
	{
		var dx = tx - x;
		var dy = ty - y;
		var dz = tz - z;
		var l = Math.sqrt(dx * dx + dy * dy + dz * dz);
		if (l < 1e-5) return this;
		dirX = dx / l;
		dirY = dy / l;
		dirZ = dz / l;
		return this;
	}

	public function copy(from:R3DLight):R3DLight
	{
		if (from == null) return this;
		name = from.name;
		type = from.type;
		enabled = from.enabled;
		x = from.x;
		y = from.y;
		z = from.z;
		dirX = from.dirX;
		dirY = from.dirY;
		dirZ = from.dirZ;
		r = from.r;
		g = from.g;
		b = from.b;
		energy = from.energy;
		range = from.range;
		spot = from.spot;
		castShadow = from.castShadow;
		return this;
	}

	public function toJson():Dynamic
	{
		return {
			name: name, type: type, on: enabled,
			x: x, y: y, z: z, dx: dirX, dy: dirY, dz: dirZ,
			r: r, g: g, b: b, energy: energy, range: range, spot: spot, shadow: castShadow
		};
	}

	public static function fromJson(o:Dynamic):R3DLight
	{
		if (o == null) return new R3DLight();
		var l = new R3DLight(o.name == null ? "light" : Std.string(o.name));
		l.type = o.type == null ? R3DLightType.POINT : cast o.type;
		l.enabled = o.on != false;
		l.x = num(o.x, 0);
		l.y = num(o.y, 0);
		l.z = num(o.z, 0);
		l.dirX = num(o.dx, 0);
		l.dirY = num(o.dy, -1);
		l.dirZ = num(o.dz, 0);
		l.r = num(o.r, 1);
		l.g = num(o.g, 1);
		l.b = num(o.b, 1);
		l.energy = num(o.energy, 1);
		l.range = num(o.range, 5);
		l.spot = num(o.spot, 0.55);
		l.castShadow = o.shadow == true;
		return l;
	}

	public static function num(v:Dynamic, d:Float):Float
	{
		if (v == null) return d;
		if (Std.isOfType(v, Float)) return cast v;
		if (Std.isOfType(v, Int)) return cast v;
		var f = Std.parseFloat("" + v);
		return Math.isNaN(f) ? d : f;
	}
}

class R3DLightRig
{
	public var lights:Array<R3DLight> = [];

	public var ambientR:Float = 0.03;
	public var ambientG:Float = 0.03;
	public var ambientB:Float = 0.035;
	public var skyR:Float = 0.05;
	public var skyG:Float = 0.05;
	public var skyB:Float = 0.06;
	public var groundR:Float = 0.02;
	public var groundG:Float = 0.02;
	public var groundB:Float = 0.022;
	public var ambientBoost:Float = 1.0;
	public var specPow:Float = 48;
	public var emissiveBoost:Float = 1.0;
	public var lightWrap:Float = 0.0;
	public var fogStart:Float = 0.0;
	public var fogEnd:Float = 0.0;
	public var fogR:Float = 0;
	public var fogG:Float = 0;
	public var fogB:Float = 0;
	public var autoAssignIndex:Int = -1;

	public function new() {}

	public function add(l:R3DLight):R3DLight
	{
		if (l == null) return null;
		lights.push(l);
		return l;
	}

	public function make(type:R3DLightType, name:String = null):R3DLight
	{
		var l = new R3DLight(name == null ? ("light" + (lights.length + 1)) : name);
		l.type = type;
		return add(l);
	}

	public function indexOf(l:R3DLight):Int
	{
		return lights.indexOf(l);
	}

	public function remove(l:R3DLight):Bool
	{
		return lights.remove(l);
	}

	public function removeAt(i:Int):Bool
	{
		if (i < 0 || i >= lights.length) return false;
		lights.splice(i, 1);
		return true;
	}

	public function swapOrder(i:Int, j:Int):Void
	{
		if (i < 0 || j < 0 || i >= lights.length || j >= lights.length || i == j) return;
		var t = lights[i];
		lights[i] = lights[j];
		lights[j] = t;
	}

	public function activeCount():Int
	{
		var n = 0;
		for (l in lights)
			if (l.enabled) n++;
		return n;
	}

	public function clear():Void
	{
		lights = [];
	}

	public function upload(sh:R3DShader):Int
	{
		if (sh == null) return 0;
		var i = 0;
		var n = 0;
		for (l in lights)
		{
			if (i >= R3DShader.MAX_LIGHTS) break;
			if (!l.enabled) continue;
			sh.setIntAt("uLightType", i, l.type);
			sh.setVec3At("uLightPos", i, l.x, l.y, l.z);
			sh.setVec3At("uLightDir", i, l.dirX, l.dirY, l.dirZ);
			sh.setVec3At("uLightColor", i, l.r, l.g, l.b);
			sh.setFloatAt("uLightEnergy", i, l.energy);
			sh.setFloatAt("uLightRange", i, l.range);
			sh.setFloatAt("uLightSpot", i, l.spot);
			sh.setFloatAt("uLightMask", i, 1.0);
			i++;
			n++;
		}
		while (i < R3DShader.MAX_LIGHTS)
		{
			sh.setFloatAt("uLightMask", i, 0.0);
			i++;
		}
		sh.setInt("uLightCount", n);
		sh.setVec3("uAmbient", ambientR, ambientG, ambientB);
		sh.setVec3("uAmbientSky", skyR, skyG, skyB);
		sh.setVec3("uAmbientGround", groundR, groundG, groundB);
		sh.setFloat("uAmbientBoost", ambientBoost);
		sh.setFloat("uSpecPow", specPow);
		sh.setFloat("uEmissiveBoost", emissiveBoost);
		sh.setFloat("uLightWrap", lightWrap);
		sh.setFloat("uFogStart", fogStart);
		sh.setFloat("uFogEnd", fogEnd);
		sh.setVec3("uFogColor", fogR, fogG, fogB);
		return n;
	}

	public function toJson():Dynamic
	{
		var arr = [];
		for (l in lights) arr.push(l.toJson());
		return {
			lights: arr,
			ar: ambientR, ag: ambientG, ab: ambientB,
			sr: skyR, sg: skyG, sb: skyB,
			gr: groundR, gg: groundG, gb: groundB,
			boost: ambientBoost, specPow: specPow, emissive: emissiveBoost, wrap: lightWrap,
			fogStart: fogStart, fogEnd: fogEnd, fogR: fogR, fogG: fogG, fogB: fogB
		};
	}

	public function fromJson(o:Dynamic):Void
	{
		if (o == null) return;
		lights = [];
		var arr:Dynamic = Reflect.field(o, "lights");
		if (arr != null && Std.isOfType(arr, Array))
			for (it in (cast arr : Array<Dynamic>))
				lights.push(R3DLight.fromJson(it));
		ambientR = R3DLight.num(Reflect.field(o, "ar"), ambientR);
		ambientG = R3DLight.num(Reflect.field(o, "ag"), ambientG);
		ambientB = R3DLight.num(Reflect.field(o, "ab"), ambientB);
		skyR = R3DLight.num(Reflect.field(o, "sr"), skyR);
		skyG = R3DLight.num(Reflect.field(o, "sg"), skyG);
		skyB = R3DLight.num(Reflect.field(o, "sb"), skyB);
		groundR = R3DLight.num(Reflect.field(o, "gr"), groundR);
		groundG = R3DLight.num(Reflect.field(o, "gg"), groundG);
		groundB = R3DLight.num(Reflect.field(o, "gb"), groundB);
		ambientBoost = R3DLight.num(Reflect.field(o, "boost"), ambientBoost);
		specPow = R3DLight.num(Reflect.field(o, "specPow"), specPow);
		emissiveBoost = R3DLight.num(Reflect.field(o, "emissive"), emissiveBoost);
		lightWrap = R3DLight.num(Reflect.field(o, "wrap"), lightWrap);
		fogStart = R3DLight.num(Reflect.field(o, "fogStart"), fogStart);
		fogEnd = R3DLight.num(Reflect.field(o, "fogEnd"), fogEnd);
		fogR = R3DLight.num(Reflect.field(o, "fogR"), fogR);
		fogG = R3DLight.num(Reflect.field(o, "fogG"), fogG);
		fogB = R3DLight.num(Reflect.field(o, "fogB"), fogB);
	}
}
