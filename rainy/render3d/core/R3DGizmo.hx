package rainy.render3d.core;

import rainy.render3d.core.R3DCamera;
import rainy.render3d.core.R3DLines;

enum abstract R3DGizmoMode(Int) from Int to Int
{
	var MOVE = 0;
	var ROTATE = 1;
	var SCALE = 2;

	public function label():String
	{
		return switch (cast this : Int)
		{
			case 0: "移动";
			case 1: "旋转";
			default: "缩放";
		}
	}
}

class R3DGizmo
{
	public static inline var AXIS_X:Int = 0;
	public static inline var AXIS_Y:Int = 1;
	public static inline var AXIS_Z:Int = 2;
	public static inline var AXIS_ALL:Int = 3;

	public var mode:R3DGizmoMode = R3DGizmoMode.MOVE;
	public var activeAxis:Int = -1;
	public var screenRadius:Float = 13.0;
	public var sizeMeters:Float = 0.55;

	var startT:Float = 0;
	var startAngle:Float = 0;
	var accAngle:Float = 0;
	var startPt:Array<Float> = null;
	var lastAngle:Float = 0;

	static var _p:Array<Float> = [0.0, 0.0, 0.0, 0.0];

	public function new() {}

	public static function axisDir(axis:Int, out:Array<Float>):Void
	{
		out[0] = axis == 0 ? 1.0 : 0.0;
		out[1] = axis == 1 ? 1.0 : 0.0;
		out[2] = axis == 2 ? 1.0 : 0.0;
	}

	public function axisLength(scale:Float):Float
	{
		return Math.max(0.05, sizeMeters * scale);
	}

	public function build(out:R3DLines, cam:R3DCamera, px:Float, py:Float, pz:Float, scale:Float):Void
	{
		var len = axisLength(scale);
		var c = [R3DLines.col(1, 0.32, 0.32), R3DLines.col(0.38, 1, 0.42), R3DLines.col(0.36, 0.65, 1)];
		if (mode == R3DGizmoMode.ROTATE)
		{
			for (a in 0...3)
				out.circle(px, py, pz, len, a, 28, c[a]);
			return;
		}
		for (a in 0...3)
		{
			var dx = a == 0 ? 1.0 : 0.0;
			var dy = a == 1 ? 1.0 : 0.0;
			var dz = a == 2 ? 1.0 : 0.0;
			out.arrow(px, py, pz, dx, dy, dz, len, c[a]);
			if (mode == R3DGizmoMode.SCALE)
			{
				var e = len * 0.06;
				out.box(px + dx * len - e, py + dy * len - e, pz + dz * len - e, px + dx * len + e, py + dy * len + e,
					pz + dz * len + e, c[a]);
			}
		}
		var s = len * 0.055;
		out.box(px - s, py - s, pz - s, px + s, py + s, pz + s, R3DLines.col(0.95, 0.95, 0.95));
	}

	public function pick(cam:R3DCamera, sx:Float, sy:Float, w:Float, h:Float, px:Float, py:Float, pz:Float,
			scale:Float):Int
	{
		var len = axisLength(scale);
		if (mode == R3DGizmoMode.ROTATE)
		{
			var best = -1;
			var bestD = screenRadius * 1.7;
			for (a in 0...3)
			{
				var d = ringDistance(cam, sx, sy, w, h, px, py, pz, len, a);
				if (d < bestD)
				{
					bestD = d;
					best = a;
				}
			}
			return best;
		}
		var ox:Array<Float> = [0.0, 0.0, 0.0, 0.0];
		var ex:Array<Float> = [0.0, 0.0, 0.0, 0.0];
		if (!cam.worldToScreen(px, py, pz, w, h, ox)) return -1;
		var bestAxis = -1;
		var bestDist = screenRadius;
		var dsq = (sx - ox[0]) * (sx - ox[0]) + (sy - ox[1]) * (sy - ox[1]);
		if (dsq < bestDist * bestDist)
		{
			bestDist = Math.sqrt(dsq);
			bestAxis = AXIS_ALL;
		}
		for (a in 0...3)
		{
			var dx = a == 0 ? 1.0 : 0.0;
			var dy = a == 1 ? 1.0 : 0.0;
			var dz = a == 2 ? 1.0 : 0.0;
			if (!cam.worldToScreen(px + dx * len, py + dy * len, pz + dz * len, w, h, ex)) continue;
			var d = segDist(sx, sy, ox[0], ox[1], ex[0], ex[1]);
			if (d < bestDist)
			{
				bestDist = d;
				bestAxis = a;
			}
		}
		return bestAxis;
	}

	static function segDist(px:Float, py:Float, x0:Float, y0:Float, x1:Float, y1:Float):Float
	{
		var dx = x1 - x0;
		var dy = y1 - y0;
		var l2 = dx * dx + dy * dy;
		if (l2 < 1e-6) return Math.sqrt((px - x0) * (px - x0) + (py - y0) * (py - y0));
		var t = ((px - x0) * dx + (py - y0) * dy) / l2;
		if (t < 0) t = 0;
		if (t > 1) t = 1;
		var cx = x0 + t * dx;
		var cy = y0 + t * dy;
		return Math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
	}

