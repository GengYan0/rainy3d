package rainy.render3d.core;

import rainy.render3d.core.R3D.R3DBounds;
import openfl.geom.Vector3D;

class R3DMeshData
{
	public var positions:Array<Float> = [];
	public var uvs:Array<Float> = [];
	public var normals:Array<Float> = [];
	public var indices:Array<Int> = [];
	public var bounds:R3DBounds = new R3DBounds();
	public var name:String = "";

	public function new(?name:String)
	{
		if (name != null) this.name = name;
		clear();
	}

	public inline function vertexCount():Int
	{
		return Std.int(positions.length / 3);
	}

	public inline function triangleCount():Int
	{
		return Std.int(indices.length / 3);
	}

	public inline function isEmpty():Bool
	{
		return indices.length == 0;
	}

	public function clear():Void
	{
		positions = [];
		uvs = [];
		normals = [];
		indices = [];
		bounds.empty();
	}

	function track(x:Float, y:Float, z:Float):Void
	{
		bounds.addPoint(x, y, z);
	}

	public function trackRaw(index:Int, count:Int):Void
	{
		var i = index * 3;
		var end = i + count * 3;
		if (end > positions.length) end = positions.length;
		while (i + 2 < end)
		{
			track(positions[i], positions[i + 1], positions[i + 2]);
			i += 3;
		}
	}

	public function addVert(x:Float, y:Float, z:Float, u:Float, v:Float, nx:Float, ny:Float, nz:Float):Int
	{
		var i = Std.int(positions.length / 3);
		positions.push(x);
		positions.push(y);
		positions.push(z);
		uvs.push(u);
		uvs.push(v);
		normals.push(nx);
		normals.push(ny);
		normals.push(nz);
		track(x, y, z);
		return i;
	}

	public function addTri(a:Int, b:Int, c:Int):Void
	{
		indices.push(a);
		indices.push(b);
		indices.push(c);
	}

	public function addQuadIndexed(a:Int, b:Int, c:Int, d:Int, twoSided:Bool = false):Void
	{
		addTri(a, b, c);
		addTri(a, c, d);
		if (twoSided)
		{
			addTri(a, c, b);
			addTri(a, d, c);
		}
	}

	public function add(other:R3DMeshData):Void
	{
		var base = vertexCount();
		for (q in other.positions) positions.push(q);
		for (q in other.uvs) uvs.push(q);
		for (q in other.normals) normals.push(q);
		for (q in other.indices) indices.push(base + q);
		if (other.bounds.valid())
		{
			track(other.bounds.minX, other.bounds.minY, other.bounds.minZ);
			track(other.bounds.maxX, other.bounds.maxY, other.bounds.maxZ);
		}
	}

	public function recomputeBounds():Void
	{
		bounds.empty();
		var i = 0;
		while (i + 2 < positions.length)
		{
			track(positions[i], positions[i + 1], positions[i + 2]);
			i += 3;
		}
	}

	public function box(x:Float, y:Float, z:Float, w:Float, h:Float, d:Float):Void
	{
		R3DGeom.pushBox(this, x, y, z, w, h, d);
	}

	public function boxRot(cx:Float, cy:Float, cz:Float, w:Float, h:Float, d:Float, rx:Float, ry:Float, rz:Float):Void
	{
		R3DGeom.pushBoxRot(this, cx, cy, cz, w, h, d, rx, ry, rz);
	}

	public function quad(points:Array<Float>, nx:Float, ny:Float, nz:Float, twoSided:Bool = true):Void
	{
		R3DGeom.pushQuad(this, points, nx, ny, nz, twoSided);
	}

	public function ring(cx:Float, cy:Float, cz:Float, axis:Int, r:Float, thickness:Float, seg:Int):Void
	{
		R3DGeom.pushRing(this, cx, cy, cz, axis, r, thickness, seg);
	}
}

class R3DGeom
{
	static var _rc:Array<Float> = [0.0, 0.0, 0.0];

	public static function rotTo(out:Array<Float>, x:Float, y:Float, z:Float, rx:Float, ry:Float, rz:Float):Void
	{
		var cz = Math.cos(rz), sz = Math.sin(rz);
		var cy = Math.cos(ry), sy = Math.sin(ry);
		var cx = Math.cos(rx), sx = Math.sin(rx);
		var x1 = x * cz - y * sz;
		var y1 = x * sz + y * cz;
		var x2 = x1 * cy + z * sy;
		var z2 = -x1 * sy + z * cy;
		out[0] = x2;
		out[1] = y1 * cx - z2 * sx;
		out[2] = y1 * sx + z2 * cx;
	}

