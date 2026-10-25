package rainy.render3d.scene;

import rainy.render3d.host.R3DEnv;

import haxe.Json;
import rainy.render3d.host.R3DLog;
import rainy.render3d.core.R3D;
import rainy.render3d.core.R3DCamera;
import rainy.render3d.core.R3DGeom;
import rainy.render3d.core.R3DGeom.R3DMeshData;
import rainy.render3d.core.R3DLight;
import rainy.render3d.core.R3DLight.R3DLightRig;
import rainy.render3d.core.R3DLight.R3DLightType;
import rainy.render3d.core.R3DPostPresets;
import rainy.render3d.core.R3DMaterial;
import rainy.render3d.core.R3DMesh;
import rainy.render3d.core.R3DModel;
import rainy.render3d.core.R3DTexture;
import rainy.render3d.core.R3DScene;
import rainy.render3d.core.R3DSkybox;

class R3DSceneTemplate
{
	public static function load(jsonPath:String, ?scene:R3DScene):R3DScene
	{
		var raw:String = null;
		try
			raw = sys.io.File.getContent(jsonPath)
		catch (e:Dynamic)
			raw = null;
		if (raw == null || raw.length < 1)
		{
			R3DLog.error('r3dtpl', 'scene config not readable: ' + jsonPath);
			return scene;
		}
		var cfg:Dynamic = null;
		try
			cfg = Json.parse(raw)
		catch (e:Dynamic)
		{
			R3DLog.error('r3dtpl', 'scene config JSON parse failed: ' + e);
			return scene;
		}
		R3DLog.info('r3dtpl', 'loading ' + jsonPath);
		return apply(cfg, scene);
	}

	public static function apply(cfg:Dynamic, ?scene:R3DScene):R3DScene
	{
		if (cfg == null) return scene;

		var s:R3DScene = scene;
		if (s == null) s = R3D.scene();

		var clearCol:Dynamic = fld(cfg, 'clear');
		if (clearCol != null) s.bgColor = asColor(clearCol, s.bgColor);

		applyCamera(s, fld(cfg, 'camera'));
		applyAmbient(fld(cfg, 'ambient'));
		applyFog(fld(cfg, 'fog'));
		applySkybox(fld(cfg, 'skybox'));
		applyLights(fld(cfg, 'lights'));
		applyBoxes(s, fld(cfg, 'boxes'));
		applySprites(s, fld(cfg, 'sprites'));
		applyPost(s, fld(cfg, 'post'));

		return s;
	}

	static function applyCamera(s:R3DScene, cam:Dynamic):Void
	{
		if (cam == null) return;
		var c:R3DCamera = null;
		try
			c = s.views.length > 0 ? s.views[0] : null
		catch (e:Dynamic)
			c = null;
		if (c == null)
		{
			R3DLog.warn('r3dtpl', 'scene has no camera, camera config skipped');
			return;
		}
		c.x = num(cam, 'x', c.x);
		c.y = num(cam, 'y', c.y);
		c.z = num(cam, 'z', c.z);
		c.fov = num(cam, 'fov', c.fov);
		c.near = num(cam, 'near', c.near);
		c.far = num(cam, 'far', c.far);
	}

	static function applyAmbient(a:Dynamic):Void
	{
		if (a == null) return;
		var rig:R3DLightRig = R3D.rig();
		if (rig == null) return;
		rig.ambientR = num(a, 'r', rig.ambientR);
		rig.ambientG = num(a, 'g', rig.ambientG);
		rig.ambientB = num(a, 'b', rig.ambientB);
		rig.skyR = num(a, 'skyR', rig.skyR);
		rig.skyG = num(a, 'skyG', rig.skyG);
		rig.skyB = num(a, 'skyB', rig.skyB);
		rig.groundR = num(a, 'groundR', rig.groundR);
		rig.groundG = num(a, 'groundG', rig.groundG);
		rig.groundB = num(a, 'groundB', rig.groundB);
		rig.specPow = num(a, 'specPow', rig.specPow);
	}

