package rainy.render3d.core;

class R3DDepth
{

	public static inline var ALWAYS:Int = 0;
	public static inline var EQUAL:Int = 1;
	public static inline var GREATER:Int = 2;
	public static inline var GREATER_EQUAL:Int = 3;
	public static inline var LESS:Int = 4;
	public static inline var LESS_EQUAL:Int = 5;
	public static inline var NEVER:Int = 6;
	public static inline var NOT_EQUAL:Int = 7;

	public static var reversed(default, null):Bool = true;

	public static var clearValue(default, null):Float = 0.0;

	/** Depth compare mode matching `reversed`. */
	public static var func(default, null):Int = GREATER_EQUAL;

	public static var ndcNear(default, null):Float = 1.0;
	public static var ndcFar(default, null):Float = -1.0;

	public static var sign(default, null):Float = 1.0;

	static var listeners:Array<Void->Void> = [];

	public static function setReversed(on:Bool):Void
	{
		if (on == reversed && clearValue == (on ? 0.0 : 1.0))
			return;
		reversed = on;
		clearValue = on ? 0.0 : 1.0;
		func = on ? GREATER_EQUAL : LESS_EQUAL;
		ndcNear = on ? 1.0 : -1.0;
		ndcFar = on ? -1.0 : 1.0;
		sign = on ? 1.0 : -1.0;
		for (cb in listeners)
			cb();
	}

	public static function addListener(cb:Void->Void):Void
	{
		if (cb != null && listeners.indexOf(cb) < 0)
			listeners.push(cb);
	}

	public static function removeListener(cb:Void->Void):Void
	{
		if (cb != null) listeners.remove(cb);
	}

	public static function compareMode():Int
	{
		return func;
	}

	public static function glslLinearize(fnName:String = 'r3d_LinearDepth'):String
	{
		return 'float ' + fnName + '(float d, float n, float f, float sign)\n'
			+ '{\n'
			+ '\tfloat z = d * 2.0 - 1.0;\n'
			+ '\treturn (2.0 * n * f) / ((f + n) + sign * z * (f - n));\n'
			+ '}\n';
	}

	public static function glslIsSky(depthExpr:String, eps:Float = 0.0001):String
	{
		return reversed
			? '($depthExpr <= ' + eps + ')'
			: '($depthExpr >= ' + (1.0 - eps) + ')';
	}

	public static function listenerCount():Int
	{
		return listeners.length;
	}

	public static function describe():String
	{
		return 'depth ' + (reversed ? 'reversed' : 'standard')
			+ ' clear=' + clearValue + ' func=' + func + ' sign=' + (sign > 0 ? '+1' : '-1');
	}
}