	public static function rotX(x:Float, y:Float, z:Float, r:Float):Array<Float>
	{
		var c = Math.cos(r), s = Math.sin(r);
		return [x, y * c - z * s, y * s + z * c];
	}

	public static function rotY(x:Float, y:Float, z:Float, r:Float):Array<Float>
	{
		var c = Math.cos(r), s = Math.sin(r);
		return [x * c + z * s, y, -x * s + z * c];
	}

	public static function rotZ(x:Float, y:Float, z:Float, r:Float):Array<Float>
	{
		var c = Math.cos(r), s = Math.sin(r);
		return [x * c - y * s, x * s + y * c, z];
	}

	public static function pushBox(m:R3DMeshData, x:Float, y:Float, z:Float, w:Float, h:Float, d:Float):Void
	{
		if (w <= 0 || h <= 0 || d <= 0) return;
		var x2 = x + w, y2 = y + h, z2 = z + d;
		var base = m.vertexCount();
		var p = [
			x, y, z2,  x2, y, z2,  x2, y2, z2,  x, y2, z2,
			x, y, z,   x, y2, z,   x2, y2, z,   x2, y, z,
			x, y2, z,  x, y2, z2,  x2, y2, z2,  x2, y2, z,
			x, y, z,   x2, y, z,   x2, y, z2,   x, y, z2,
			x2, y, z,  x2, y2, z,  x2, y2, z2,  x2, y, z2,
			x, y, z,   x, y, z2,   x, y2, z2,   x, y2, z
		];
		var top:Array<Float> = w >= d
			? [x, z, x2, z, x2, z2, x, z2]
			: [z, x, z2, x, z2, x2, z, x2];
		var bot:Array<Float> = w >= d
			? [x, z, x, z2, x2, z2, x2, z]
			: [z, x, z, x2, z2, x2, z2, x];
		var uvq:Array<Float> = [x, y, x2, y, x2, y2, x, y2];
		uvq = uvq.concat([x, y, x, y2, x2, y2, x2, y]);
		uvq = uvq.concat(top);
		uvq = uvq.concat(bot);
		uvq = uvq.concat([z, y, z, y2, z2, y2, z2, y, z, y, z2, y, z2, y2, z, y2]);
		var nm = [
			0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1,
			0, 0, -1, 0, 0, -1, 0, 0, -1, 0, 0, -1,
			0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0,
			0, -1, 0, 0, -1, 0, 0, -1, 0, 0, -1, 0,
			1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0,
			-1, 0, 0, -1, 0, 0, -1, 0, 0, -1, 0, 0
		];
		for (i in 0...p.length) m.positions.push(p[i]);
		for (i in 0...uvq.length) m.uvs.push(uvq[i]);
		for (i in 0...nm.length) m.normals.push(nm[i]);
		for (i in 0...24) m.trackRaw(base + i, 1);
		for (f in 0...6)
		{
			var o = base + f * 4;
			m.addTri(o, o + 1, o + 2);
			m.addTri(o, o + 2, o + 3);
		}
	}

	public static function pushBoxRot(m:R3DMeshData, cx:Float, cy:Float, cz:Float, w:Float, h:Float, d:Float,
		rx:Float, ry:Float, rz:Float):Void
	{
		if (rx == 0 && ry == 0 && rz == 0)
		{
			pushBox(m, cx - w * 0.5, cy - h * 0.5, cz - d * 0.5, w, h, d);
			return;
		}
		var t = new R3DMeshData();
		pushBox(t, -w * 0.5, -h * 0.5, -d * 0.5, w, h, d);
		var i = 0;
		while (i + 2 < t.positions.length)
		{
			rotTo(_rc, t.positions[i], t.positions[i + 1], t.positions[i + 2], rx, ry, rz);
			t.positions[i] = _rc[0] + cx;
			t.positions[i + 1] = _rc[1] + cy;
			t.positions[i + 2] = _rc[2] + cz;
			i += 3;
		}
		i = 0;
		while (i + 2 < t.normals.length)
		{
			rotTo(_rc, t.normals[i], t.normals[i + 1], t.normals[i + 2], rx, ry, rz);
			t.normals[i] = _rc[0];
			t.normals[i + 1] = _rc[1];
			t.normals[i + 2] = _rc[2];
			i += 3;
		}
		t.recomputeBounds();
		m.add(t);
	}

