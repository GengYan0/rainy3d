package rainy.render3d.core;

import rainy.render3d.host.R3DEnv;

typedef R3DLodLevel = {
	var mesh:R3DMesh;

	var minScreenRadius:Float;
}

class R3DLod
{

	public static var sceneBias:Float = 0.0;

	public static var cullRadius:Float = 0.35;

	public static function screenRadius(worldRadius:Float, dist:Float, fovDeg:Float, viewportH:Int):Float
	{
		if (worldRadius <= 0 || viewportH <= 0) return 0.0;
		var fov = fovDeg;
		if (fov < 1.0) fov = 1.0;
		if (fov > 179.0) fov = 179.0;
		var focal:Float = viewportH * 0.5 / Math.tan(fov * 0.5 * Math.PI / 180.0);
		var d:Float = dist < 0.01 ? 0.01 : dist;
		return worldRadius * focal / d;
	}

	public static function applyBias(threshold:Float, bias:Float):Float
	{
		if (threshold <= 0 || bias == 0) return threshold;
		return threshold * Math.pow(2.0, -bias);
	}

	public static function pickMesh(m:R3DModel, cam:R3DCamera, dist:Float, viewportH:Int):R3DMesh
	{
		if (m == null) return null;
		var levels = m.lodLevels;
		if (levels == null || levels.length == 0 || cam == null) return m.primary();

		var bias:Float = R3DEnv.lodBias + sceneBias;
		var r:Float = screenRadius(m.bounds.radius(0, 0, 0), dist, cam.ortho ? 60.0 : cam.fov, viewportH);
		if (r < cullRadius) return null;

		for (lv in levels)
		{
			if (lv == null || lv.mesh == null) continue;
			if (r >= applyBias(lv.minScreenRadius, bias)) return lv.mesh;
		}
		return m.primary();
	}

	public static function mipBiasFor(screenRadius:Float, nativeRadius:Float):Float
	{
		if (screenRadius <= 0 || nativeRadius <= 0) return 0.0;
		var ratio:Float = screenRadius / nativeRadius;
		if (ratio >= 1.0) return 0.0;
		return Math.log(ratio) / Math.log(2.0);
	}

	public static function clampMipBias(b:Float, levels:Int):Float
	{
		var maxLevel:Float = levels < 1 ? 0.0 : levels - 1.0;
		if (b > 0) return 0;
		return b < -maxLevel ? -maxLevel : b;
	}
}
