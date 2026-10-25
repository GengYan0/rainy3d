package rainy.render3d.stage3d;

import flixel.FlxSprite;
import flixel.graphics.frames.FlxFrame;
import haxe.ds.StringMap;
import rainy.render3d.host.R3DLog;

class AtlasTiles
{

	public static var tileSize:Int = 512;

	static var byKey:StringMap<AtlasTiles> = new StringMap();

	static var trivial:StringMap<Bool> = new StringMap();

	public var key(default, null):String = "";
	public var atlasW(default, null):Int = 0;
	public var atlasH(default, null):Int = 0;
	public var cols(default, null):Int = 1;
	public var rows(default, null):Int = 1;
	public var tileCount(default, null):Int = 1;
	public var frameCount(default, null):Int = 0;
	public var usedTiles(default, null):Int = 0;
	public var worstGroupTiles(default, null):Int = 0;
	public var groupCount(default, null):Int = 0;

	public var maxFrameTiles(default, null):Int = 0;
	public var avgFrameTiles:Float = 0;

	public var groups(default, null):StringMap<Array<Int>> = new StringMap();

	public function new() {}

	public static function forGraphic(key:String, frames:Array<FlxFrame>, w:Int, h:Int):AtlasTiles
	{
		if (key == null || key.length == 0 || frames == null || w <= 0 || h <= 0) return null;
		var hit = byKey.get(key);
		if (hit != null) return hit;
		if (w <= tileSize && h <= tileSize)
		{
			trivial.set(key, true);
			return null;
		}

		var t = new AtlasTiles();
		t.key = key;
		t.atlasW = w;
		t.atlasH = h;
		t.cols = Std.int((w + tileSize - 1) / tileSize);
		t.rows = Std.int((h + tileSize - 1) / tileSize);
		if (t.cols < 1) t.cols = 1;
		if (t.rows < 1) t.rows = 1;
		t.tileCount = t.cols * t.rows;

		var touched:Array<Bool> = [];
		touched.resize(t.tileCount);
		var frameTileSum:Int = 0;

		for (f in frames)
		{
			if (f == null) continue;
			var r = f.frame;
			if (r == null || r.width <= 0 || r.height <= 0) continue;
			t.frameCount++;
			var gname = groupOf(f.name);
			var list = t.groups.get(gname);
			if (list == null)
			{
				list = [];
				t.groups.set(gname, list);
			}
			var tx0 = Std.int(r.x / tileSize);
			var ty0 = Std.int(r.y / tileSize);
			var tx1 = Std.int((r.x + r.width - 1) / tileSize);
			var ty1 = Std.int((r.y + r.height - 1) / tileSize);
			if (tx0 < 0) tx0 = 0;
			if (ty0 < 0) ty0 = 0;
			if (tx1 >= t.cols) tx1 = t.cols - 1;
			if (ty1 >= t.rows) ty1 = t.rows - 1;
			for (ty in ty0...ty1 + 1)
			{
				for (tx in tx0...tx1 + 1)
				{
					var idx = ty * t.cols + tx;
					if (idx < 0 || idx >= t.tileCount) continue;
					touched[idx] = true;
					if (list.indexOf(idx) < 0) list.push(idx);
				}
			}
			var own = (tx1 - tx0 + 1) * (ty1 - ty0 + 1);
			frameTileSum += own;
			if (own > t.maxFrameTiles) t.maxFrameTiles = own;
		}
		if (t.frameCount > 0) t.avgFrameTiles = frameTileSum / t.frameCount;

		for (i in 0...t.tileCount)
			if (touched[i]) t.usedTiles++;

		for (g in t.groups.keys())
		{
			var l = t.groups.get(g);
			if (l == null) continue;
			t.groupCount++;
			if (l.length > t.worstGroupTiles) t.worstGroupTiles = l.length;
		}

		byKey.set(key, t);
		R3DLog.info('r3d', 'tiles ' + key + ': ' + t.tileCount + ' tile (' + t.cols + 'x' + t.rows + ' of ' + tileSize
			+ '), ' + t.frameCount + ' 帧 ' + t.groupCount + ' 组, 单帧 ' + Std.int(t.avgFrameTiles) + ' 至 ' + t.maxFrameTiles
			+ ' tile (' + Std.int(t.avgFrameTiles * tileMB(1)) + '~' + Std.int(tileMB(t.maxFrameTiles)) + 'MB)'
			+ ', 单组最多 ' + t.worstGroupTiles + ' tile, 全载 ' + Std.int(t.fullMB()) + 'MB');
		return t;
	}

	public static function note(spr:FlxSprite):Void
	{
		if (spr == null) return;
		var g = spr.graphic;
		if (g == null || g.key == null || g.key.length == 0) return;
		if (byKey.exists(g.key) || trivial.exists(g.key)) return;
		var coll = spr.frames;
		if (coll == null || coll.frames == null) return;
		forGraphic(g.key, coll.frames, g.width, g.height);
	}

	static function groupOf(name:String):String
	{
		if (name == null || name.length == 0) return "(unnamed)";
		var i = name.length;
		while (i > 0)
		{
			var c = name.charCodeAt(i - 1);
			if (c < 48 || c > 57) break;
			i--;
		}
		return i == 0 ? name : name.substr(0, i);
	}

	static inline function tileMB(n:Int):Float
	{
		return n * tileSize * tileSize * 4.0 / 1048576.0;
	}

	public function fullMB():Float return tileMB(tileCount);

	public function frameMB():Float return tileMB(maxFrameTiles);

	public function report():String
	{
		return key + '  ' + atlasW + 'x' + atlasH + ' -> ' + cols + 'x' + rows + ' = ' + tileCount + ' tile'
			+ ' | ' + frameCount + ' 帧 ' + groupCount + ' 组 | 单帧 ' + Std.int(avgFrameTiles) + '~' + maxFrameTiles
			+ ' tile (' + Std.int(tileMB(Std.int(avgFrameTiles))) + '~' + Std.int(frameMB()) + 'MB)'
			+ ' | 单组最多 ' + worstGroupTiles + ' tile | 全载 ' + Std.int(fullMB()) + 'MB';
	}

	public static function reportAll():String
	{
		var n = 0;
		var full = 0.0;
		var frame = 0.0;
		var body = new StringBuf();
		for (k in byKey.keys())
		{
			var t = byKey.get(k);
			if (t == null) continue;
			n++;
			full += t.fullMB();
			frame += t.frameMB();
			body.add('\n  ' + t.report());
		}
		if (n == 0) return 'r3d tiles: 还没有超过 ' + tileSize + 'px 的图集被索引';
		return 'r3d tiles: ' + n + ' 个超尺寸图集, 全载 ' + Std.int(full) + 'MB -> 单帧峰值 ' + Std.int(frame)
			+ 'MB (省 ' + Std.int((1.0 - frame / Math.max(full, 1.0)) * 100) + '%)'
			+ ' | tile ' + tileSize + 'px = ' + Std.int(tileMB(1)) + 'MB' + body.toString();
	}
}