	static function applyFog(f:Dynamic):Void
	{
		if (f == null) return;
		var rig:R3DLightRig = R3D.rig();
		if (rig == null) return;
		rig.fogStart = num(f, 'start', rig.fogStart);
		rig.fogEnd = num(f, 'end', rig.fogEnd);
		rig.fogR = num(f, 'r', rig.fogR);
		rig.fogG = num(f, 'g', rig.fogG);
		rig.fogB = num(f, 'b', rig.fogB);
	}

	static function applySkybox(sky:Dynamic):Void
	{
		if (sky == null) return;
		var folder:Dynamic = fld(sky, 'folder');
		if (folder != null && Std.isOfType(folder, String) && cast(folder, String).length > 0)
		{
			var ok:Bool = R3DSkybox.setCubemapFolder(cast folder);
			R3DSkybox.enabled = ok && boolOf(sky, 'enabled', true);
			if (!ok) R3DLog.warn('r3dtpl', 'skybox load failed: ' + folder);
		}
		else
		{
			R3DSkybox.enabled = boolOf(sky, 'enabled', false);
		}
		R3DSkybox.intensity = num(sky, 'intensity', 1.0);
		R3DLog.info('r3dtpl', 'skybox enabled=' + R3DSkybox.enabled);
	}

	static function applyLights(lights:Dynamic):Void
	{
		if (lights == null || !Std.isOfType(lights, Array)) return;
		var rig:R3DLightRig = R3D.rig();
		if (rig == null)
		{
			R3DLog.error('r3dtpl', 'R3D.rig() returned null, lights cannot attach');
			return;
		}
		var arr:Array<Dynamic> = cast lights;
		var n:Int = 0;
		for (L in arr)
		{
			if (L == null) continue;
			var l:R3DLight = new R3DLight();
			l.name = str(L, 'name', 'light' + n);
			var t:String = str(L, 'type', 'POINT').toUpperCase();
			l.type = (t == 'DIR' || t == 'DIRECTIONAL') ? R3DLightType.DIRECTIONAL : R3DLightType.POINT;
			l.x = num(L, 'x', 0);
			l.y = num(L, 'y', 0);
			l.z = num(L, 'z', 0);
			l.dirX = num(L, 'dirX', 0);
			l.dirY = num(L, 'dirY', -1);
			l.dirZ = num(L, 'dirZ', 0);
			l.r = num(L, 'r', 1);
			l.g = num(L, 'g', 1);
			l.b = num(L, 'b', 1);
			l.energy = num(L, 'energy', 1);
			l.range = num(L, 'range', 8);
			l.spot = num(L, 'spot', 0.55);
			l.enabled = boolOf(L, 'enabled', true);
			if (rig.add(l) != null) n++;
		}
		R3DLog.info('r3dtpl', 'lights added: ' + n + '/' + arr.length);
	}

	static function applyBoxes(s:R3DScene, boxes:Dynamic):Void
	{
		if (boxes == null || !Std.isOfType(boxes, Array)) return;
		var arr:Array<Dynamic> = cast boxes;
		var n:Int = 0;
		for (B in arr)
		{
			if (B == null) continue;
			var d:R3DMeshData = new R3DMeshData();
			R3DGeom.pushBox(d,
				num(B, 'x', 0), num(B, 'y', 0), num(B, 'z', 0),
				num(B, 'w', 1), num(B, 'h', 1), num(B, 'd', 1));

			var mat:Dynamic = fld(B, 'solid');
			var material:R3DMaterial = null;
			if (mat != null)
			{
				var col:Int = asColor(mat, 0xFF808080);
				material = R3D.material(null, true, true);
				if (material != null)
				{
					material.colorR = ((col >> 16) & 0xFF) / 255.0;
					material.colorG = ((col >> 8) & 0xFF) / 255.0;
					material.colorB = (col & 0xFF) / 255.0;
				}
			}

			var mesh:R3DMesh = R3D.mesh(d, material);
			if (mesh == null) continue;
			var model:R3DModel = new R3DModel();
			model.meshes = [mesh];
			try
				s.members.push(model)
			catch (e:Dynamic)
			{
				R3DLog.capture(e, 'r3dtpl', 'push box');
				continue;
			}
			n++;
		}
		R3DLog.info('r3dtpl', 'boxes: ' + n);
	}

