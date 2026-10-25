package rainy.render3d.core;

import rainy.render3d.host.R3DEnv;

import rainy.render3d.host.R3DLog;
import lime.graphics.opengl.GL;
import openfl.display3D.Context3D;
import openfl.display3D.Context3DTextureFormat;
import openfl.display3D.textures.Texture;
import openfl.display3D.textures.TextureBase;
import openfl.display.BitmapData;
import openfl.geom.Matrix;
import rainy.render3d.core.R3D.R3DFilter;
import rainy.render3d.core.R3D.R3DMipFilter;
import rainy.render3d.core.R3D.R3DWrap;

class R3DTexture
{
	public var glTexture:Texture;
	public var glAny:TextureBase = null;
	public var wrapMode:R3DWrap = R3DWrap.CLAMP;
	public var filter:R3DFilter = R3DFilter.LINEAR;
	public var mipFilter:R3DMipFilter = R3DMipFilter.MIPNONE;
	public var width(default, null):Int = 0;
	public var height(default, null):Int = 0;
	public var anisotropy:Int = 1;
	public var path:String = "";
	public var disposed:Bool = false;
	public var id:Int = 0;

	static var __seq:Int = 0;

	public function new()
	{
		id = ++__seq;
	}

	public static function wrap(tex:TextureBase, w:Int, h:Int):R3DTexture
	{
		if (tex == null) return null;
		var t:R3DTexture = new R3DTexture();
		t.glAny = tex;
		t.width = w;
		t.height = h;
		t.path = "wrap";
		return t;
	}

	public inline function valid():Bool
		return glAny != null || glTexture != null;

	public inline function handle():TextureBase
		return glAny != null ? glAny : glTexture;

	public static var lastFallback:String = "";

	public static var compress:Bool = true;

	public static var maxSize:Int = 0;
	public static var fitCount:Int = 0;

	public static var fitLastReason:String = "";

	public static function capSize():Int
	{
		var cap:Int = maxSize > 0 ? maxSize : (R3DCaps.detected ? R3DCaps.maxTextureSize : 16384);
		return cap < 32 ? 32 : cap;
	}

	public static function fit(b:BitmapData, ?wantMips:Bool = false):BitmapData
	{
		if (b == null) return b;
		var w:Int = b.width;
		var h:Int = b.height;
		if (w <= 0 || h <= 0) return b;

		var cap:Int = capSize();

		var tw:Int = w;
		var th:Int = h;
		var reason:String = "";

		if (tw > cap || th > cap)
		{
			var k:Float = Math.min(cap / tw, cap / th);
			tw = Std.int(tw * k);
			th = Std.int(th * k);
			if (tw < 1) tw = 1;
			if (th < 1) th = 1;
			reason = "over maxTextureSize " + cap;
		}

		var needPot:Bool = !R3DCaps.npotSupported || (wantMips && !R3DCaps.npotMipmap);
		if (needPot)
		{
			var pw:Int = 1;
			while (pw < tw) pw <<= 1;
			var ph:Int = 1;
			while (ph < th) ph <<= 1;
			while (pw > cap) pw >>= 1;
			while (ph > cap) ph >>= 1;
			if (pw < 1) pw = 1;
			if (ph < 1) ph = 1;
			if (pw != tw || ph != th)
			{
				tw = pw;
				th = ph;
				if (reason.length == 0) reason = R3DCaps.npotSupported ? "no NPOT+mip" : "no NPOT";
			}
		}

		if (tw == w && th == h) return b;

		var o:BitmapData = null;
		try
		{
			o = new BitmapData(tw, th, true, 0x00000000);
			var m = new Matrix();
			m.scale(tw / w, th / h);
			o.draw(b, m, null, null, null, true);
		}
		catch (e:Dynamic)
		{
			o = null;
		}
		if (o == null) return b;
		fitCount++;
		fitLastReason = w + "x" + h + " -> " + tw + "x" + th + " (" + reason + ")";
		return o;
	}

