package rainy.render3d.core;

class R3DMat4
{
	public static function identity(?out:Array<Float>):Array<Float>
	{
		if (out == null) out = [];
		out.resize(16);
		for (i in 0...16) out[i] = 0;
		out[0] = out[5] = out[10] = out[15] = 1;
		return out;
	}

	public static function multiplication(a:Array<Float>, b:Array<Float>, ?out:Array<Float>):Array<Float>
	{
		// Aliasing a source with the destination would read terms that were already
		// overwritten, so that case allocates instead of trying to be clever.
		var o:Array<Float> = (out == null || out == a || out == b) ? [] : out;
		o.resize(16);
		for (r in 0...4)
			for (c in 0...4)
			{
				var s = 0.0;
				for (k in 0...4) s += a[r * 4 + k] * b[k * 4 + c];
				o[r * 4 + c] = s;
			}
		return o;
	}

	public static function translation(tx:Float, ty:Float, tz:Float):Array<Float>
	{
		var m = identity();
		m[3] = tx;
		m[7] = ty;
		m[11] = tz;
		return m;
	}

	public static function scaling(sx:Float, sy:Float, sz:Float):Array<Float>
	{
		var m = identity();
		m[0] = sx;
		m[5] = sy;
		m[10] = sz;
		return m;
	}

	public static function rotationX(r:Float):Array<Float>
	{
		var m = identity();
		var c = Math.cos(r), s = Math.sin(r);
		m[5] = c; m[6] = -s;
		m[9] = s; m[10] = c;
		return m;
	}

	public static function rotationY(r:Float):Array<Float>
	{
		var m = identity();
		var c = Math.cos(r), s = Math.sin(r);
		m[0] = c; m[2] = s;
		m[8] = -s; m[10] = c;
		return m;
	}

	public static function rotationZ(r:Float):Array<Float>
	{
		var m = identity();
		var c = Math.cos(r), s = Math.sin(r);
		m[0] = c; m[1] = -s;
		m[4] = s; m[5] = c;
		return m;
	}

	public static function euler(rx:Float, ry:Float, rz:Float, ?out:Array<Float>):Array<Float>
	{
		var m = multiplication(rotationY(ry), rotationX(rx));
		return multiplication(m, rotationZ(rz));
	}

	public static function compose(px:Float, py:Float, pz:Float, rx:Float, ry:Float, rz:Float,
		sx:Float, sy:Float, sz:Float, ?out:Array<Float>):Array<Float>
	{
		var c1 = Math.cos(ry), s1 = Math.sin(ry);
		var c2 = Math.cos(rx), s2 = Math.sin(rx);
		var c3 = Math.cos(rz), s3 = Math.sin(rz);

		// Row 0 of Ry * Rx * Rz.
		var r00 = c1 * c3 + s1 * s2 * s3;
		var r01 = -c1 * s3 + s1 * s2 * c3;
		var r02 = s1 * c2;
		// Row 1 collapses because Ry leaves the middle row untouched.
		var r10 = c2 * s3;
		var r11 = c2 * c3;
		var r12 = -s2;
		// Row 2.
		var r20 = -s1 * c3 + c1 * s2 * s3;
		var r21 = s1 * s3 + c1 * s2 * c3;
		var r22 = c1 * c2;

		var o:Array<Float> = out == null ? [] : out;
		o.resize(16);
		o[0] = r00 * sx; o[1] = r01 * sx; o[2] = r02 * sx; o[3] = px;
		o[4] = r10 * sy; o[5] = r11 * sy; o[6] = r12 * sy; o[7] = py;
		o[8] = r20 * sz; o[9] = r21 * sz; o[10] = r22 * sz; o[11] = pz;
		o[12] = 0; o[13] = 0; o[14] = 0; o[15] = 1;
		return o;
	}

	public static function perspectiveHalf(fovRad:Float, aspect:Float, zNear:Float, zFar:Float,
		?reversed:Bool, ?out:Array<Float>):Array<Float>
	{
		if (reversed == null) reversed = R3DDepth.reversed;
		var f = 1.0 / Math.tan(fovRad * 0.5);
		var m:Array<Float> = out == null ? [] : out;
		m.resize(16);
		for (i in 0...16) m[i] = 0;
		var den:Float = zNear - zFar;
		if (den == 0) den = -1e-6;
		m[0] = f / aspect;
		m[5] = f;
		if (reversed)
		{
			m[10] = (zFar + zNear) / -den;
			m[11] = (2 * zFar * zNear) / -den;
		}
		else
		{
			m[10] = (zFar + zNear) / den;
			m[11] = (2 * zFar * zNear) / den;
		}
		m[14] = -1;
		return m;
	}

