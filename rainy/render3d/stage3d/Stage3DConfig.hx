package rainy.render3d.stage3d;

import rainy.render3d.host.R3DLog;
import haxe.Json;
import sys.FileSystem;
import sys.io.File;

typedef Stage3DProp =
{
	var type:String;
	var x:Float;
	var y:Float;
	var z:Float;
	var sx:Float;
	var sy:Float;
	var sz:Float;
	var color:String;
	var texture:String;
}

class Stage3DConfig
{
	public var enabled:Bool = false;
	public var placement:String = 'behindGF';
	public var opacity:Float = 1.0;

	public var skyTexture:String = '';
	public var skyTint:String = '#FFFFFF';
	public var skyRoll:Float = 0.6;
	public var skyFallbackTop:String = '#1B4A8A';
	public var skyFallbackHorizon:String = '#8FC4E8';
	public var skyFallbackBottom:String = '#101418';
	public var floorChecker:Int = 12;
	public var floorColorA:String = '#F2F2F2';
	public var floorColorB:String = '#141414';
	public var floorSize:Float = 260;
	public var floorTileSize:Float = 6;
	public var mirrorFloor:Bool = true;
	public var mirrorStrength:Float = 0.5;
	public var mirrorSphere:Bool = true;
	public var mirrorSphereStrength:Float = 0.55;
	public var mirrorScale:Float = 0.5;

	public var mirrorEvery:Int = 2;
	public var billboards:String = 'bf,dad,gf';
	public var billboardScale:Float = 1.0;
	public var billboardHeight:Float = 0.0;
	public var billboardDepth:Float = 0.0;
	public var hide2DChars:Bool = true;
	public var billboardGrounded:Bool = true;
	public var billboardYaw:Bool = false;
	public var useKeyframes:Bool = true;
	public var worldScale:Float = 0.05;
	public var camHeight:Float = 9;
	public var camDistance:Float = 26;
	public var camFov:Float = 55;
	public var camLookHeight:Float = 5;
	public var yawFromAngle:Bool = true;
	public var stageCenterX:Float = 960;
	public var stageCenterY:Float = 540;
	// No `pixelSnap` here: snapping a rasterized perspective projection has no meaning; the 2D cameras keep `pixelPerfectPosition`.
	public var dynamicSize:Bool = true;
	public var renderWidth:Int = 1280;
	public var renderHeight:Int = 720;
	public var props:Array<Stage3DProp> = [];
	public var sourcePath:String = '';

	static var cached:Stage3DConfig = null;
	static var songPath:String = null;
	static var lastMtime:Float = -1;
	public static var hotReloadInterval:Float = 0.25;
	static var hotReloadAccum:Float = 0;
	static var hotReloadEnabled:Bool = true;

	public function new() {}

	public static function get():Stage3DConfig
	{
		if (cached == null) cached = load();
		return cached;
	}

	public static function reload():Stage3DConfig
	{
		cached = load();
		return cached;
	}

	public static function bindSong(?songFolder:String):Void
	{
		var p:String = (songFolder == null || songFolder.length == 0) ? null : songConfigPath(songFolder);
		if (p == songPath) return;
		songPath = p;
		lastMtime = -1;
		cached = null;
	}

	public static function boundSong():String
		return songPath;

	public static function songConfigPath(songFolder:String):String
	{
		if (songFolder == null || songFolder.length == 0) return null;
		var s:String = songFolder.split('\\').join('/');
		while (s.length > 1 && s.charAt(s.length - 1) == '/') s = s.substr(0, s.length - 1);
		return s + '/stage3d.json';
	}

	public static function ensureSongFile(songFolder:String):String
	{
		var p:String = songConfigPath(songFolder);
		if (p == null) return null;
		try
		{
			if (!FileSystem.exists(p)) writeTemplate(p);
		}
		catch (e:Dynamic) { R3DLog.silentFailure("Stage3DConfig.ensureSongFile", e); }
		return p;
	}

	public static function writeTemplate(path:String, ?base:Stage3DConfig):Void
	{
		#if sys
		try
		{
			var cfg:Stage3DConfig = (base != null) ? base : new Stage3DConfig();
			cfg.defaultProps();
			cfg.enabled = true;
			var dir:String = haxe.io.Path.directory(path);
			if (dir != null && dir.length > 0 && !FileSystem.exists(dir))
				FileSystem.createDirectory(dir);
			File.saveContent(path, toJson(cfg));
			trace('[Stage3D] wrote song config template: $path');
		}
		catch (e:Dynamic) { R3DLog.silentFailure("Stage3DConfig.writeTemplate", e); }
		#end
	}

