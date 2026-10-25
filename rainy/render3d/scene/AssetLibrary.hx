package rainy.render3d.scene;

import rainy.render3d.host.R3DLog;
import haxe.ds.StringMap;
import openfl.display.BitmapData;
import rainy.render3d.core.R3DPreload;
import rainy.render3d.core.R3DTexture;
import rainy.render3d.core.R3D.R3DWrap;
import rainy.render3d.core.R3D.R3DFilter;
import rainy.render3d.core.R3D.R3DMipFilter;
import rainy.render3d.host.R3DLog;
import sys.FileSystem;

typedef AssetEntry = {
	var path:String;
	var name:String;
	var dir:Bool;
	var depth:Int;
	var kind:String;
	var size:Int;
}

class AssetLibrary
{
	public static var roots:Array<String> = [
		"assets/3d",
		"assets/shop/textures",
		"assets/shop/materials",
		"assets/shop/stage"
	];

	public static inline var DIR3D:String = "assets/3d";

	public static function pack3dDir(pack:String):String
	{
		return "packs/" + (pack.length == 0 ? "shop" : pack) + "/" + DIR3D;
	}

	public static var files:Array<String> = [];
	public static var models:Array<String> = [];
	public static var shaders:Array<String> = [];
	public static var packs:Array<String> = [];
	public static var entries:Array<AssetEntry> = [];
	public static var curPack:String = "";
	public static var filter:String = "all";
	public static var lastError:String = "";

	static var cache:StringMap<R3DTexture> = new StringMap();
	static var thumbCache:StringMap<BitmapData> = new StringMap();

	static var thumbMiss:StringMap<Bool> = new StringMap();
	static var expanded:StringMap<Bool> = new StringMap();

	static var tree:Array<AssetEntry> = [];
	/** Directories still to visit, deepest last. */
	static var walkStack:Array<{d:String, depth:Int}> = [];
	static var treeReady:Bool = false;
	static var scanDerivedEpoch:Int = -1;
	static var scanDerived:Bool = false;

	public static var treeEpoch:Int = 0;

	static var scanQueued:Bool = false;
	static var walkSeeded:Bool = false;
	static inline var MAX_DEPTH:Int = 8;

	static function scanStep():Void
	{
		scanQueued = false;
		if (walkStep(2.5)) return;
		scanAsync();
	}

	public static function kindOf(name:String):String
	{
		var low = name.toLowerCase();
		if (StringTools.endsWith(low, ".obj") || StringTools.endsWith(low, ".fbx") || StringTools.endsWith(low, ".glb")
			|| StringTools.endsWith(low, ".gltf")) return "model";
		if (StringTools.endsWith(low, ".glsl") || StringTools.endsWith(low, ".vert") || StringTools.endsWith(low, ".frag")) return "shader";
		if (StringTools.endsWith(low, ".png") || StringTools.endsWith(low, ".jpg") || StringTools.endsWith(low, ".jpeg")
			|| StringTools.endsWith(low, ".bmp")) return "texture";
		return "other";
	}

	public static function scan(?force:Bool = false):Array<String>
	{
		if (scanDerived && !force && scanDerivedEpoch == treeEpoch) return files;
		files = [];
		models = [];
		shaders = [];
		for (e in tree)
		{
			if (e.dir) continue;
			if (e.kind == "texture") files.push(e.path);
			else if (e.kind == "model") models.push(e.path);
			else if (e.kind == "shader") shaders.push(e.path);
		}
		scanDerived = true;
		scanDerivedEpoch = treeEpoch;
		if (!treeReady) scanAsync();
		return files;
	}

	public static function scanAsync():Void
	{
		if (treeReady || scanQueued) return;
		scanQueued = true;
		R3DPreload.push("素材扫描", scanStep);
	}

	public static function walkStep(budgetMs:Float = 2.5):Bool
	{
		if (treeReady) return true;
		seedWalk();
		var t0 = haxe.Timer.stamp();
		while (walkStack.length > 0)
		{
			var cur = walkStack.pop();
			readDir(cur.d, cur.depth);
			if ((haxe.Timer.stamp() - t0) * 1000.0 >= budgetMs) break;
		}
		if (walkStack.length == 0) finishWalk();
		return treeReady;
	}

	public static function resetTree():Void
	{
		tree = [];
		walkStack = [];
		walkSeeded = false;
		treeReady = false;
		scanDerived = false;
		treeEpoch++;
	}

	static function finishWalk():Void
	{
		treeReady = true;
		treeEpoch++;
		scan(true);
		R3DLog.info("资产库扫描: 条目 " + tree.length + " (贴图 " + files.length + " / 模型 " + models.length
			+ " / 着色器 " + shaders.length + ")", "Shop3D");
	}

	static function seedWalk():Void
	{
		if (walkSeeded) return;
		walkSeeded = true;
		scanPacks();
		var starts:Array<String> = [];
		for (p in packs) starts.push(packAssetsDir(p));
		for (r in roots) starts.push(r);
		var i = starts.length - 1;
		while (i >= 0)
		{
			walkStack.push({d: starts[i], depth: 0});
			i--;
		}
	}

