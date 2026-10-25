package rainy.render3d.core;

import rainy.render3d.core.R3DMaterial;
import rainy.render3d.core.R3DMesh;
import rainy.render3d.core.R3DModel;

typedef R3DBatchStat = {
	var groups:Int;
	var sources:Int;
	var tris:Int;
	var verts:Int;
}

class R3DBatch
{
	public static var last:R3DBatchStat = {groups: 0, sources: 0, tris: 0, verts: 0};
	public static var lastError:String = "";

	static inline var MAX_BATCH_VERTS:Int = 65000;

	public static function bake(models:Array<R3DModel>, keepMaterials:Array<R3DMaterial> = null):Array<R3DModel>
	{
		lastError = "";
		last = {groups: 0, sources: 0, tris: 0, verts: 0};
		var out:Array<R3DModel> = [];
		if (models == null || models.length == 0) return out;

		var groups:Array<R3DMaterial> = [];
		var buckets:Array<Array<R3DModel>> = [];
		for (m in models)
		{
			// Single-mesh models only. This routine reads `meshes[0]` and then hides the source
			// model, so anything with a second mesh would lose that geometry from the scene —
			// silently, since the batch looks fine.
			if (m == null || !m.visible || m.meshes == null || m.meshes.length != 1) continue;
			var mesh = m.meshes[0];
			var mat = mesh == null ? null : mesh.material;
			if (mat == null || mesh.positions == null || mesh.indices == null) continue;
			if (keepMaterials != null && keepMaterials.indexOf(mat) >= 0) continue;
			var gi = groups.indexOf(mat);
			if (gi < 0)
			{
				groups.push(mat);
				buckets.push([]);
				gi = groups.length - 1;
			}
			buckets[gi].push(m);
		}

		for (gi in 0...groups.length)
		{
			var list = buckets[gi];
			if (list.length < 2) continue;
			var mat = groups[gi];
			var pos:Array<Float> = [];
			var uv:Array<Float> = [];
			var nor:Array<Float> = [];
			var idx:Array<Int> = [];
			var tris = 0;
			var src:Array<R3DModel> = [];

			for (m in list)
			{
				var mesh = m.meshes[0];
				var n = Std.int(mesh.positions.length / 3);
				if (Std.int(pos.length / 3) + n > MAX_BATCH_VERTS)
				{
					flush(mat, pos, uv, nor, idx, tris, src, out);
					pos = [];
					uv = [];
					nor = [];
					idx = [];
					tris = 0;
					src = [];
					if (n > MAX_BATCH_VERTS)
					{
						lastError = "skipping oversized model " + m.name + " (" + n + " vertices)";
						continue;
					}
				}

				m.updateWorld();
				var w = m.world;
				var base = Std.int(pos.length / 3);
				var i = 0;
				while (i < n)
				{
					var x = mesh.positions[i * 3];
					var y = mesh.positions[i * 3 + 1];
					var z = mesh.positions[i * 3 + 2];
					pos.push(w[0] * x + w[4] * y + w[8] * z + w[12]);
					pos.push(w[1] * x + w[5] * y + w[9] * z + w[13]);
					pos.push(w[2] * x + w[6] * y + w[10] * z + w[14]);
					i++;
				}
				var hasUv = mesh.uvs != null && mesh.uvs.length >= n * 2;
				var hasNor = mesh.normals != null && mesh.normals.length >= n * 3;
				var vi = 0;
				while (vi < n)
				{
					if (hasUv)
					{
						uv.push(mesh.uvs[vi * 2]);
						uv.push(mesh.uvs[vi * 2 + 1]);
					}
					else
					{
						uv.push(0.0);
						uv.push(0.0);
					}
					if (hasNor)
					{
						var nx = mesh.normals[vi * 3];
						var ny = mesh.normals[vi * 3 + 1];
						var nz = mesh.normals[vi * 3 + 2];
						var tx = w[0] * nx + w[4] * ny + w[8] * nz;
						var ty = w[1] * nx + w[5] * ny + w[9] * nz;
						var tz = w[2] * nx + w[6] * ny + w[10] * nz;
						var l = Math.sqrt(tx * tx + ty * ty + tz * tz);
						if (l < 1e-6) l = 1;
						nor.push(tx / l);
						nor.push(ty / l);
						nor.push(tz / l);
					}
					else
					{
						nor.push(0.0);
						nor.push(0.0);
						nor.push(1.0);
					}
					vi++;
				}
				for (k in mesh.indices)
					idx.push(base + k);
				tris += mesh.triangles;
				src.push(m);
			}
			flush(mat, pos, uv, nor, idx, tris, src, out);
		}
		return out;
	}

	static function flush(mat:R3DMaterial, pos:Array<Float>, uv:Array<Float>, nor:Array<Float>, idx:Array<Int>, tris:Int, src:Array<R3DModel>,
			out:Array<R3DModel>):Bool
	{
		if (src.length < 2 || pos.length == 0 || idx.length == 0) return false;
		var merged = new R3DMesh();
		try
		{
			merged.setArrays(pos, uv, idx, mat, nor);
		}
		catch (e:Dynamic)
		{
			lastError = "merge failed: " + Std.string(e);
			merged.dispose();
			return false;
		}
		var batch = new R3DModel(0, 0, 0);
		batch.name = "static batch " + mat.name;
		batch.meshes = [merged];
		batch.bounds = merged.bounds;
		for (m in src)
			m.visible = false;
		out.push(batch);
		last.groups++;
		last.sources += src.length;
		last.tris += tris;
		last.verts += Std.int(pos.length / 3);
		return true;
	}

	public static function info():String
	{
		if (last.groups == 0 && lastError.length == 0) return "static batch: no shared material to merge";
		if (lastError.length > 0) return "static batch failed: " + lastError;
		return "static batch " + last.groups + " group(s) / " + last.sources + " model(s) -> " + last.groups + " draw(s), "
			+ last.tris + " triangles, " + last.verts + " vertices";
	}
}