	public static function saveTo(path:String, cfg:Stage3DConfig):Bool
	{
		#if sys
		try
		{
			File.saveContent(path, toJson(cfg));
			lastMtime = mtimeOf(path);
			return true;
		}
		catch (e:Dynamic) { R3DLog.silentFailure("Stage3DConfig.saveTo", e); }
		#end
		return false;
	}

	public static function toJson(cfg:Stage3DConfig):String
	{
		var o:Dynamic = {};
		Reflect.setField(o, 'enabled', cfg.enabled);
		Reflect.setField(o, 'placement', cfg.placement);
		Reflect.setField(o, 'opacity', cfg.opacity);
		Reflect.setField(o, 'skyTexture', cfg.skyTexture);
		Reflect.setField(o, 'skyTint', cfg.skyTint);
		Reflect.setField(o, 'skyRoll', cfg.skyRoll);
		Reflect.setField(o, 'skyFallbackTop', cfg.skyFallbackTop);
		Reflect.setField(o, 'skyFallbackHorizon', cfg.skyFallbackHorizon);
		Reflect.setField(o, 'skyFallbackBottom', cfg.skyFallbackBottom);
		Reflect.setField(o, 'floorChecker', cfg.floorChecker);
		Reflect.setField(o, 'floorColorA', cfg.floorColorA);
		Reflect.setField(o, 'floorColorB', cfg.floorColorB);
		Reflect.setField(o, 'floorSize', cfg.floorSize);
		Reflect.setField(o, 'floorTileSize', cfg.floorTileSize);
		Reflect.setField(o, 'mirrorFloor', cfg.mirrorFloor);
		Reflect.setField(o, 'mirrorStrength', cfg.mirrorStrength);
		Reflect.setField(o, 'mirrorSphere', cfg.mirrorSphere);
		Reflect.setField(o, 'mirrorSphereStrength', cfg.mirrorSphereStrength);
		Reflect.setField(o, 'mirrorScale', cfg.mirrorScale);
		Reflect.setField(o, 'mirrorEvery', cfg.mirrorEvery);
		Reflect.setField(o, 'billboards', cfg.billboards);
		Reflect.setField(o, 'billboardScale', cfg.billboardScale);
		Reflect.setField(o, 'billboardHeight', cfg.billboardHeight);
		Reflect.setField(o, 'billboardDepth', cfg.billboardDepth);
		Reflect.setField(o, 'hide2DChars', cfg.hide2DChars);
		Reflect.setField(o, 'billboardGrounded', cfg.billboardGrounded);
		Reflect.setField(o, 'billboardYaw', cfg.billboardYaw);
		Reflect.setField(o, 'useKeyframes', cfg.useKeyframes);
		Reflect.setField(o, 'worldScale', cfg.worldScale);
		Reflect.setField(o, 'camHeight', cfg.camHeight);
		Reflect.setField(o, 'camDistance', cfg.camDistance);
		Reflect.setField(o, 'camFov', cfg.camFov);
		Reflect.setField(o, 'camLookHeight', cfg.camLookHeight);
		Reflect.setField(o, 'yawFromAngle', cfg.yawFromAngle);
		Reflect.setField(o, 'stageCenterX', cfg.stageCenterX);
		Reflect.setField(o, 'stageCenterY', cfg.stageCenterY);
		Reflect.setField(o, 'dynamicSize', cfg.dynamicSize);
		Reflect.setField(o, 'renderWidth', cfg.renderWidth);
		Reflect.setField(o, 'renderHeight', cfg.renderHeight);
		var arr:Array<Dynamic> = [];
		for (p in cfg.props)
			arr.push({type: p.type, x: p.x, y: p.y, z: p.z, sx: p.sx, sy: p.sy, sz: p.sz, color: p.color, texture: p.texture});
		Reflect.setField(o, 'props', arr);
		return haxe.Json.stringify(o, '\t');
	}

	static function mtimeOf(path:String):Float
	{
		#if sys
		try
		{
			if (path == null || !FileSystem.exists(path)) return -1;
			return FileSystem.stat(path).mtime.getTime();
		}
		catch (e:Dynamic) { return -1; }
		#else
		return -1;
		#end
	}

