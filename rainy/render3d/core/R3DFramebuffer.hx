package rainy.render3d.core;

import rainy.render3d.host.R3DLog;

import lime.graphics.opengl.GL;
import lime.graphics.opengl.GLFramebuffer;
import lime.graphics.opengl.GLTexture;

class R3DFramebuffer
{
	public var width:Int = 0;
	public var height:Int = 0;
	public var colorTex:GLTexture = null;
	public var depthTex:GLTexture = null;
	public var fbo:GLFramebuffer = null;
	public var complete:Bool = false;
	public var status:Int = 0;
	public var depthFormat:String = 'none';
	public var triedFormats:String = '';

	var prevFbo:Dynamic = null;
	public var bound:Bool = false;

	public function new() {}

	public function attach(color:GLTexture, w:Int, h:Int):Bool
	{
		dispose();
		if (color == null || w < 2 || h < 2) return false;
		width = w;
		height = h;
		colorTex = color;
		triedFormats = '';

		// Leaves the binding as it found it on every exit.
		final previous = currentBinding();

		try
		{
			fbo = GL.createFramebuffer();
			GL.bindFramebuffer(GL.FRAMEBUFFER, fbo);
			GL.framebufferTexture2D(GL.FRAMEBUFFER, GL.COLOR_ATTACHMENT0, GL.TEXTURE_2D, colorTex, 0);
		}
		catch (e:Dynamic)
		{
			R3DLog.capture(e, 'r3dfbo', 'create');
			restoreBinding(previous);
			dispose();
			return false;
		}

		if (!makeDepth())
		{
			status = GL.checkFramebufferStatus(GL.FRAMEBUFFER);
			R3DLog.warn('r3dfbo', 'depth texture: all formats failed: ' + triedFormats);
			restoreBinding(previous);
			dispose();
			return false;
		}

		status = GL.checkFramebufferStatus(GL.FRAMEBUFFER);
		complete = status == GL.FRAMEBUFFER_COMPLETE;
		if (!complete)
			R3DLog.warn('r3dfbo', 'FBO incomplete status=0x' + StringTools.hex(status, 4) + ' depth=' + depthFormat);
		restoreBinding(previous);
		return complete;
	}

	static function currentBinding():Dynamic
	{
		try
			return GL.getParameter(GL.FRAMEBUFFER_BINDING)
		catch (e:Dynamic)
			return null;
	}

	static function restoreBinding(previous:Dynamic):Void
	{
		try GL.bindFramebuffer(GL.FRAMEBUFFER, cast previous) catch (e:Dynamic) {}
	}

	function makeDepth():Bool
	{
		var formats:Array<Array<Int>> = [
			[GL.DEPTH_COMPONENT24, GL.DEPTH_COMPONENT, GL.UNSIGNED_INT, 24],
			[GL.DEPTH_COMPONENT16, GL.DEPTH_COMPONENT, GL.UNSIGNED_SHORT, 16],
			[GL.DEPTH_COMPONENT, GL.DEPTH_COMPONENT, GL.UNSIGNED_INT, 32],
			[GL.DEPTH_COMPONENT, GL.DEPTH_COMPONENT, GL.UNSIGNED_SHORT, 16]
		];

		for (f in formats)
		{
			var label:String = 'internal=0x' + StringTools.hex(f[0], 4) + '/' + f[3] + 'bit';
			var t:GLTexture = null;
			try
			{
				t = GL.createTexture();
				GL.bindTexture(GL.TEXTURE_2D, t);
				GL.texImage2D(GL.TEXTURE_2D, 0, f[0], width, height, 0, f[1], f[2], cast 0);
				GL.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_MIN_FILTER, GL.NEAREST);
				GL.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_MAG_FILTER, GL.NEAREST);
				GL.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_S, GL.CLAMP_TO_EDGE);
				GL.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_T, GL.CLAMP_TO_EDGE);
				GL.framebufferTexture2D(GL.FRAMEBUFFER, GL.DEPTH_ATTACHMENT, GL.TEXTURE_2D, t, 0);
				R3DGLStateCache.invalidateOpenfl();
			}
			catch (e:Dynamic)
			{
				triedFormats += (triedFormats.length > 0 ? ', ' : '') + label + '=exception';
				if (t != null)
				{
					try GL.deleteTexture(t) catch (e2:Dynamic) {}
				}
				continue;
			}

			var st:Int = GL.checkFramebufferStatus(GL.FRAMEBUFFER);
			var err:Int = 0;
			try err = GL.getError() catch (e3:Dynamic) {}

			if (st == GL.FRAMEBUFFER_COMPLETE)
			{
				depthTex = t;
				depthFormat = label;
				triedFormats += (triedFormats.length > 0 ? ', ' : '') + label + '=ok';
				return true;
			}

			triedFormats += (triedFormats.length > 0 ? ', ' : '') + label + '=0x' + StringTools.hex(st, 4)
				+ (err != 0 ? '(glErr 0x' + StringTools.hex(err, 4) + ')' : '');
			GL.framebufferTexture2D(GL.FRAMEBUFFER, GL.DEPTH_ATTACHMENT, GL.TEXTURE_2D, null, 0);
			try GL.deleteTexture(t) catch (e4:Dynamic) {}
		}
		return false;
	}

	public function bind():Void
	{
		if (fbo == null || bound) return;
		prevFbo = currentBinding();
		GL.bindFramebuffer(GL.FRAMEBUFFER, fbo);
		bound = true;
	}

	public function unbind():Void
	{
		if (!bound) return;
		restoreBinding(prevFbo);
		prevFbo = null;
		bound = false;
	}

	public function hasDepth():Bool
	{
		return depthTex != null;
	}

	public function dispose():Void
	{
		if (bound)
		{
			restoreBinding(prevFbo);
			prevFbo = null;
			bound = false;
		}
		if (depthTex != null)
		{
			try GL.deleteTexture(depthTex) catch (e:Dynamic) {}
			depthTex = null;
		}
		if (fbo != null)
		{
			try GL.deleteFramebuffer(fbo) catch (e:Dynamic) {}
			fbo = null;
		}
		colorTex = null;
		complete = false;
		depthFormat = 'none';
		width = 0;
		height = 0;
	}

	public function statusText():String
	{
		return 'fb=' + (fbo != null) + ' complete=' + complete
			+ ' status=0x' + StringTools.hex(status, 4)
			+ ' depth=' + depthFormat
			+ (triedFormats.length > 0 ? ' tried[' + triedFormats + ']' : '')
			+ ' ' + width + 'x' + height;
	}
}
