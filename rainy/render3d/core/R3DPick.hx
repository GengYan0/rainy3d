package rainy.render3d.core;

import rainy.render3d.core.R3D.R3DBounds;

class R3DRay
{
	public var ox:Float = 0;
	public var oy:Float = 0;
	public var oz:Float = 0;
	public var dx:Float = 0;
	public var dy:Float = 0;
	public var dz:Float = -1;

	public function new(ox:Float = 0, oy:Float = 0, oz:Float = 0, dx:Float = 0, dy:Float = 0, dz:Float = -1)
	{
		set(ox, oy, oz, dx, dy, dz);
	}

	public function set(ox:Float, oy:Float, oz:Float, dx:Float, dy:Float, dz:Float):R3DRay
	{
		this.ox = ox;
		this.oy = oy;
		this.oz = oz;
		var l = Math.sqrt(dx * dx + dy * dy + dz * dz);
		if (l < 1e-9) l = 1;
		this.dx = dx / l;
		this.dy = dy / l;
		this.dz = dz / l;
		return this;
	}

	public inline function pointAt(t:Float, out:Array<Float>):Array<Float>
	{
		out[0] = ox + dx * t;
		out[1] = oy + dy * t;
		out[2] = oz + dz * t;
		return out;
	}
}

class R3DPick
{
	static var slabTmin:Float = 0;
	static var slabTmax:Float = 1e30;

	static function slab(o:Float, d:Float, mn:Float, mx:Float):Bool
	{
		if (Math.abs(d) < 1e-9) return o >= mn && o <= mx;
		var inv = 1.0 / d;
		var t1 = (mn - o) * inv;
		var t2 = (mx - o) * inv;
		if (t1 > t2)
		{
			var tt = t1;
			t1 = t2;
			t2 = tt;
		}
		if (t1 > slabTmin) slabTmin = t1;
		if (t2 < slabTmax) slabTmax = t2;
		return slabTmax >= slabTmin;
	}

	public static function aabb(ray:R3DRay, b:R3DBounds):Float
	{
		slabTmin = 0.0;
		slabTmax = 1e30;
		if (!slab(ray.ox, ray.dx, b.minX, b.maxX)) return -1;
		if (!slab(ray.oy, ray.dy, b.minY, b.maxY)) return -1;
		if (!slab(ray.oz, ray.dz, b.minZ, b.maxZ)) return -1;
		if (slabTmax < 0) return -1;
		return slabTmin;
	}

	public static function triangle(ray:R3DRay, ax:Float, ay:Float, az:Float,
		bx:Float, by:Float, bz:Float, cx:Float, cy:Float, cz:Float):Float
	{
		var e1x = bx - ax, e1y = by - ay, e1z = bz - az;
		var e2x = cx - ax, e2y = cy - ay, e2z = cz - az;
		var px = ray.dy * e2z - ray.dz * e2y;
		var py = ray.dz * e2x - ray.dx * e2z;
		var pz = ray.dx * e2y - ray.dy * e2x;
		var det = e1x * px + e1y * py + e1z * pz;
		if (Math.abs(det) < 1e-9) return -1;
		var inv = 1.0 / det;
		var tx = ray.ox - ax, ty = ray.oy - ay, tz = ray.oz - az;
		var u = (tx * px + ty * py + tz * pz) * inv;
		if (u < -1e-5 || u > 1.00001) return -1;
		var qx = ty * e1z - tz * e1y;
		var qy = tz * e1x - tx * e1z;
		var qz = tx * e1y - ty * e1x;
		var v = (ray.dx * qx + ray.dy * qy + ray.dz * qz) * inv;
		if (v < -1e-5 || u + v > 1.00001) return -1;
		var t = (e2x * qx + e2y * qy + e2z * qz) * inv;
		return t > 1e-5 ? t : -1;
	}

	public static function quad(ray:R3DRay, p:Array<Float>):Float
	{
		var t = triangle(ray, p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8]);
		if (t >= 0) return t;
		return triangle(ray, p[0], p[1], p[2], p[6], p[7], p[8], p[9], p[10], p[11]);
	}

	public static function pickBounds(ray:R3DRay, list:Array<R3DBounds>):Int
	{
		var best = -1;
		var bestT = 1e30;
		for (i in 0...list.length)
		{
			var t = aabb(ray, list[i]);
			if (t >= 0 && t < bestT)
			{
				bestT = t;
				best = i;
			}
		}
		return best;
	}
}
