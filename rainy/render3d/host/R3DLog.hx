package rainy.render3d.host;

class R3DLog
{
	public static inline var INFO:Int = 1;
	public static inline var WARN:Int = 2;
	public static inline var ERROR:Int = 3;

	public static var sink:Int->String->Void = defaultSink;

	public static var missingSink:String->String->Array<String>->String->Void = null;

	static var _missingSeen:Map<String, Bool> = new Map();

	public static function info(tag:String, msg:String):Void
	{
		emit(INFO, tag, msg);
	}

	public static function warn(tag:String, msg:String):Void
	{
		emit(WARN, tag, msg);
	}

	public static function error(tag:String, msg:String):Void
	{
		emit(ERROR, tag, msg);
	}

	public static function silentFailure(where:String, e:Dynamic):Void
	{
		emit(WARN, where, Std.string(e));
	}

	public static function capture(e:Dynamic, tag:String, what:String):Void
	{
		final detail = Std.string(e);
		emit(ERROR, tag, what + ': ' + detail);
	}

	public static function missingAsset(kind:String, key:String, candidates:Array<String>, ?pack:String):Void
	{
		final when = missingSink;
		if (when != null)
		{
			when(kind, key, candidates, pack);
			return;
		}

		final id = kind + '|' + key;
		if (_missingSeen.exists(id))
			return;
		_missingSeen.set(id, true);

		var tried = '';
		for (path in candidates)
			tried += '\n  - ' + path;

		emit(WARN, 'missing', 'missing ' + kind + ': ' + key + (pack != null ? ' [' + pack + ']' : '') + tried);
	}

	inline static function emit(level:Int, tag:String, msg:String):Void
	{
		final fn = sink;
		if (fn == null)
			return;
		fn(level, (tag != null ? '[' + tag + '] ' : '') + (msg != null ? msg : 'null'));
	}

	static function defaultSink(level:Int, line:String):Void
	{
		#if sys
		Sys.println(line);
		#else
		trace(line);
		#end
	}
}