	static function readDir(dir:String, depth:Int):Void
	{
		var list:Array<String> = null;
		try list = FileSystem.readDirectory(dir)
		catch (e:Dynamic) return;
		var dirs:Array<String> = [];
		for (f in list)
		{
			var full = dir + "/" + f;
			var isDir = false;
			try isDir = FileSystem.isDirectory(full)
			catch (eD:Dynamic) isDir = false;
			if (isDir)
			{
				tree.push({path: full, name: f, dir: true, depth: depth, kind: "dir", size: 0});
				dirs.push(full);
				continue;
			}
			var k = kindOf(f);
			if (k == "other") continue;
			var sz = 0;
			try sz = FileSystem.stat(full).size
			catch (eS:Dynamic) sz = 0;
			tree.push({path: full, name: f, dir: false, depth: depth, kind: k, size: sz});
		}
		var i = dirs.length - 1;
		while (i >= 0)
		{
			if (depth + 1 <= MAX_DEPTH) walkStack.push({d: dirs[i], depth: depth + 1});
			i--;
		}
	}

	public static function scanPacks():Array<String>
	{
		packs = [];
		var base = "packs";
		if (!FileSystem.exists(base) || !FileSystem.isDirectory(base)) return packs;
		try
		{
			for (f in FileSystem.readDirectory(base))
			{
				var full = base + "/" + f;
				if (FileSystem.isDirectory(full) && FileSystem.exists(full + "/assets")) packs.push(f);
			}
		}
		catch (e:Dynamic) { R3DLog.silentFailure("AssetLibrary.scanPacks", e); }
		if (packs.length > 0 && (curPack.length == 0 || packs.indexOf(curPack) < 0)) curPack = packs[0];
		return packs;
	}

	public static function packAssetsDir(pack:String):String
	{
		return "packs/" + (pack.length == 0 ? "shop" : pack) + "/assets";
	}

	public static function scanEntries(pack:String, kindFilter:String):Array<AssetEntry>
	{
		curPack = pack;
		filter = kindFilter;
		entries = [];
		var base = packAssetsDir(pack);
		var has = false;
		try has = FileSystem.exists(base) && FileSystem.isDirectory(base)
		catch (eD:Dynamic) has = false;
		if (!has) return entries;
		var baseSlashes = 0;
		for (i in 0...base.length)
			if (base.charCodeAt(i) == 47) baseSlashes++;
		for (e in tree)
		{
			if (e.path.length <= base.length) continue;
			if (!StringTools.startsWith(e.path, base)) continue;
			if (!visibleByExpansion(e.path, base)) continue;
			if (!e.dir && kindFilter != "all" && e.kind != kindFilter) continue;
			// The walk records depth from the scan root; the panel wants it from the pack
			// root, and files sit at the depth of their directory.
			var slashes = 0;
			for (i in 0...e.path.length)
				if (e.path.charCodeAt(i) == 47) slashes++;
			e.depth = slashes - baseSlashes - 1;
			if (e.depth < 0) e.depth = 0;
			entries.push(e);
		}
		if (!treeReady) scanAsync();
		return entries;
	}

	static function visibleByExpansion(path:String, base:String):Bool
	{
		var d = dirOf(path);
		while (d.length > base.length)
		{
			if (!isExpanded(d)) return false;
			var up = dirOf(d);
			if (up == d || up.length < base.length) break;
			d = up;
		}
		return true;
	}

	public static function isExpanded(path:String):Bool
	{
		return !expanded.exists(path) ? true : expanded.get(path);
	}

	public static function toggleExpanded(path:String):Bool
	{
		var v = !isExpanded(path);
		expanded.set(path, v);
		return v;
	}

	public static function count():Int
	{
		scan();
		return files.length;
	}

	public static function at(i:Int):String
	{
		scan();
		if (files.length == 0) return "";
		var k = i % files.length;
		if (k < 0) k += files.length;
		return files[k];
	}

	public static function modelAt(i:Int):String
	{
		scan();
		if (models.length == 0) return "";
		var k = i % models.length;
		if (k < 0) k += models.length;
		return models[k];
	}

	public static function shortName(path:String):String
	{
		if (path == null || path.length == 0) return "(空)";
		var i = path.lastIndexOf("/");
		return i < 0 ? path : path.substr(i + 1);
	}

	public static function dirOf(path:String):String
	{
		if (path == null) return "";
		var i = path.lastIndexOf("/");
		return i < 0 ? "" : path.substr(0, i);
	}

	public static function indexOf(path:String):Int
	{
		scan();
		return files.indexOf(path);
	}

	public static function texture(path:String):R3DTexture
	{
		if (path == null || path.length == 0) return null;
		if (cache.exists(path))
		{
			var c = cache.get(path);
			if (c != null && !c.disposed) return c;
		}
		var t:R3DTexture = null;
		try
		{
			t = R3DTexture.fromFile(path, {wrapMode: R3DWrap.REPEAT, filter: R3DFilter.LINEAR, mipFilter: R3DMipFilter.MIPLINEAR});
		}
		catch (e:Dynamic)
		{
			t = null;
		}
		if (t == null)
		{
			lastError = "无法载入 " + path;
			R3DLog.error("Shop3D", "贴图载入失败: " + path);
			return null;
		}
		cache.set(path, t);
		return t;
	}