	static function clearGlErrors():Void
	{
		try
		{
			var guard:Int = 0;
			while (GL.getError() != 0 && guard < 16) guard++;
		}
		catch (e:Dynamic) { R3DLog.silentFailure("R3DTexture.clearGlErrors", e); }
	}

	static function uploadOnce(data:BitmapData, format:Dynamic, mipmaps:Bool,
		?params:{?wrapMode:R3DWrap, ?filter:R3DFilter, ?mipFilter:R3DMipFilter, ?anisotropy:Int}):R3DTexture
	{
		var ctx = R3DShader.context == null ? openfl.Lib.current.stage.context3D : R3DShader.context;
		var fmt = format == null ? Context3DTextureFormat.BGRA : cast format;
		var tex:Texture = null;
		try
		{
			clearGlErrors();
			tex = ctx.createTexture(data.width, data.height, fmt, false);
			tex.uploadFromBitmapData(data, 0, mipmaps);
			if (GL.getError() != 0)
			{
				try tex.dispose() catch (e1:Dynamic) { R3DLog.silentFailure("R3DTexture.uploadOnce", e1); }
				return null;
			}
		}
		catch (eUp:Dynamic)
		{
			if (tex != null)
			{
				try tex.dispose() catch (e2:Dynamic) { R3DLog.silentFailure("R3DTexture.uploadOnce", e2); }
			}
			return null;
		}
		var t = new R3DTexture();
		t.glTexture = tex;
		t.width = data.width;
		t.height = data.height;
		t.wrapMode = R3DWrap.REPEAT;
		t.filter = R3DFilter.LINEAR;
		t.mipFilter = mipmaps ? R3DMipFilter.MIPLINEAR : R3DMipFilter.MIPNONE;
		if (params != null)
		{
			if (params.wrapMode != null) t.wrapMode = params.wrapMode;
			if (params.filter != null) t.filter = params.filter;
			if (params.mipFilter != null) t.mipFilter = params.mipFilter;
			if (params.anisotropy != null) t.anisotropy = params.anisotropy;
		}
		// Invariant: never ask for a mip filter on a texture that has no mip chain. The
		// driver treats that as an incomplete texture and samples it black, so a caller
		// pairing `mipmaps = false` with `mipFilter: MIPLINEAR` would ship an invisible
		// texture with no error anywhere.
		if (!mipmaps) t.mipFilter = R3DMipFilter.MIPNONE;
		if (t.anisotropy <= 1 && R3DCaps.presetAniso > 1) t.anisotropy = R3DCaps.presetAniso;
		t.applyAnisotropy();
		return t;
	}

	public static function fromBitmapData(data:BitmapData, format:Dynamic = null, ?mipmaps:Null<Bool> = null,
		?params:{?wrapMode:R3DWrap, ?filter:R3DFilter, ?mipFilter:R3DMipFilter, ?anisotropy:Int}):R3DTexture
	{
		if (data == null) return null;
		// `compress` is a veto over mip generation; an explicit false from the caller still
		// means false. A per-frame billboard texture is drawn at roughly its own pixel size,
		// so a mip chain for it costs a third more VRAM and only softens the result.
		var doMips:Bool = compress && (mipmaps == null ? true : mipmaps);
		// Sized after the mip decision, because "NPOT + mip chain" is its own capability.
		// `fit` may return a freshly allocated resampled copy; the caller's bitmap is never
		// ours to free, but that copy is, so every exit path below releases it.
		var source:BitmapData = data;
		data = fit(data, doMips);
		var resampled:Bool = (data != source);
		var w0:Int = data.width;
		var h0:Int = data.height;
		var tStart:Float = haxe.Timer.stamp();
		var t:R3DTexture = uploadOnce(data, format, doMips, params);
		if (t != null)
		{
			R3DEnv.upload(w0 * h0 * 4.0, (haxe.Timer.stamp() - tStart) * 1000.0);
			if (resampled) disposeQuietly(data);
			return t;
		}
		var w:Int = w0;
		var h:Int = h0;
		var cur:BitmapData = data;
		while (t == null && w > 16 && h > 16)
		{
			w = Std.int(w / 2);
			h = Std.int(h / 2);
			var small:BitmapData = null;
			try
			{
				small = new BitmapData(w, h, true, 0x00000000);
				var m = new Matrix();
				m.scale(w / cur.width, h / cur.height);
				small.draw(cur, m, null, null, null, true);
			}
			catch (eD:Dynamic)
			{
				small = null;
			}
			if (small == null) break;
			// `data` belongs to the caller; the intermediate halvings are ours to free.
			if (cur != data)
			{
				disposeQuietly(cur);
			}
			cur = small;
			t = uploadOnce(cur, format, doMips, params);
		}
		// Success or not, nothing below needs the pixels anymore: the texture owns its copy.
		if (cur != data) disposeQuietly(cur);
		if (resampled) disposeQuietly(data);
		if (t != null)
		{
			lastFallback = w0 + "x" + h0 + " -> " + w + "x" + h;
			R3DLog.warn('r3d', 'texture upload failed at ' + w0 + 'x' + h0 + ', fell back to ' + w + 'x' + h);
		}
		return t;
	}

