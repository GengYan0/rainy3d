package rainy.render3d.core;

import rainy.render3d.core.R3D.R3DBlend;
import rainy.render3d.core.R3D.R3DFace;
import rainy.render3d.core.R3DMaterial;
import rainy.render3d.core.R3DMesh;
import rainy.render3d.core.R3DShaders;

class R3DLines
{
	public var verts:Array<Float> = [];
	public var cols:Array<Float> = [];
	public var idx:Array<Int> = [];
	public var material:R3DMaterial;

	public function new(?mat:R3DMaterial)
	{
		material = mat;
		if (material == null)
		{
			material = new R3DMaterial(R3DShaders.lineShader());
			material.name = "debug-lines";
		}
		material.blendMode = R3DBlend.MIX;
		material.culling = R3DFace.BOTH;
		material.opaque = false;
	}

	public function segments():Int
	{
		return Std.int(idx.length * 0.5);
	}

	public function clear():Void
	{
		verts = [];
		cols = [];
		idx = [];
	}

	public static function col(r:Float, g:Float, b:Float, a:Float = 1.0):Int
	{
		return (Std.int(Math.max(0, Math.min(1, a)) * 255) << 24)
			| (Std.int(Math.max(0, Math.min(1, r)) * 255) << 16)
			| (Std.int(Math.max(0, Math.min(1, g)) * 255) << 8)
			| Std.int(Math.max(0, Math.min(1, b)) * 255);
	}

	inline function pushVert(x:Float, y:Float, z:Float, c:Int):Int
	{
		var i = Std.int(verts.length / 3);
		verts.push(x);
		verts.push(y);
		verts.push(z);
		cols.push(((c >> 16) & 0xFF) / 255.0);
		cols.push(((c >> 8) & 0xFF) / 255.0);
		cols.push((c & 0xFF) / 255.0);
		cols.push(((c >> 24) & 0xFF) / 255.0);
		return i;
	}

	public function line(x0:Float, y0:Float, z0:Float, x1:Float, y1:Float, z1:Float, c:Int):Void
	{
		var a = pushVert(x0, y0, z0, c);
		var b = pushVert(x1, y1, z1, c);
		idx.push(a);
		idx.push(b);
	}

	public function line2(x0:Float, y0:Float, z0:Float, c0:Int, x1:Float, y1:Float, z1:Float, c1:Int):Void
	{
		var a = pushVert(x0, y0, z0, c0);
		var b = pushVert(x1, y1, z1, c1);
		idx.push(a);
		idx.push(b);
	}

	public function box(minX:Float, minY:Float, minZ:Float, maxX:Float, maxY:Float, maxZ:Float, c:Int):Void
	{
		line(minX, minY, minZ, maxX, minY, minZ, c);
		line(maxX, minY, minZ, maxX, minY, maxZ, c);
		line(maxX, minY, maxZ, minX, minY, maxZ, c);
		line(minX, minY, maxZ, minX, minY, minZ, c);
		line(minX, maxY, minZ, maxX, maxY, minZ, c);
		line(maxX, maxY, minZ, maxX, maxY, maxZ, c);
		line(maxX, maxY, maxZ, minX, maxY, maxZ, c);
		line(minX, maxY, maxZ, minX, maxY, minZ, c);
		line(minX, minY, minZ, minX, maxY, minZ, c);
		line(maxX, minY, minZ, maxX, maxY, minZ, c);
		line(maxX, minY, maxZ, maxX, maxY, maxZ, c);
		line(minX, minY, maxZ, minX, maxY, maxZ, c);
	}

	public function circle(cx:Float, cy:Float, cz:Float, r:Float, axis:Int, seg:Int, c:Int):Void
	{
		if (seg < 3) seg = 3;
		var px = 0.0;
		var py = 0.0;
		var pz = 0.0;
		for (i in 0...(seg + 1))
		{
			var a = i / seg * Math.PI * 2;
			var ca = Math.cos(a) * r;
			var sa = Math.sin(a) * r;
			var x = cx;
			var y = cy;
			var z = cz;
			if (axis == 0)
			{
				x = cx;
				y = cy + ca;
				z = cz + sa;
			}
			else if (axis == 1)
			{
				x = cx + ca;
				y = cy;
				z = cz + sa;
			}
			else
			{
				x = cx + ca;
				y = cy + sa;
				z = cz;
			}
			if (i > 0) line(px, py, pz, x, y, z, c);
			px = x;
			py = y;
			pz = z;
		}
	}

	public function arrow(x:Float, y:Float, z:Float, dx:Float, dy:Float, dz:Float, len:Float, c:Int):Void
	{
		var l = Math.sqrt(dx * dx + dy * dy + dz * dz);
		if (l < 1e-6) return;
		dx /= l;
		dy /= l;
		dz /= l;
		var ex = x + dx * len;
		var ey = y + dy * len;
		var ez = z + dz * len;
		line(x, y, z, ex, ey, ez, c);
		var hx = 0.0;
		var hy = 0.0;
		var hz = 0.0;
		if (Math.abs(dy) < 0.9)
		{
			hx = -dz;
			hy = 0;
			hz = dx;
		}
		else
		{
			hx = 1;
			hy = 0;
			hz = 0;
		}
		var hl = Math.sqrt(hx * hx + hy * hy + hz * hz);
		if (hl < 1e-6) hl = 1;
		hx /= hl;
		hy /= hl;
		hz /= hl;
		var back = len * 0.22;
		var side = len * 0.08;
		line(ex, ey, ez, ex - dx * back + hx * side, ey - dy * back + hy * side, ez - dz * back + hz * side, c);
		line(ex, ey, ez, ex - dx * back - hx * side, ey - dy * back - hy * side, ez - dz * back - hz * side, c);
	}