	static function ringDistance(cam:R3DCamera, sx:Float, sy:Float, w:Float, h:Float, px:Float, py:Float, pz:Float,
			r:Float, axis:Int):Float
	{
		var seg = 28;
		var best = 1e9;
		var a:Array<Float> = [0.0, 0.0, 0.0, 0.0];
		var b:Array<Float> = [0.0, 0.0, 0.0, 0.0];
		var okA = false;
		for (i in 0...(seg + 1))
		{
			var t = i / seg * Math.PI * 2;
			var ca = Math.cos(t) * r;
			var sa = Math.sin(t) * r;
			var x = px;
			var y = py;
			var z = pz;
			if (axis == 0)
			{
				y = py + ca;
				z = pz + sa;
			}
			else if (axis == 1)
			{
				x = px + ca;
				z = pz + sa;
			}
			else
			{
				x = px + ca;
				y = py + sa;
			}
			var ok = cam.worldToScreen(x, y, z, w, h, b);
			if (ok && okA) best = Math.min(best, segDist(sx, sy, a[0], a[1], b[0], b[1]));
			for (k in 0...3)
			{
				a[k] = b[k];
			}
			okA = ok;
		}
		return best;
	}

	public function lineT(px:Float, py:Float, pz:Float, axis:Int, cam:R3DCamera, mx:Float, my:Float, w:Float, h:Float):Float
	{
		var dx = axis == 0 ? 1.0 : 0.0;
		var dy = axis == 1 ? 1.0 : 0.0;
		var dz = axis == 2 ? 1.0 : 0.0;
		var ray = cam.screenRay(mx, my, w, h);
		var wx = px - ray.ox;
		var wy = py - ray.oy;
		var wz = pz - ray.oz;
		var a = ray.dx * ray.dx + ray.dy * ray.dy + ray.dz * ray.dz;
		var b = ray.dx * dx + ray.dy * dy + ray.dz * dz;
		var d = ray.dx * wx + ray.dy * wy + ray.dz * wz;
		var e = dx * wx + dy * wy + dz * wz;
		var den = a - b * b;
		if (Math.abs(den) < 1e-9) return 0.0;
		return (a * e - b * d) / den;
	}

	public function planeHit(px:Float, py:Float, pz:Float, cam:R3DCamera, mx:Float, my:Float, w:Float, h:Float):Array<Float>
	{
		var fwd:Array<Float> = [0.0, 0.0, 0.0];
		cam.forward(fwd);
		var ray = cam.screenRay(mx, my, w, h);
		var den = ray.dx * fwd[0] + ray.dy * fwd[1] + ray.dz * fwd[2];
		if (Math.abs(den) < 1e-7) return null;
		var t = ((px - ray.ox) * fwd[0] + (py - ray.oy) * fwd[1] + (pz - ray.oz) * fwd[2]) / den;
		return [ray.ox + ray.dx * t, ray.oy + ray.dy * t, ray.oz + ray.dz * t];
	}

	public function beginDrag(axis:Int, cam:R3DCamera, mx:Float, my:Float, w:Float, h:Float, px:Float, py:Float,
			pz:Float, scale:Float):Void
	{
		activeAxis = axis;
		accAngle = 0;
		startPt = null;
		if (mode == R3DGizmoMode.ROTATE)
		{
			startAngle = screenAngle(cam, mx, my, w, h, px, py, pz);
			lastAngle = startAngle;
		}
		else if (axis == AXIS_ALL) startPt = planeHit(px, py, pz, cam, mx, my, w, h);
		else startT = lineT(px, py, pz, axis, cam, mx, my, w, h);
	}

	public function drag(cam:R3DCamera, mx:Float, my:Float, w:Float, h:Float, px:Float, py:Float, pz:Float, scale:Float,
			snap:Float, out:Array<Float>):Void
	{
		out[0] = 0;
		out[1] = 0;
		out[2] = 0;
		out[3] = 0;
		if (activeAxis < 0) return;
		if (mode == R3DGizmoMode.ROTATE)
		{
			var cur = screenAngle(cam, mx, my, w, h, px, py, pz);
			var d = cur - lastAngle;
			while (d > Math.PI) d -= Math.PI * 2;
			while (d < -Math.PI) d += Math.PI * 2;
			lastAngle = cur;
			accAngle += d;
			var sign = 1.0;
			var fwd:Array<Float> = [0.0, 0.0, 0.0];
			cam.forward(fwd);
			var ax = activeAxis == 0 ? fwd[0] : (activeAxis == 1 ? fwd[1] : fwd[2]);
			if (ax > 0) sign = -1.0;
			var ang = accAngle * sign;
			if (snap > 0) ang = Math.round(ang / snap) * snap;
			out[3] = ang;
			return;
		}
		if (activeAxis == AXIS_ALL)
		{
			var hit = planeHit(px, py, pz, cam, mx, my, w, h);
			if (hit == null || startPt == null) return;
			out[0] = hit[0] - startPt[0];
			out[1] = hit[1] - startPt[1];
			out[2] = hit[2] - startPt[2];
			if (snap > 0)
			{
				out[0] = Math.round(out[0] / snap) * snap;
				out[1] = Math.round(out[1] / snap) * snap;
				out[2] = Math.round(out[2] / snap) * snap;
			}
			return;
		}
		var t = lineT(px, py, pz, activeAxis, cam, mx, my, w, h);
		var delta = t - startT;
		if (snap > 0) delta = Math.round(delta / snap) * snap;
		if (mode == R3DGizmoMode.MOVE)
		{
			if (activeAxis == 0) out[0] = delta;
			else if (activeAxis == 1) out[1] = delta;
			else out[2] = delta;
		}
		else
		{
			var len = Math.max(0.05, axisLength(scale));
			out[3] = delta / len;
		}
	}

	static function screenAngle(cam:R3DCamera, mx:Float, my:Float, w:Float, h:Float, px:Float, py:Float, pz:Float):Float
	{
		if (!cam.worldToScreen(px, py, pz, w, h, _p)) return 0.0;
		return Math.atan2(my - _p[1], mx - _p[0]);
	}
}