	static function applySprites(s:R3DScene, sprites:Dynamic):Void
	{
		if (sprites == null || !Std.isOfType(sprites, Array)) return;
		var arr:Array<Dynamic> = cast sprites;
		var ok:Int = 0;
		for (P in arr)
		{
			if (P == null) continue;
			var key:String = str(P, 'texture', '');
			if (key.length < 1) continue;

			var tex:R3DTexture = loadTexture(key);
			if (tex == null) continue;

			var w:Float = num(P, 'w', 1);
			var h:Float = num(P, 'h', 1);
			var d:R3DMeshData = new R3DMeshData();
			var hw:Float = w / 2;
			var hh:Float = h / 2;
			R3DGeom.pushQuad(d, [-hw, -hh, 0, hw, -hh, 0, hw, hh, 0, -hw, hh, 0], 0, 0, 1, true);

			var mat:R3DMaterial = R3D.material(tex, true, false);
			var mesh:R3DMesh = R3D.mesh(d, mat);
			if (mesh == null) continue;

			var model:R3DModel = new R3DModel();
			model.meshes = [mesh];
			model.x = num(P, 'x', 0);
			model.y = num(P, 'y', 0);
			model.z = num(P, 'z', 0);
			var rotY:Float = num(P, 'rotY', 0);
			if (rotY != 0) model.angleY = rotY;
			try
				s.members.push(model)
			catch (e:Dynamic)
			{
				R3DLog.capture(e, 'r3dtpl', 'push sprite');
				continue;
			}
			ok++;
		}
		R3DLog.info('r3dtpl', '2D sprites placed: ' + ok + '/' + arr.length);
	}

	static function loadTexture(key:String):R3DTexture
	{
		var exts:Array<String> = ['.png', '.jpg', '.jpeg'];
		var tried:Array<String> = [];
		for (ext in exts)
		{
			var k:String = key.toLowerCase().endsWith(ext) ? key : key + ext;
			var resolved:String = null;
			try
				resolved = R3DEnv.imagePath(k)
			catch (e:Dynamic)
				resolved = null;
			if (resolved == null || resolved.length < 1) continue;
			tried.push(resolved);
			var tex:R3DTexture = null;
			try
				tex = R3DTexture.fromFile(resolved)
			catch (e:Dynamic)
				tex = null;
			if (tex != null) return tex;
		}
		tried.push(key);
		R3DLog.missingAsset('texture', key, tried, 'r3dtpl');
		return null;
	}

	static function applyPost(s:R3DScene, post:Dynamic):Void
	{
		if (post == null) return;
		var n:Int = R3DPostPresets.applyToSprite(s, post);
		R3DLog.info('r3dtpl', 'post fx: ' + (n > 0 ? 'applied' : 'shader compile failed, skipped'));
	}

	static function fld(o:Dynamic, k:String):Dynamic
	{
		if (o == null) return null;
		try
			return Reflect.field(o, k)
		catch (e:Dynamic)
			return null;
	}

	static function asColor(v:Dynamic, def:Int):Int
	{
		if (v == null) return def;
		if (Std.isOfType(v, Int)) return cast v;
		var s:String = Std.string(v);
		var p:Null<Int> = Std.parseInt(s);
		return p == null ? def : p;
	}

	static function num(o:Dynamic, k:String, def:Float):Float
	{
		var v:Dynamic = fld(o, k);
		if (v == null) return def;
		var n:Float = Std.parseFloat(Std.string(v));
		return Math.isNaN(n) ? def : n;
	}

	static function str(o:Dynamic, k:String, def:String):String
	{
		var v:Dynamic = fld(o, k);
		return (v == null) ? def : Std.string(v);
	}

	static function boolOf(o:Dynamic, k:String, def:Bool):Bool
	{
		var v:Dynamic = fld(o, k);
		if (v == null) return def;
		if (Std.isOfType(v, Bool)) return cast v;
		var t:String = Std.string(v).toLowerCase();
		return t == 'true' || t == '1' || t == 'yes';
	}
}