	public static function pushQuad(m:R3DMeshData, q:Array<Float>, nx:Float, ny:Float, nz:Float, twoSided:Bool = true):Void
	{
		if (q.length < 12) return;
		var base = m.vertexCount();
		for (k in 0...4)
			m.addVert(q[k * 3], q[k * 3 + 1], q[k * 3 + 2], 0, 0, nx, ny, nz);
		m.addQuadIndexed(base, base + 1, base + 2, base + 3, twoSided);
	}

	public static function pushRing(m:R3DMeshData, cx:Float, cy:Float, cz:Float, axis:Int, r:Float, thickness:Float, seg:Int):Void
	{
		if (seg < 3 || r <= 0) return;
		var nx = axis == 0 ? 1.0 : 0.0;
		var ny = axis == 1 ? 1.0 : 0.0;
		var nz = axis == 2 ? 1.0 : 0.0;
		var a0 = ringPoint(cx, cy, cz, axis, r, 0);
		var b0 = ringPoint(cx, cy, cz, axis, r + thickness, 0);
		for (k in 1...seg + 1)
		{
			var t = k / seg * Math.PI * 2;
			var a1 = ringPoint(cx, cy, cz, axis, r, t);
			var b1 = ringPoint(cx, cy, cz, axis, r + thickness, t);
			var base = m.vertexCount();
			m.addVert(a0[0], a0[1], a0[2], 0, 0, nx, ny, nz);
			m.addVert(b0[0], b0[1], b0[2], 0, 0, nx, ny, nz);
			m.addVert(b1[0], b1[1], b1[2], 0, 0, nx, ny, nz);
			m.addVert(a1[0], a1[1], a1[2], 0, 0, nx, ny, nz);
			m.addQuadIndexed(base, base + 1, base + 2, base + 3, true);
			a0 = a1;
			b0 = b1;
		}
	}

	public static function pushSphere(m:R3DMeshData, cx:Float, cy:Float, cz:Float, r:Float, segU:Int = 20,
		segV:Int = 12, yScale:Float = 1.0):Void
	{
		if (r <= 0) return;
		if (segU < 3) segU = 3;
		if (segV < 2) segV = 2;
		if (yScale < 0.0001) yScale = 0.0001;
		var prev:Array<Int> = [];
		for (v in 0...segV + 1)
		{
			var phi = v / segV * Math.PI;
			var sy = Math.cos(phi);
			var sr = Math.sin(phi);
			var row:Array<Int> = [];
			var u = 0;
			while (u < segU + 1)
			{
				var th = u / segU * Math.PI * 2;
				var nx = sr * Math.cos(th);
				var nz = sr * Math.sin(th);
				var ny = sy / yScale;
				var nl = Math.sqrt(nx * nx + ny * ny + nz * nz);
				if (nl < 1e-6) nl = 1;
				row.push(m.addVert(cx + nx * r, cy + sy * r * yScale, cz + nz * r,
					u / segU * 2, v / segV, nx / nl, ny / nl, nz / nl));
				u++;
			}
			if (v > 0)
			{
				u = 0;
				while (u < segU)
				{
					m.addQuadIndexed(prev[u], prev[u + 1], row[u + 1], row[u]);
					u++;
				}
			}
			prev = row;
		}
	}

	public static function pushCylinder(m:R3DMeshData, cx:Float, cy:Float, cz:Float, rBot:Float, rTop:Float,
		h:Float, seg:Int = 24, capped:Bool = true):Void
	{
		if (h <= 0) return;
		if (seg < 3) seg = 3;
		if (rBot < 0) rBot = 0;
		if (rTop < 0) rTop = 0;
		if (rBot <= 0 && rTop <= 0) return;
		var y1 = cy + h;
		var slope = (rBot - rTop) / h;
		var top:Array<Int> = [];
		var bot:Array<Int> = [];
		var u = 0;
		while (u < seg + 1)
		{
			var th = u / seg * Math.PI * 2;
			var ca = Math.cos(th);
			var sa = Math.sin(th);
			var nl = Math.sqrt(ca * ca + slope * slope + sa * sa);
			if (nl < 1e-6) nl = 1;
			var uu = u / seg * 2;
			top.push(m.addVert(cx + ca * rTop, y1, cz + sa * rTop, uu, 0, ca / nl, slope / nl, sa / nl));
			bot.push(m.addVert(cx + ca * rBot, cy, cz + sa * rBot, uu, 1, ca / nl, slope / nl, sa / nl));
			u++;
		}
		u = 0;
		while (u < seg)
		{
			m.addQuadIndexed(top[u], top[u + 1], bot[u + 1], bot[u]);
			u++;
		}
		if (!capped) return;
		if (rTop > 0.0001) cap(m, cx, y1, cz, rTop, seg, 1.0);
		if (rBot > 0.0001) cap(m, cx, cy, cz, rBot, seg, -1.0);
	}

