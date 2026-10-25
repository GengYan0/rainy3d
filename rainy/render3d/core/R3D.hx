package rainy.render3d.core;

import openfl.geom.Vector3D;
import rainy.render3d.core.R3DCamera;
import rainy.render3d.core.R3DCaps;
import rainy.render3d.core.R3DGeom.R3DMeshData;
import rainy.render3d.core.R3DAnim.R3DClip;
import rainy.render3d.core.R3DAnim.R3DCurve;
import rainy.render3d.core.R3DGLStateCache;
import rainy.render3d.core.R3DInst.R3DInstSet;
import rainy.render3d.core.R3DPool;
import rainy.render3d.core.R3DLight.R3DLightRig;
import rainy.render3d.core.R3DLight.R3DLightType;
import rainy.render3d.core.R3DMaterialGraph;
import rainy.render3d.core.R3DNodeEditor;
import rainy.render3d.core.R3DMaterial;
import rainy.render3d.core.R3DMesh;
import rainy.render3d.core.R3DModel;
import rainy.render3d.core.R3DTexture;
import rainy.render3d.core.R3DScene;
import rainy.render3d.core.R3DShader;
import rainy.render3d.core.R3DShaders;
import rainy.render3d.core.R3DShell;

enum abstract R3DBlend(Int) from Int to Int
{
	var ADD = 0;
	var MIX = 1;
	var SCREEN = 2;
	var MULTIPLY = 3;
	var NONE = 4;
}

enum abstract R3DFace(Int) from Int to Int
{
	var FRONT = 0;
	var BACK = 1;
	var BOTH = 2;
}

enum abstract R3DWrap(Int) from Int to Int
{
	var CLAMP = 0;
	var REPEAT = 1;
	var MIRROR = 2;
}

enum abstract R3DFilter(Int) from Int to Int
{
	var NEAREST = 0;
	var LINEAR = 1;
}

enum abstract R3DMipFilter(Int) from Int to Int
{
	var MIPNONE = 0;
	var MIPNEAREST = 1;
	var MIPLINEAR = 2;
}

class R3DBounds
{
	public var minX:Float = 0;
	public var minY:Float = 0;
	public var minZ:Float = 0;
	public var maxX:Float = 0;
	public var maxY:Float = 0;
	public var maxZ:Float = 0;

	public function new() {}

	public function set(minX:Float, minY:Float, minZ:Float, maxX:Float, maxY:Float, maxZ:Float):R3DBounds
	{
		this.minX = minX;
		this.minY = minY;
		this.minZ = minZ;
		this.maxX = maxX;
		this.maxY = maxY;
		this.maxZ = maxZ;
		return this;
	}

	public function empty():R3DBounds
	{
		return set(1e30, 1e30, 1e30, -1e30, -1e30, -1e30);
	}

	public function clear():Void
	{
		empty();
	}

	public inline function valid():Bool
	{
		return maxX >= minX;
	}

	public function addPoint(x:Float, y:Float, z:Float):Void
	{
		if (x < minX) minX = x;
		if (y < minY) minY = y;
		if (z < minZ) minZ = z;
		if (x > maxX) maxX = x;
		if (y > maxY) maxY = y;
		if (z > maxZ) maxZ = z;
	}

	public function center(?out:Vector3D):Vector3D
	{
		if (out == null) out = new Vector3D();
		out.x = (minX + maxX) * 0.5;
		out.y = (minY + maxY) * 0.5;
		out.z = (minZ + maxZ) * 0.5;
		return out;
	}

	public function radius(px:Float, py:Float, pz:Float):Float
	{
		var dx = Math.max(Math.abs(px - minX), Math.abs(px - maxX));
		var dy = Math.max(Math.abs(py - minY), Math.abs(py - maxY));
		var dz = Math.max(Math.abs(pz - minZ), Math.abs(pz - maxZ));
		return Math.sqrt(dx * dx + dy * dy + dz * dz);
	}

	public function copyFrom(b:R3DBounds):Void
	{
		set(b.minX, b.minY, b.minZ, b.maxX, b.maxY, b.maxZ);
	}
}

enum abstract R3DAxis(Int) from Int to Int
{
	var AXIS_X = 0;
	var AXIS_Y = 1;
	var AXIS_Z = 2;
}

enum abstract R3DFaceId(Int) from Int to Int
{
	var FACE_PX = 0;
	var FACE_NX = 1;
	var FACE_PY = 2;
	var FACE_NY = 3;
	var FACE_PZ = 4;
	var FACE_NZ = 5;
}

class R3DUtil
{
	public static inline function axisIndex(f:R3DFaceId):Int
	{
		return (cast f : Int) >> 1;
	}

	public static inline function axisSign(f:R3DFaceId):Float
	{
		return ((cast f : Int) & 1) == 0 ? 1.0 : -1.0;
	}

