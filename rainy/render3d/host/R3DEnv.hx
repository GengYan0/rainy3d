package rainy.render3d.host;

import openfl.display.BitmapData;

typedef RGB = {
	r:Null<Int>,
	g:Null<Int>,
	b:Null<Int>
}

class R3DEnv
{

	public static var lodBias:Float = 0;

	/**
	 * Rasterisation multiplier for supersampling; 1 disables it.
	 */
	public static var superSample:Float = 1;

	public static var textureBudgetMB:Float = 512;

	public static var dataPath:String->String = p -> p;

	/**
	 * Resolves a path inside the log folder.
	 */
	public static var logPath:String->String = p -> p;

	public static var imagePath:String->String = p -> '';

	/**
	 * Upload accounting: `(bytes, milliseconds)`.
	 */
	public static var upload:Float->Float->Void = (bytes, ms) -> {};

	/**
	 * Draw accounting: `(drawCalls, triangles)`.
	 */
	public static var drawStats:Int->Int->Void = (calls, tris) -> {};

	public static var probeEnabled:Void->Bool = () -> false;
	public static var probeBegin:Int->Void = id -> {};
	public static var probeGrab:Int->Int->Bool = (w, h) -> false;

	public static var applyQuality:Void->Void = () -> {};

	public static function reset():Void
	{
		lodBias = 0;
		superSample = 1;
		textureBudgetMB = 512;
		dataPath = p -> p;
		logPath = p -> p;
		imagePath = p -> '';
		upload = (bytes, ms) -> {};
		drawStats = (calls, tris) -> {};
		probeEnabled = () -> false;
		probeBegin = id -> {};
		probeGrab = (w, h) -> false;
		applyQuality = () -> {};
	}
}