	static function cap(m:R3DMeshData, cx:Float, y:Float, cz:Float, r:Float, seg:Int, up:Float):Void
	{
		var c = m.addVert(cx, y, cz, 0.5, 0.5, 0, up, 0);
		var i = 0;
		while (i < seg)
		{
			var a = i / seg * Math.PI * 2;
			var b = (i + 1) / seg * Math.PI * 2;
			var ia = m.addVert(cx + Math.cos(a) * r, y, cz + Math.sin(a) * r, Math.cos(a) * 0.5 + 0.5,
				Math.sin(a) * 0.5 + 0.5, 0, up, 0);
			var ib = m.addVert(cx + Math.cos(b) * r, y, cz + Math.sin(b) * r, Math.cos(b) * 0.5 + 0.5,
				Math.sin(b) * 0.5 + 0.5, 0, up, 0);
			if (up > 0) m.addTri(c, ib, ia);
			else m.addTri(c, ia, ib);
			i++;
		}
	}

	public static function pushPlane(m:R3DMeshData, cx:Float, cy:Float, cz:Float, w:Float, d:Float,
		doubleSided:Bool = true):Void
	{
		if (w <= 0 || d <= 0) return;
		var x0 = cx - w * 0.5, x1 = cx + w * 0.5;
		var z0 = cz - d * 0.5, z1 = cz + d * 0.5;
		pushQuad(m, [x0, cy, z1, x1, cy, z1, x1, cy, z0, x0, cy, z0], 0, 1, 0, doubleSided);
	}

	public static function ringPoint(cx:Float, cy:Float, cz:Float, axis:Int, r:Float, ang:Float):Array<Float>
	{
		var c = Math.cos(ang) * r;
		var s = Math.sin(ang) * r;
		if (axis == 0) return [cx, cy + c, cz + s];
		if (axis == 1) return [cx + s, cy, cz + c];
		return [cx + c, cy + s, cz];
	}

	public static function pushCone(m:R3DMeshData, cx:Float, cz:Float, yTop:Float, yBot:Float,
		botR:Float, topR:Float, seg:Int, twoSided:Bool = true):Void
	{
		if (seg < 3) return;
		var a0 = [cx + botR, yBot, cz];
		var b0 = [cx + topR, yTop, cz];
		for (k in 1...seg + 1)
		{
			var t = k / seg * Math.PI * 2;
			var a1 = [cx + Math.cos(t) * botR, yBot, cz + Math.sin(t) * botR];
			var b1 = [cx + Math.cos(t) * topR, yTop, cz + Math.sin(t) * topR];
			var mx = (a0[0] + a1[0]) * 0.5 - cx;
			var mz = (a0[2] + a1[2]) * 0.5 - cz;
			var nl = Math.sqrt(mx * mx + mz * mz);
			var nx = nl > 1e-6 ? mx / nl : 0.0;
			var nz = nl > 1e-6 ? mz / nl : 1.0;
			var base = m.vertexCount();
			m.addVert(a0[0], a0[1], a0[2], 0, 0, nx, 0.0, nz);
			m.addVert(b0[0], b0[1], b0[2], 0, 0, nx, 0.0, nz);
			m.addVert(b1[0], b1[1], b1[2], 0, 0, nx, 0.0, nz);
			m.addVert(a1[0], a1[1], a1[2], 0, 0, nx, 0.0, nz);
			m.addQuadIndexed(base, base + 1, base + 2, base + 3, twoSided);
			a0 = a1;
			b0 = b1;
		}
	}

	public static function pushDisc(m:R3DMeshData, cx:Float, y:Float, cz:Float, r:Float, seg:Int, up:Bool = true):Void
	{
		if (seg < 3 || r <= 0) return;
		var ny = up ? 1.0 : -1.0;
		var c = m.addVert(cx, y, cz, 0, 0, 0, ny, 0);
		for (k in 0...seg)
		{
			var t0 = k / seg * Math.PI * 2;
			var t1 = (k + 1) / seg * Math.PI * 2;
			var i0 = m.addVert(cx + Math.cos(t0) * r, y, cz + Math.sin(t0) * r, 0, 0, 0, ny, 0);
			var i1 = m.addVert(cx + Math.cos(t1) * r, y, cz + Math.sin(t1) * r, 0, 0, 0, ny, 0);
			if (up) m.addTri(c, i0, i1);
			else m.addTri(c, i1, i0);
		}
	}
}