	public static function ortho(left:Float, right:Float, bottom:Float, top:Float, zNear:Float, zFar:Float,
		?reversed:Bool, ?out:Array<Float>):Array<Float>
	{
		if (reversed == null) reversed = R3DDepth.reversed;
		var m:Array<Float> = out == null ? [] : out;
		m.resize(16);
		for (i in 0...16) m[i] = 0;
		var rl = right - left;
		var tb = top - bottom;
		var fn = zFar - zNear;
		if (rl == 0) rl = 1e-6;
		if (tb == 0) tb = 1e-6;
		if (fn == 0) fn = 1e-6;
		m[0] = 2.0 / rl;
		m[3] = -(right + left) / rl;
		m[5] = 2.0 / tb;
		m[7] = -(top + bottom) / tb;
		// Same sign flip as the perspective case, for the same reason.
		m[10] = reversed ? 2.0 / fn : -2.0 / fn;
		m[11] = reversed ? (zFar + zNear) / fn : -(zFar + zNear) / fn;
		m[15] = 1.0;
		return m;
	}

	public static function lookAt(px:Float, py:Float, pz:Float, tx:Float, ty:Float, tz:Float,
		ux:Float, uy:Float, uz:Float, ?out:Array<Float>):Array<Float>
	{
		var fx = tx - px, fy = ty - py, fz = tz - pz;
		var fl = Math.sqrt(fx * fx + fy * fy + fz * fz);
		if (fl < 1e-9) fl = 1;
		fx /= fl; fy /= fl; fz /= fl;
		var sx = fy * uz - fz * uy;
		var sy = fz * ux - fx * uz;
		var sz = fx * uy - fy * ux;
		var sl = Math.sqrt(sx * sx + sy * sy + sz * sz);
		if (sl < 1e-9)
		{
			sx = 1; sy = 0; sz = 0; sl = 1;
		}
		sx /= sl; sy /= sl; sz /= sl;
		var rx = sy * fz - sz * fy;
		var ry = sz * fx - sx * fz;
		var rz = sx * fy - sy * fx;
		var m:Array<Float> = out == null ? [] : out;
		m.resize(16);
		m[0] = sx; m[1] = sy; m[2] = sz; m[3] = -(sx * px + sy * py + sz * pz);
		m[4] = rx; m[5] = ry; m[6] = rz; m[7] = -(rx * px + ry * py + rz * pz);
		m[8] = -fx; m[9] = -fy; m[10] = -fz; m[11] = (fx * px + fy * py + fz * pz);
		m[12] = 0; m[13] = 0; m[14] = 0; m[15] = 1;
		return m;
	}

	public static function transformPoint(m:Array<Float>, x:Float, y:Float, z:Float, out:Array<Float>):Void
	{
		var w = m[12] * x + m[13] * y + m[14] * z + m[15];
		if (w == 0) w = 1e-9;
		out[0] = (m[0] * x + m[1] * y + m[2] * z + m[3]) / w;
		out[1] = (m[4] * x + m[5] * y + m[6] * z + m[7]) / w;
		out[2] = (m[8] * x + m[9] * y + m[10] * z + m[11]) / w;
		out[3] = w;
	}

	public static function inverse(m:Array<Float>, ?out:Array<Float>):Array<Float>
	{
		var inv:Array<Float> = (out == null || out == m) ? [] : out;
		inv.resize(16);
		inv[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] + m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10];
		inv[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] - m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10];
		inv[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] + m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9];
		inv[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] - m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9];
		inv[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] - m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10];
		inv[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] + m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10];
		inv[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] - m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9];
		inv[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] + m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9];
		inv[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] + m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6];
		inv[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] - m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6];
		inv[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] + m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5];
		inv[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] - m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5];
		inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] - m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6];
		inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] + m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6];
		inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] - m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5];
		inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] + m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5];
		var det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12];
		if (det == 0)
			return identity(inv);
		det = 1.0 / det;
		for (i in 0...16) inv[i] *= det;
		return inv;
	}
}