	public static function pollHotReload(elapsed:Float):Bool
	{
		if (!hotReloadEnabled || cached == null) return false;
		var p:String = cached.sourcePath;
		if (p == null || p.length == 0) return false;
		hotReloadAccum += elapsed;
		if (hotReloadAccum < hotReloadInterval) return false;
		hotReloadAccum = 0;
		var m:Float = mtimeOf(p);
		if (m < 0) return false;
		if (lastMtime < 0) { lastMtime = m; return false; }
		if (Math.abs(m - lastMtime) < 0.001) return false;
		lastMtime = m;
		reload();
		trace('[Stage3D] hot reload: $p');
		return true;
	}

	public static function setHotReload(on:Bool):Void
	{
		hotReloadEnabled = on;
		hotReloadAccum = 0;
	}

	static function candidatePaths():Array<String>
	{
		var out:Array<String> = [];
		if (songPath != null && songPath.length > 0) out.push(songPath);
		out.push('stage3d.json');
		return out;
	}

	static function load():Stage3DConfig
	{
		var cfg = new Stage3DConfig();
		cfg.defaultProps();
		var raw:String = null;
		for (p in candidatePaths())
		{
			try
			{
				if (FileSystem.exists(p))
				{
					raw = File.getContent(p);
					cfg.sourcePath = p;
					break;
				}
			}
			catch (e:Dynamic) { R3DLog.silentFailure("Stage3DConfig.load", e); }
		}
		if (raw != null)
		{
			try
			{
				apply(cfg, Json.parse(raw));
			}
			catch (e:Dynamic) { R3DLog.silentFailure("Stage3DConfig.load", e); }
		}
		else
		{
			cfg.sourcePath = (songPath != null) ? songPath : 'stage3d.json';
		}
		lastMtime = mtimeOf(cfg.sourcePath);
		return cfg;
	}

	static function apply(cfg:Stage3DConfig, d:Dynamic):Void
	{
		if (d == null) return;
		cfg.enabled = num(d, 'enabled', cfg.enabled ? 1 : 0) != 0;
		cfg.placement = str(d, 'placement', cfg.placement);
		cfg.opacity = num(d, 'opacity', cfg.opacity);
		cfg.skyTexture = optStr(d, 'skyTexture', cfg.skyTexture);
		cfg.skyTint = str(d, 'skyTint', cfg.skyTint);
		cfg.skyRoll = num(d, 'skyRoll', cfg.skyRoll);
		cfg.skyFallbackTop = str(d, 'skyFallbackTop', cfg.skyFallbackTop);
		cfg.skyFallbackHorizon = str(d, 'skyFallbackHorizon', cfg.skyFallbackHorizon);
		cfg.skyFallbackBottom = str(d, 'skyFallbackBottom', cfg.skyFallbackBottom);
		cfg.floorChecker = Std.int(num(d, 'floorChecker', cfg.floorChecker));
		cfg.floorColorA = str(d, 'floorColorA', cfg.floorColorA);
		cfg.floorColorB = str(d, 'floorColorB', cfg.floorColorB);
		cfg.floorSize = num(d, 'floorSize', cfg.floorSize);
		cfg.floorTileSize = num(d, 'floorTileSize', cfg.floorTileSize);
		cfg.mirrorFloor = num(d, 'mirrorFloor', cfg.mirrorFloor ? 1 : 0) != 0;
		cfg.mirrorStrength = num(d, 'mirrorStrength', cfg.mirrorStrength);
		cfg.mirrorSphere = num(d, 'mirrorSphere', cfg.mirrorSphere ? 1 : 0) != 0;
		cfg.mirrorSphereStrength = num(d, 'mirrorSphereStrength', cfg.mirrorSphereStrength);
		cfg.mirrorScale = num(d, 'mirrorScale', cfg.mirrorScale);
		cfg.mirrorEvery = Std.int(Math.max(1, num(d, 'mirrorEvery', cfg.mirrorEvery)));
		cfg.billboards = str(d, 'billboards', cfg.billboards);
		cfg.billboardScale = num(d, 'billboardScale', cfg.billboardScale);
		cfg.billboardHeight = num(d, 'billboardHeight', cfg.billboardHeight);
		cfg.billboardDepth = num(d, 'billboardDepth', cfg.billboardDepth);
		cfg.hide2DChars = num(d, 'hide2DChars', cfg.hide2DChars ? 1 : 0) != 0;
		cfg.billboardGrounded = num(d, 'billboardGrounded', cfg.billboardGrounded ? 1 : 0) != 0;
		cfg.billboardYaw = num(d, 'billboardYaw', cfg.billboardYaw ? 1 : 0) != 0;
		cfg.useKeyframes = num(d, 'useKeyframes', cfg.useKeyframes ? 1 : 0) != 0;
		cfg.worldScale = num(d, 'worldScale', cfg.worldScale);
		cfg.camHeight = num(d, 'camHeight', cfg.camHeight);
		cfg.camDistance = num(d, 'camDistance', cfg.camDistance);
		cfg.camFov = num(d, 'camFov', cfg.camFov);
		cfg.camLookHeight = num(d, 'camLookHeight', cfg.camLookHeight);
		cfg.yawFromAngle = num(d, 'yawFromAngle', cfg.yawFromAngle ? 1 : 0) != 0;
		cfg.stageCenterX = num(d, 'stageCenterX', cfg.stageCenterX);
		cfg.stageCenterY = num(d, 'stageCenterY', cfg.stageCenterY);
		cfg.dynamicSize = num(d, 'dynamicSize', cfg.dynamicSize ? 1 : 0) != 0;
		cfg.renderWidth = Std.int(num(d, 'renderWidth', cfg.renderWidth));
		cfg.renderHeight = Std.int(num(d, 'renderHeight', cfg.renderHeight));

		var list:Dynamic = Reflect.field(d, 'props');
		if (list != null && Std.isOfType(list, Array))
		{
			var arr:Array<Dynamic> = cast list;
			if (arr.length > 0)
			{
				cfg.props = [];
				for (o in arr)
				{
					if (o == null) continue;
					cfg.props.push({
						type: str(o, 'type', 'box'),
						x: num(o, 'x', 0),
						y: num(o, 'y', 0),
						z: num(o, 'z', 0),
						sx: num(o, 'sx', 2),
						sy: num(o, 'sy', 2),
						sz: num(o, 'sz', 2),
						color: str(o, 'color', '#888888'),
						texture: str(o, 'texture', '')
					});
				}
			}
		}
	}

