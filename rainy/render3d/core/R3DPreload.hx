package rainy.render3d.core;

typedef R3DPreloadTask = {
	var name:String;
	var job:Void->Void;
}

class R3DPreload
{
	public static var budgetMs:Float = 3.5;
	public static var maxPerFrame:Int = 2;
	public static var done:Int = 0;
	public static var failed:Int = 0;
	public static var lastError:String = "";

	static var q:Array<R3DPreloadTask> = [];
	static var busy:Bool = false;

	public static function push(name:String, job:Void->Void):Void
	{
		if (job == null) return;
		q.push({name: name, job: job});
	}

	public static function clear():Void
	{
		q = [];
	}

	public static function pending():Int
	{
		return q.length;
	}

	public static function update():Int
	{
		if (busy || q.length == 0) return 0;
		busy = true;
		var n = 0;
		var t0 = haxe.Timer.stamp();
		while (q.length > 0 && n < maxPerFrame)
		{
			// Checked before starting the next job, so one slow decode cannot overrun by a second job.
			if (n > 0 && (haxe.Timer.stamp() - t0) * 1000.0 >= budgetMs) break;
			var t = q.shift();
			try
			{
				t.job();
				done++;
			}
			catch (e:Dynamic)
			{
				failed++;
				lastError = t.name + ": " + Std.string(e);
			}
			n++;
			if ((haxe.Timer.stamp() - t0) * 1000.0 >= budgetMs) break;
		}
		busy = false;
		return n;
	}

	public static function info():String
	{
		return "预加载 完成 " + done + " 待处理 " + q.length + (failed > 0 ? (" 失败 " + failed) : "");
	}
}
