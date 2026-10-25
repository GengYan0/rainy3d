package rainy.render3d.stage3d;

import flixel.graphics.FlxGraphic;
import openfl.display.BitmapData;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import rainy.render3d.host.R3DLog;
import rainy.render3d.core.R3D.R3DFilter;
import rainy.render3d.core.R3D.R3DMipFilter;
import rainy.render3d.core.R3D.R3DWrap;
import rainy.render3d.core.R3DTexture;

class Stage3DFrameCache
{
	public static var enabled:Bool = true;

	public static var budgetMB:Int = 384;

	public static var keep:Int = 512;

	static var map:Map<String, R3DTexture> = new Map();
	static var order:Array<String> = [];
	static var bytes:Int = 0;

	static var stamp:Map<String, Int> = new Map();

	public static var frameId:Int = 0;

	public static var hits:Int = 0;
	public static var misses:Int = 0;
	public static var uploads:Int = 0;
	public static var evictions:Int = 0;
	public static var uploadMS:Float = 0;

	public static var epoch:Int = 0;

	public static var freedMB:Float = 0;

	public static var lastFail:String = "";

	public static function beginFrame():Void
	{
		frameId++;
	}

	public static function size():Int return order.length;

	public static function stats():String
	{
		var total:Int = hits + misses;
		var rate:Float = total == 0 ? 0 : (hits * 100.0 / total);
		return 'r3d frames: ' + order.length + ' tex, ' + Math.round(bytes / 1048576.0) + '/' + budgetMB + ' MB'
			+ ', 命中 ' + hits + '/' + total + ' (' + Math.round(rate) + '%), 上传 ' + uploads + ' 次 '
			+ Math.round(uploadMS) + 'ms, 淘汰 ' + evictions;
	}

	public static function resetStats():Void
	{
		hits = 0;
		misses = 0;
		uploads = 0;
		evictions = 0;
		uploadMS = 0;
	}

	public static function acquire(g:FlxGraphic, x:Float, y:Float, w:Float, h:Float):R3DTexture
	{
		lastFail = "";
		if (!enabled || g == null || g.bitmap == null)
		{
			lastFail = g == null ? "graphic null" : (g.bitmap == null ? "bitmap null" : "disabled");
			return null;
		}

		// Cropping needs CPU pixels. With `cacheOnGPU` the bitmap only holds a GL handle, and
		// `copyPixels` on such a bitmap is a silent no-op — it would upload a fully transparent
		// texture and cache it under a key that looks valid. The caller has to take the
		// wrapped-handle path instead.
		if (g.bitmap.image == null)
		{
			lastFail = "no CPU pixels (cacheOnGPU)";
			return null;
		}

		var bw:Float = g.bitmap.width;
		var bh:Float = g.bitmap.height;
		var fw:Int = Std.int(Math.max(1, Math.min(w, bw - x)));
		var fh:Int = Std.int(Math.max(1, Math.min(h, bh - y)));
		if (fw <= 0 || fh <= 0)
		{
			lastFail = "degenerate crop " + fw + "x" + fh;
			return null;
		}

		var k:String = keyOf(g.key, Std.int(x), Std.int(y), fw, fh);
		var hit:R3DTexture = map.get(k);
		if (hit != null && !hit.disposed)
		{
			hits++;
			touch(k);
			stamp.set(k, frameId);
			return hit;
		}

		misses++;
		// A disposed entry can still be sitting in the map. Leaving it there means a later
		// eviction pulls the *new* texture out of the map by the same key.
		if (map.exists(k)) forget(k);

		var t:R3DTexture = crop(g, x, y, fw, fh);
		if (t == null) return null;
		t.path = k;
		map.set(k, t);
		order.push(k);
		bytes += costOf(t);
		stamp.set(k, frameId);
		uploads++;
		evict();
		return t;
	}