	public function grid(cx:Float, cz:Float, half:Float, step:Float, cMinor:Int, cMajor:Int):Void
	{
		if (step <= 0.001) step = 0.5;
		var n = Std.int(half / step);
		if (n > 220) n = 220;
		var ext = n * step;
		for (i in -n...n + 1)
		{
			var off = i * step;
			var c = (i == 0) ? cMajor : ((i % 5 == 0) ? cMajor : cMinor);
			line(cx - ext, 0, cz + off, cx + ext, 0, cz + off, c);
			line(cx + off, 0, cz - ext, cx + off, 0, cz + ext, c);
		}
	}

	public function frustum(cam:R3DCamera, c:Int):Void
	{
		if (cam == null) return;
		var corners = new Array<Float>();
		var tanHalf = Math.tan(cam.fov * Math.PI / 360.0);
		var aspect = cam.aspect <= 0 ? 1.7778 : cam.aspect;
		var fwd:Array<Float> = [0.0, 0.0, 0.0];
		cam.forward(fwd);
		var upv:Array<Float> = [0.0, 0.0, 0.0];
		var rightv:Array<Float> = [0.0, 0.0, 0.0];
		var ux = 0.0;
		var uy = 1.0;
		var uz = 0.0;
		var rx = fwd[1] * uz - fwd[2] * uy;
		var ry = fwd[2] * ux - fwd[0] * uz;
		var rz = fwd[0] * uy - fwd[1] * ux;
		var rl = Math.sqrt(rx * rx + ry * ry + rz * rz);
		if (rl < 1e-6)
		{
			rx = 1;
			ry = 0;
			rz = 0;
			rl = 1;
		}
		rightv[0] = rx / rl;
		rightv[1] = ry / rl;
		rightv[2] = rz / rl;
		var bx = rightv[1] * fwd[2] - rightv[2] * fwd[1];
		var by = rightv[2] * fwd[0] - rightv[0] * fwd[2];
		var bz = rightv[0] * fwd[1] - rightv[1] * fwd[0];
		upv[0] = bx;
		upv[1] = by;
		upv[2] = bz;
		var d = Math.min(cam.far, 12.0);
		if (d < 0.5) d = 0.5;
		var hw = d * tanHalf * aspect;
		var hh = d * tanHalf;
		for (i in 0...4)
		{
			var sx = ((i == 0 || i == 3) ? -1.0 : 1.0) * hw;
			var sy = ((i < 2) ? 1.0 : -1.0) * hh;
			var px = cam.x + fwd[0] * d + rightv[0] * sx + upv[0] * sy;
			var py = cam.y + fwd[1] * d + rightv[1] * sx + upv[1] * sy;
			var pz = cam.z + fwd[2] * d + rightv[2] * sx + upv[2] * sy;
			corners.push(px);
			corners.push(py);
			corners.push(pz);
		}
		for (i in 0...4)
		{
			var j = (i + 1) % 4;
			line(cam.x, cam.y, cam.z, corners[i * 3], corners[i * 3 + 1], corners[i * 3 + 2], c);
			line(corners[i * 3], corners[i * 3 + 1], corners[i * 3 + 2], corners[j * 3], corners[j * 3 + 1], corners[j * 3 + 2], c);
		}
	}

	public function spotCone(x:Float, y:Float, z:Float, dx:Float, dy:Float, dz:Float, len:Float, spot:Float, c:Int):Void
	{
		var l = Math.sqrt(dx * dx + dy * dy + dz * dz);
		if (l < 1e-6) return;
		dx /= l;
		dy /= l;
		dz /= l;
		var ang = Math.acos(Math.max(-1, Math.min(1, 1 - spot * 2)));
		var rad = Math.tan(ang) * len;
		var ux = 0.0;
		var uy = 1.0;
		var uz = 0.0;
		var rx = dy * uz - dz * uy;
		var ry = dz * ux - dx * uz;
		var rz = dx * uy - dy * ux;
		var rl = Math.sqrt(rx * rx + ry * ry + rz * rz);
		if (rl < 1e-6)
		{
			rx = 1;
			ry = 0;
			rz = 0;
			rl = 1;
		}
		rx /= rl;
		ry /= rl;
		rz /= rl;
		var bx = ry * dz - rz * dy;
		var by = rz * dx - rx * dz;
		var bz = rx * dy - ry * dx;
		var seg = 12;
		var px = 0.0;
		var py = 0.0;
		var pz = 0.0;
		for (i in 0...(seg + 1))
		{
			var a = i / seg * Math.PI * 2;
			var ca = Math.cos(a) * rad;
			var sa = Math.sin(a) * rad;
			var ex = x + dx * len + rx * ca + bx * sa;
			var ey = y + dy * len + ry * ca + by * sa;
			var ez = z + dz * len + rz * ca + bz * sa;
			if (i > 0) line(px, py, pz, ex, ey, ez, c);
			if (i % 3 == 0) line(x, y, z, ex, ey, ez, c);
			px = ex;
			py = ey;
			pz = ez;
		}
	}

	public function build():R3DMesh
	{
		if (verts.length == 0 || idx.length == 0) return null;
		var m = new R3DMesh();
		m.setArrays(verts, null, idx, material, null, cols);
		m.primitive = 1;
		return m;
	}
}
