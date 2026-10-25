package rainy.render3d.stage3d;

import flixel.graphics.FlxGraphic;
import openfl.display.BitmapData;
import rainy.render3d.host.R3DLog;
import rainy.render3d.core.R3D.R3DFilter;
import rainy.render3d.core.R3D.R3DMipFilter;
import rainy.render3d.core.R3D.R3DWrap;
import rainy.render3d.core.R3DTexture;

class Stage3DAtlasCache
{
	public static var enabled:Bool = true;
	public static var maxSize:Int = 4096;
	public static var keep:Int = 4;
	public static var budgetMB:Int = 768;

	public static var wholeMaxMB:Int = 96;

	public static var skippedTooBig:Int = 0;

	static var map:Map<String, R3DTexture> = new Map();
	static var order:Array<String> = [];
	static var bytes:Int = 0;

	static var declinedKeys:Map<String, Bool> = new Map();

	static function decline(key:String):Void
	{
		if (declinedKeys.exists(key)) return;
		declinedKeys.set(key, true);
		skippedTooBig++;
	}

	public static function declinedFor3D(key:String):Bool
	{
		return key != null && declinedKeys.exists(key);
	}

	public static function get(key:String):R3DTexture
	{
		if (key == null || key.length == 0) return null;
		var t:R3DTexture = map.get(key);
		if (t == null) return null;
		if (t.disposed)
		{
			// A disposer outside this class got to it first. Treat as a miss instead of
			// handing out a GL name that no longer exists.
			map.remove(key);
			var i:Int = order.indexOf(key);
			if (i >= 0) order.splice(i, 1);
			bytes -= costOf(t);
			if (bytes < 0) bytes = 0;
			return null;
		}
		touch(key);
		return t;
	}

	public static function size():Int return order.length;

	public static function stats():String
	{
		var names:Array<String> = [];
		for (k in order) names.push(k);
		return 'r3d atlas: ' + order.length + '/' + keep + ' textures, ' + Math.round(bytes / 1048576.0) + '/' + budgetMB + ' MB'
			+ (skippedTooBig > 0 ? ', 整图跳过 ' + skippedTooBig + ' 张(改走帧级/在位纹理)' : '')
			+ (names.length > 0 ? ' [' + names.join(', ') + ']' : '');
	}

	public static function register(key:String, src:BitmapData):Void
	{
		if (!enabled || src == null || key == null || key.length == 0) return;
		if (map.exists(key) || declinedKeys.exists(key)) return;

		var w:Int = Std.int(src.width);
		var h:Int = Std.int(src.height);
		if (w <= 1 || h <= 1) return;

		// Falls back to per-frame cropping instead of resampling: `maxSize` is the preset cap,
		// `R3DTexture.capSize()` the hardware/editor limit, and the stricter one wins.
		var cap:Int = R3DTexture.capSize();
		if (maxSize > 0 && maxSize < cap) cap = maxSize;
		if (cap < 256) cap = 256;
		if (w > cap || h > cap)
		{
			decline(key);
			return;
		}
		var mb:Float = w * h * 4.0 / 1048576.0;
		var limit:Int = wholeMaxMB < 8 ? 8 : wholeMaxMB;
		if (mb > limit)
		{
			decline(key);
			return;
		}

		var t:R3DTexture = null;
		try
		{
			t = R3DTexture.fromBitmapData(src, null, true, {
				filter: R3DFilter.LINEAR,
				wrapMode: R3DWrap.CLAMP,
				mipFilter: R3DMipFilter.MIPLINEAR
			});
		}
		catch (e:Dynamic)
		{
			t = null;
		}
		if (t == null) return;

		t.path = key;
		map.set(key, t);
		order.push(key);
		bytes += costOf(t);
		R3DLog.info('r3d', 'atlas3d +' + key + ' ' + Std.int(t.width) + 'x' + Std.int(t.height)
			+ ' ' + Math.round(bytes / 1048576.0) + 'MB');
		evict();
	}

	public static function clear():Int
	{
		var n:Int = order.length;
		for (k in order)
		{
			var t:R3DTexture = map.get(k);
			if (t != null)
			{
				try t.dispose() catch (e:Dynamic) { R3DLog.silentFailure("Stage3DAtlasCache.clear", e); }
			}
		}
		map = new Map();
		order = [];
		bytes = 0;
		// A quality change moves the cap, so the next load must be free to try again.
		declinedKeys = new Map();
		skippedTooBig = 0;
		return n;
	}

	/** RGBA8 + one third for the mip chain. */
	inline static function costOf(t:R3DTexture):Int
	{
		return Std.int(t.width * t.height * 4 * 1.34);
	}

	static function touch(key:String):Void
	{
		var i:Int = order.indexOf(key);
		if (i < 0 || i == order.length - 1) return;
		order.splice(i, 1);
		order.push(key);
	}

	static function evict():Void
	{
		var cap:Int = (keep < 1) ? 1 : keep;
		var limit:Int = (budgetMB < 64 ? 64 : budgetMB) * 1048576;
		while (order.length > 1 && (order.length > cap || bytes > limit))
		{
			var old:String = order.shift();
			var ot:R3DTexture = map.get(old);
			map.remove(old);
			if (ot == null) continue;
			bytes -= costOf(ot);
			if (bytes < 0) bytes = 0;
			R3DLog.info('r3d', 'atlas3d -' + old + ' ' + Math.round(bytes / 1048576.0) + 'MB');
			try ot.dispose() catch (eO:Dynamic) { R3DLog.silentFailure("Stage3DAtlasCache.evict", eO); }
		}
	}
}
