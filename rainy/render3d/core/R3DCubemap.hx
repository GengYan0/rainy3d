package rainy.render3d.core;

import rainy.render3d.host.R3DLog;
import lime.graphics.opengl.GL;
import openfl.display.BitmapData;
import openfl.display3D.Context3D;
import openfl.display3D.Context3DTextureFormat;
import openfl.display3D.textures.CubeTexture;
import rainy.render3d.core.R3DShader;

class R3DCubemap
{
	public static var FACE_PX:Int = 0;
	public static var FACE_NX:Int = 1;
	public static var FACE_PY:Int = 2;
	public static var FACE_NY:Int = 3;
	public static var FACE_PZ:Int = 4;
	public static var FACE_NZ:Int = 5;

	public var glTexture:CubeTexture = null;
	public var faceSize:Int = 0;
	public var disposed:Bool = false;
	public var path:String = "";

	public function new() {}

	public static function create(size:Int, ?format:Dynamic):R3DCubemap
	{
		var ctx = R3DShader.context == null ? openfl.Lib.current.stage.context3D : R3DShader.context;
		if (ctx == null || size <= 0) return null;
		var fmt = format == null ? Context3DTextureFormat.BGRA : cast format;
		var c = new R3DCubemap();
		try
		{
			c.glTexture = ctx.createCubeTexture(size, fmt, false, 0);
			c.faceSize = size;
		}
		catch (e:Dynamic)
		{
			return null;
		}
		return c;
	}

	public static function fromFiles(px:String, nx:String, py:String, ny:String, pz:String, nz:String):R3DCubemap
	{
		var names:Array<String> = [px, nx, py, ny, pz, nz];
		var faces:Array<BitmapData> = [];
		var size = 0;
		for (n in names)
		{
			var b:BitmapData = null;
			try
			{
				b = BitmapData.fromFile(n);
			}
			catch (e:Dynamic)
			{
				b = null;
			}
			if (b == null) return null;
			if (size == 0) size = b.width;
			faces.push(b);
		}
		var c = create(size);
		if (c == null) return null;
		for (side in 0...6)
		{
			c.upload(side, faces[side]);
			faces[side].dispose();
		}
		c.path = px;
		return c;
	}

	public static function fromFolder(dir:String, ext:String = "png"):R3DCubemap
	{
		var d = StringTools.endsWith(dir, "/") ? dir : dir + "/";
		return fromFiles(d + "px." + ext, d + "nx." + ext, d + "py." + ext,
			d + "ny." + ext, d + "pz." + ext, d + "nz." + ext);
	}

	public function upload(side:Int, b:BitmapData):Bool
	{
		if (glTexture == null || b == null || side < 0 || side > 5) return false;
		try
		{
			glTexture.uploadFromBitmapData(b, side);
			if (faceSize == 0) faceSize = b.width;
			return true;
		}
		catch (e:Dynamic)
		{
			return false;
		}
	}

	public function bind(unit:Int):Void
	{
		var ctx = R3DShader.context;
		if (ctx == null || glTexture == null) return;
		try
		{
			ctx.setTextureAt(unit, glTexture);
		}
		catch (e:Dynamic) { R3DLog.silentFailure("R3DCubemap.bind", e); }
	}

	public function bindTo(sh:R3DShader, name:String, unit:Int):Bool
	{
		if (sh == null || glTexture == null) return false;
		bind(unit);
		return sh.setTexture(name, unit);
	}

	public function applyFilter(mode:Int, ?aniso:Int):Void
	{
		if (glTexture == null) return;
		try
		{
			var id:Dynamic = @:privateAccess glTexture.__textureID;
			GL.activeTexture(GL.TEXTURE0 + 15);
			GL.bindTexture(0x8513, id);
			GL.texParameteri(0x8513, GL.TEXTURE_MIN_FILTER, mode);
			GL.texParameteri(0x8513, GL.TEXTURE_MAG_FILTER, mode);
			if (aniso != null && aniso > 1 && R3DCaps.anisoSupported)
			{
				try GL.texParameterf(0x8513, 0x84FE, cast Math.min(aniso, Math.max(1, R3DCaps.maxAnisotropy))) catch (e:Dynamic) { R3DLog.silentFailure("R3DCubemap.applyFilter", e); }
			}
			GL.bindTexture(0x8513, 0);
			GL.activeTexture(GL.TEXTURE0);
			R3DGLStateCache.invalidateOpenfl();
		}
		catch (e2:Dynamic) { R3DLog.silentFailure("R3DCubemap.applyFilter", e2); }
	}

	public function dispose():Void
	{
		if (disposed) return;
		disposed = true;
		if (glTexture != null)
		{
			try glTexture.dispose() catch (e:Dynamic) { R3DLog.silentFailure("R3DCubemap.dispose", e); }
			glTexture = null;
		}
	}

	public function info():String
	{
		return "立方体贴图 " + faceSize + "x" + faceSize + (disposed ? " 已释放" : "");
	}
}