	static function disposeQuietly(b:BitmapData):Void
	{
		if (b == null) return;
		try b.dispose() catch (e:Dynamic) { R3DLog.silentFailure("R3DTexture.disposeQuietly", e); }
	}

	public static function fromFile(path:String, ?params:{?wrapMode:R3DWrap, ?filter:R3DFilter, ?mipFilter:R3DMipFilter, ?anisotropy:Int}):R3DTexture
	{
		var data:BitmapData = null;
		try
		{
			data = BitmapData.fromFile(path);
		}
		catch (e:Dynamic)
		{
			data = null;
		}
		if (data == null) return null;
		var t = fromBitmapData(data, null, true, params);
		if (t != null) t.path = path;
		return t;
	}

	public function setAnisotropy(level:Int):Int
	{
		anisotropy = R3DCaps.clampAniso(level);
		applyAnisotropy();
		return anisotropy;
	}

	public function applyAnisotropy():Void
	{
		if (!R3DCaps.anisoSupported || anisotropy <= 1 || glTexture == null) return;
		try
		{
			var id:Dynamic = @:privateAccess glTexture.__textureID;
			// Park on the last unit the driver actually has; a hardcoded 15 is out of range
			// on a context that reports fewer fragment units.
			var unit:Int = R3DCaps.maxTextureUnits - 1;
			if (unit < 0) unit = 0;
			GL.activeTexture(GL.TEXTURE0 + unit);
			GL.bindTexture(GL.TEXTURE_2D, id);
			GL.texParameterf(GL.TEXTURE_2D, 0x84FE, cast Math.min(anisotropy, Math.max(1, R3DCaps.maxAnisotropy)));
			GL.bindTexture(GL.TEXTURE_2D, 0);
			GL.activeTexture(GL.TEXTURE0);
			R3DGLStateCache.invalidateOpenfl();
		}
		catch (e:Dynamic) { R3DLog.silentFailure("R3DTexture.applyAnisotropy", e); }
	}

	public static function create(width:Int, height:Int, format:Dynamic = null):R3DTexture
	{
		var ctx = R3DShader.context == null ? openfl.Lib.current.stage.context3D : R3DShader.context;
		var fmt = format == null ? Context3DTextureFormat.BGRA : cast format;
		var t = new R3DTexture();
		t.glTexture = ctx.createTexture(width, height, fmt, true);
		t.width = width;
		t.height = height;
		return t;
	}

	public function destroy():Void
	{
		dispose();
	}

	public function asBitmapData():BitmapData
	{
		if (glTexture == null) return null;
		return BitmapData.fromTexture(glTexture);
	}

	public function dispose():Void
	{
		if (disposed) return;
		disposed = true;
		if (glTexture != null)
		{
			try glTexture.dispose() catch (e:Dynamic) { R3DLog.silentFailure("R3DTexture.dispose", e); }
			glTexture = null;
		}
	}
}