	public static function axisVector(f:R3DFaceId, ?out:Vector3D):Vector3D
	{
		if (out == null) out = new Vector3D();
		var a = axisIndex(f);
		var s = axisSign(f);
		out.setTo(a == 0 ? s : 0.0, a == 1 ? s : 0.0, a == 2 ? s : 0.0);
		return out;
	}
}

class R3D
{
	public static inline var VERSION:String = "1.0";

	public static var autoInit:Bool = true;
	public static var defaultRig:R3DLightRig = null;

	public static function init():Void
	{
		var ctx = openfl.Lib.current.stage.context3D;
		if (ctx == null) return;
		R3DShader.context = ctx;
		R3DScene.context = ctx;
		R3DGLStateCache.init(ctx);
		R3DCaps.init(ctx);
	}

	public static function rig():R3DLightRig
	{
		if (defaultRig != null) return defaultRig;
		defaultRig = new R3DLightRig();
		var key = defaultRig.make(R3DLightType.DIRECTIONAL, "key");
		key.setDir(-0.35, -0.9, 0.3).setColor(0.85, 0.82, 0.76);
		key.energy = 1.0;
		var fill = defaultRig.make(R3DLightType.DIRECTIONAL, "fill");
		fill.setDir(0.6, -0.25, -0.6).setColor(0.18, 0.2, 0.26);
		fill.energy = 1.0;
		defaultRig.ambientR = 0.05;
		defaultRig.ambientG = 0.05;
		defaultRig.ambientB = 0.06;
		defaultRig.specPow = 48;
		return defaultRig;
	}

	public static function scene(width:Int = 1280, height:Int = 720):R3DScene
	{
		if (autoInit) init();
		var s = new R3DScene(width, height);
		s.bgColor = 0xFF0E1116;
		var r = rig();
		s.onBindShader = function(sh:R3DShader) r.upload(sh);
		return s;
	}

	public static function camera(x:Float = 0, y:Float = 1.6, z:Float = 4, ?into:R3DScene):R3DCamera
	{
		var c = new R3DCamera(x, y, z);
		c.fov = 55;
		c.near = 0.1;
		c.far = 120;
		c.label = "主相机";
		if (into != null) into.addCamera(c);
		return c;
	}

	public static function litShader():R3DShader
	{
		return R3DShaders.litShader();
	}

	public static function unlitShader(solid:Bool = false):R3DShader
	{
		return R3DShaders.unlitShader(solid ? ["SOLID"] : null);
	}

	public static function material(?tex:R3DTexture, lit:Bool = true, solid:Bool = false):R3DMaterial
	{
		var m = new R3DMaterial(lit ? litShader() : unlitShader(solid));
		m.name = lit ? "lit" : (solid ? "solid" : "unlit");
		if (tex != null) m.textures.set("uAlbedoMap", tex);
		return m;
	}

	public static function mesh(data:R3DMeshData, ?mat:R3DMaterial):R3DMesh
	{
		var m = new R3DMesh();
		m.setArrays(data.positions, data.uvs, data.indices, mat, data.normals);
		m.calculateBounds(data.positions);
		return m;
	}

	public static function box(w:Float = 1, h:Float = 1, d:Float = 1, ?mat:R3DMaterial):R3DMesh
	{
		var data = new R3DMeshData("box");
		data.box(0, 0, 0, w, h, d);
		return mesh(data, mat);
	}

	public static function model(mesh:R3DMesh, ?name:String):R3DModel
	{
		var m = new R3DModel(0, 0, 0);
		m.name = name == null ? "" : name;
		m.addMesh(mesh);
		return m;
	}

	public static function graph():R3DMaterialGraph
	{
		return R3DMaterialGraph.defaultGraph();
	}

	public static function shell():R3DShell
	{
		return new R3DShell();
	}

	public static function nodeEditor():R3DNodeEditor
	{
		return new R3DNodeEditor();
	}

	public static function instSet():R3DInstSet
	{
		return new R3DInstSet();
	}

	public static function clip(?name:String):R3DClip
	{
		return new R3DClip(name);
	}

	public static function curve():R3DCurve
	{
		return new R3DCurve();
	}

	public static function tunePool(budgetMB:Int, idleSec:Float):Void
	{
		R3DPool.budgetBytes = budgetMB * 1024 * 1024;
		R3DPool.idleSeconds = idleSec;
	}

	public static function runtimeInfo():String
	{
		return R3DPool.stats();
	}

	public static function applyGraph(mat:R3DMaterial):Bool
	{
		if (mat == null || mat.graph == null) return false;
		return mat.useGraph(mat.graph, R3DShaders.LIT_VERT);
	}

	public static function info():String
	{
		return "r3d " + VERSION + "  ·  " + R3DCaps.describe();
	}
}