	static function str(d:Dynamic, f:String, def:String):String
	{
		var v:Dynamic = Reflect.field(d, f);
		if (v == null) return def;
		var s:String = Std.string(v);
		return s.length == 0 ? def : s;
	}

	static function optStr(d:Dynamic, f:String, def:String):String
	{
		var v:Dynamic = Reflect.field(d, f);
		if (v == null) return def;
		return Std.string(v);
	}

	static function num(d:Dynamic, f:String, def:Float):Float
	{
		var v:Dynamic = Reflect.field(d, f);
		if (v == null) return def;
		if (Std.isOfType(v, Bool)) return cast(v, Bool) ? 1 : 0;
		var f2:Float = Std.parseFloat(Std.string(v));
		return Math.isNaN(f2) ? def : f2;
	}

	public static function colorOf(hex:String, def:Int):Int
	{
		if (hex == null) return def;
		var s:String = StringTools.trim(hex);
		if (s.length == 0) return def;
		if (s.charAt(0) == '#') s = s.substr(1);
		if (s.length == 3)
			s = '' + s.charAt(0) + s.charAt(0) + s.charAt(1) + s.charAt(1) + s.charAt(2) + s.charAt(2);
		var v:Null<Int> = Std.parseInt('0x' + s);
		if (v == null) return def;
		return 0xFF000000 | (v & 0xFFFFFF);
	}

	function defaultProps():Void
	{
		props = [
			{type: 'box', x: -13, y: 3, z: -9, sx: 5, sy: 6, sz: 5, color: '#7B4BE0', texture: ''},
			{type: 'box', x: -7, y: 2, z: -4, sx: 4, sy: 4, sz: 4, color: '#E08A2B', texture: ''},
			{type: 'cyl', x: 1, y: 3.5, z: -14, sx: 3, sy: 7, sz: 3, color: '#2BB6A8', texture: ''},
			{type: 'box', x: 8, y: 2.5, z: -11, sx: 5, sy: 5, sz: 5, color: '#8E5CE0', texture: ''},
			{type: 'cone', x: 14, y: 3, z: -8, sx: 5, sy: 6, sz: 5, color: '#3FBF63', texture: ''},
			{type: 'sphere', x: 4, y: 2.6, z: -6, sx: 5.2, sy: 5.2, sz: 5.2, color: '#BFD4E6', texture: ''}
		];
	}
}