	public static var MAX_THUMB_BYTES:Int = 33554432;

	public static var maxThumbSourcePx:Int = 4194304;

	public static var thumbDir:String = "assets/cache/thumbs";

	public static function thumbnail(path:String, maxSize:Int = 96):BitmapData
	{
		if (path == null || path.length == 0) return null;
		if (thumbCache.exists(path)) return thumbCache.get(path);
		// Remembered so the inspector does not re-stat and re-read the header of the same
		// 750MB atlas on every repaint just to conclude again that it has no thumbnail.
		if (thumbMiss.exists(path)) return null;

		var baked = loadBakedThumb(path);
		if (baked != null)
		{
			thumbCache.set(path, baked);
			return baked;
		}

		var sz = 0;
		try sz = FileSystem.stat(path).size
		catch (e:Dynamic) R3DLog.silentFailure("AssetLibrary.thumbnail", e);
		if (sz > MAX_THUMB_BYTES)
		{
			thumbMiss.set(path, true);
			return null;
		}

		// Read the header before decoding: the dimensions alone decide whether a 96px
		// thumbnail is representable at a sane cost.
		var dim = pngSizeOf(path);
		if (dim != null && dim[0] > 0 && dim[1] > 0 && dim[0] * dim[1] > maxThumbSourcePx)
		{
			thumbMiss.set(path, true);
			return null;
		}

		var b:BitmapData = null;
		try b = BitmapData.fromFile(path)
		catch (eD:Dynamic) b = null;
		if (b == null)
		{
			thumbMiss.set(path, true);
			return null;
		}
		var w = b.width;
		var h = b.height;
		var sc = Math.min(maxSize / Math.max(w, 1), maxSize / Math.max(h, 1));
		if (sc < 1)
		{
			var nw = Std.int(Math.max(4, w * sc));
			var nh = Std.int(Math.max(4, h * sc));
			var small = new BitmapData(nw, nh, true, 0x00000000);
			small.draw(b, new openfl.geom.Matrix(nw / w, 0, 0, nh / h, 0, 0));
			b = small;
		}
		thumbCache.set(path, b);
		return b;
	}

	public static function hash32(path:String):String
	{
		var s = path.toLowerCase();
		var h:Int = 0x811C9DC5;
		for (i in 0...s.length)
		{
			h = h ^ s.charCodeAt(i);
			h = h * 0x01000193;
		}
		return StringTools.hex(h & 0x7FFFFFFF, 8).toLowerCase();
	}

	static function loadBakedThumb(path:String):BitmapData
	{
		if (thumbDir == null || thumbDir.length == 0) return null;
		var f = thumbDir + "/" + hash32(path) + ".png";
		var ok = false;
		try ok = FileSystem.exists(f)
		catch (eD:Dynamic) ok = false;
		if (!ok) return null;
		var b:BitmapData = null;
		try b = BitmapData.fromFile(f)
		catch (eB:Dynamic) b = null;
		return b;
	}

	static function pngSizeOf(path:String):Array<Int>
	{
		var inp:haxe.io.Input = null;
		try inp = sys.io.File.read(path, true)
		catch (eD:Dynamic) return null;
		try
		{
			var head = inp.read(24);
			inp.close();
			inp = null;
			if (head.length < 24) return null;
			if (head.get(0) != 0x89 || head.get(1) != 0x50 || head.get(2) != 0x4E || head.get(3) != 0x47) return null;
			return [head.getInt32(16), head.getInt32(20)];
		}
		catch (eR:Dynamic)
		{
			if (inp != null)
			{
				try inp.close() catch (eC:Dynamic) R3DLog.silentFailure("AssetLibrary.pngSizeOf", eC);
			}
			return null;
		}
	}

	public static function info(path:String):String
	{
		var t = texture(path);
		if (t == null) return "(载入失败)";
		return t.width + "x" + t.height + "  各向异性 x" + t.anisotropy;
	}

	public static function clearCache():Void
	{
		for (k in cache.keys())
		{
			var t = cache.get(k);
			if (t != null) t.dispose();
		}
		cache = new StringMap();
	}

	public static function trim(referenced:Array<String>):Int
	{
		var n = 0;
		var dead:Array<String> = [];
		for (k in cache.keys())
		{
			if (referenced.indexOf(k) >= 0) continue;
			var t = cache.get(k);
			if (t != null) t.dispose();
			dead.push(k);
			n++;
		}
		for (k in dead) cache.remove(k);
		if (n > 0) R3DLog.info("Shop3D", "卸载未引用贴图 " + n + " 张");
		return n;
	}

	public static function dispose():Void
	{
		clearCache();
		thumbCache = new StringMap();
		thumbMiss = new StringMap();
		files = [];
		models = [];
		shaders = [];
		entries = [];
		resetTree();
	}
}