	static function forget(k:String):Void
	{
		var old:R3DTexture = map.get(k);
		map.remove(k);
		var i:Int = order.indexOf(k);
		if (i >= 0) order.splice(i, 1);
		stamp.remove(k);
		if (old != null)
		{
			bytes -= costOf(old);
			if (bytes < 0) bytes = 0;
		}
	}

	public static function clear():Int
	{
		var n:Int = order.length;
		for (k in order)
		{
			var t:R3DTexture = map.get(k);
			if (t != null)
			{
				try t.dispose() catch (e:Dynamic) { R3DLog.silentFailure("Stage3DFrameCache.clear", e); }
			}
		}
		map = new Map();
		order = [];
		stamp = new Map();
		bytes = 0;
		freedMB = 0;
		lastFail = "";
		// Holders outside this class still point at the names just freed.
		if (n > 0) epoch++;
		resetStats();
		return n;
	}

	static inline function keyOf(gkey:String, x:Int, y:Int, w:Int, h:Int):String
	{
		return gkey + '#' + x + ',' + y + ',' + w + ',' + h;
	}

	static function crop(g:FlxGraphic, x:Float, y:Float, fw:Int, fh:Int):R3DTexture
	{
		var src:BitmapData = g.bitmap;
		var buf:BitmapData = null;
		try
		{
			buf = new BitmapData(fw, fh, true, 0x00000000);
			buf.copyPixels(src, new Rectangle(x, y, fw, fh), new Point(0, 0));
		}
		catch (e:Dynamic)
		{
			lastFail = "copyPixels: " + Std.string(e);
			if (buf != null)
			{
				try buf.dispose() catch (eD:Dynamic) { R3DLog.silentFailure("Stage3DFrameCache.crop", eD); }
			}
			return null;
		}

		var t0:Float = haxe.Timer.stamp();
		var t:R3DTexture = null;
		try
		{
			// No mipmaps: a billboard frame is drawn at roughly its own pixel size on
			// screen, so a mip chain costs a third more VRAM and only blurs it.
			t = R3DTexture.fromBitmapData(buf, null, false, {
				filter: R3DFilter.LINEAR,
				wrapMode: R3DWrap.CLAMP,
				mipFilter: R3DMipFilter.MIPNONE
			});
		}
		catch (eU:Dynamic)
		{
			t = null;
			lastFail = "upload: " + Std.string(eU);
		}
		uploadMS += (haxe.Timer.stamp() - t0) * 1000.0;
		try buf.dispose() catch (eB:Dynamic) { R3DLog.silentFailure("Stage3DFrameCache.crop.dispose", eB); }
		if (t == null && lastFail.length == 0) lastFail = "upload returned null";
		return t;
	}

	inline static function costOf(t:R3DTexture):Int
	{
		return Std.int(t.width) * Std.int(t.height) * 4;
	}

	static function touch(k:String):Void
	{
		var i:Int = order.indexOf(k);
		if (i < 0 || i == order.length - 1) return;
		order.splice(i, 1);
		order.push(k);
	}

	static function evict():Void
	{
		var cap:Int = keep < 8 ? 8 : keep;
		var limit:Int = (budgetMB < 32 ? 32 : budgetMB) * 1048576;
		var dropped:Bool = false;
		while (order.length > 1 && (order.length > cap || bytes > limit))
		{
			var idx:Int = -1;
			for (i in 0...order.length)
			{
				if (stamp.get(order[i]) != frameId)
				{
					idx = i;
					break;
				}
			}
			if (idx < 0) break;

			var old:String = order[idx];
			order.splice(idx, 1);
			stamp.remove(old);
			var ot:R3DTexture = map.get(old);
			map.remove(old);
			if (ot == null) continue;
			var cost:Int = costOf(ot);
			bytes -= cost;
			if (bytes < 0) bytes = 0;
			evictions++;
			dropped = true;
			freedMB += cost / 1048576.0;
			try ot.dispose() catch (e:Dynamic) { R3DLog.silentFailure("Stage3DFrameCache.evict", e); }
		}
		if (dropped) epoch++;
	}
}
