package rainy.render3d.core;

import flixel.FlxG;
import rainy.render3d.core.R3DScene;
import rainy.render3d.core.R3DCamera;
import rainy.render3d.core.R3DShaders;
import rainy.render3d.core.R3DShader;
import rainy.render3d.core.R3DModel;
import rainy.render3d.core.R3DMesh;
import rainy.render3d.core.R3DMaterial;
import rainy.render3d.core.R3DGeom;
import rainy.render3d.core.R3DGeom.R3DMeshData;
import rainy.render3d.core.R3D.R3DBlend;

class R3DStage
{
	public var scene:R3DScene;
	public var cam:R3DCamera;
	public var bgColor:Int = 0xff0c0c14;
	public var built:Bool = false;

	public function new(width:Int, height:Int)
	{
		scene = new R3DScene(width, height);
		scene.direct = true;
		scene.culling = true;
		scene.wireframe = false;
		scene.bgColor = bgColor;

		cam = new R3DCamera(0.0, 2.4, 7.0);
		cam.fov = 55.0;
		cam.near = 0.1;
		cam.far = 300.0;
		cam.aspect = (height > 0) ? (width / height) : 1.7778;
		cam.update();
		scene.views.push(cam);

		try
		{
			var sh = R3DShader.fromSources(R3DShaders.UNLIT_VERT, R3DShaders.UNLIT_FRAG, ["SOLID"]);
			buildScene(sh);
			built = true;
		}
		catch (e:Dynamic)
		{
			trace("R3DStage build failed: " + e);
			FlxG.log.error("R3DStage 构建失败: " + e);
		}
	}

	function mat(sh:R3DShader, color:Int):R3DMaterial
	{
		var m = new R3DMaterial(sh);
		m.setColor(color);
		m.blendMode = R3DBlend.MIX;
		return m;
	}

	function addModel(d:R3DMeshData, m:R3DMaterial):Void
	{
		if (d == null || d.indices.length == 0) return;
		var mesh = new R3DMesh();
		mesh.setArrays(d.positions, d.uvs, d.indices, m, d.normals);
		var model = new R3DModel(0, 0, 0);
		model.addMesh(mesh);
		scene.add(model);
	}

	function buildScene(sh:R3DShader):Void
	{
		var ground = new R3DMeshData("ground");
		R3DGeom.pushPlane(ground, 0, 0.0, 0, 60, 60, true);
		addModel(ground, mat(sh, 0xff222633));

		var back = new R3DMeshData("backWall");
		R3DGeom.pushBox(back, -30, 0, -12, 60, 16, 0.6);
		addModel(back, mat(sh, 0xff2e2e3c));

		var left = new R3DMeshData("leftWall");
		R3DGeom.pushBox(left, -30, 0, -12, 0.6, 16, 24);
		addModel(left, mat(sh, 0xff26262f));
		var right = new R3DMeshData("rightWall");
		R3DGeom.pushBox(right, 29.4, 0, -12, 0.6, 16, 24);
		addModel(right, mat(sh, 0xff26262f));

		var p1 = new R3DMeshData("plat1");
		R3DGeom.pushBox(p1, -6, 0, -3, 4, 1.2, 4);
		addModel(p1, mat(sh, 0xff3a6ea5));
		var p2 = new R3DMeshData("plat2");
		R3DGeom.pushBox(p2, 4, 0, -4, 5, 1.6, 5);
		addModel(p2, mat(sh, 0xff4a7fb0));
		var p3 = new R3DMeshData("box3");
		R3DGeom.pushBox(p3, -1, 1.6, -5, 2.4, 2.4, 2.4);
		addModel(p3, mat(sh, 0xffc0643a));
		var p4 = new R3DMeshData("pillar");
		R3DGeom.pushBox(p4, 9, 0, -6, 1.2, 10, 1.2);
		addModel(p4, mat(sh, 0xff5a5a6a));
	}

	public function update(elapsed:Float):Void
	{
		if (scene == null) return;
		scene.time += elapsed;
	}

	public function destroy():Void
	{
		if (scene != null)
		{
			scene.dispose();
			scene = null;
		}
	}
}
