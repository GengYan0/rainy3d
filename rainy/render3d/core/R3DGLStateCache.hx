package rainy.render3d.core;

import openfl.display3D.Context3D;
import openfl.display3D.Context3DBlendFactor;
import openfl.display3D.Context3DCompareMode;
import openfl.display3D.Context3DTriangleFace;
import openfl.display3D.Program3D;
import openfl.display3D.textures.TextureBase;

class R3DGLStateCache
{
	public static var context:Context3D;

	public static var culling:Int = -1;
	public static var depthTest:Int = -1;
	public static var depthMask:Int = -1;
	public static var blendSrc:Int = -1;
	public static var blendDst:Int = -1;
	public static var program:Program3D = null;

	static var texAt:Array<Dynamic> = [];
	static var attrAt:Array<Dynamic> = [];
	static var attrFmtAt:Array<Int> = [];
	static var attrCleared:Array<Bool> = [];

	public static var stateChanges:Int = 0;
	public static var redundantSkipped:Int = 0;
	public static var textureBinds:Int = 0;
	public static var programSwitches:Int = 0;
	public static var attrBinds:Int = 0;

	public static function init(ctx:Context3D):Void
	{
		context = ctx;
		invalidate();
	}

	public static function invalidateOpenfl():Void
	{
		if (context != null) context.__invalidateGLCache();
	}

	public static function invalidate():Void
	{
		culling = -1;
		depthTest = -1;
		depthMask = -1;
		blendSrc = -1;
		blendDst = -1;
		program = null;
		texAt = [];
		attrAt = [];
		attrFmtAt = [];
		attrCleared = [];
	}

	public static function beginFrame():Void
	{
		stateChanges = 0;
		redundantSkipped = 0;
		textureBinds = 0;
		programSwitches = 0;
		attrBinds = 0;
	}

	public static function useProgram(p:Program3D):Void
	{
		if (p == null || context == null) return;
		if (program == p)
		{
			redundantSkipped++;
			return;
		}
		@:privateAccess
		{
			context.setProgram(p);
			context.__flushGLProgram();
		}
		program = p;
		programSwitches++;
		stateChanges++;
	}

	public static function setCulling(face:Int):Void
	{
		if (context == null || face == culling) { if (face == culling) redundantSkipped++; return; }
		context.setCulling(cast face);
		culling = face;
		stateChanges++;
	}

	public static function setDepthTest(on:Bool, cmp:Int):Void
	{
		if (context == null) return;
		// The compare function is part of the state. Caching only the on/off bit meant that
		// changing `cmp` while depth test stayed enabled was skipped as redundant and the
		// previous comparison silently kept applying. All current callers pass LESS_EQUAL,
		// so nothing is broken today, but a per-material depth compare would have been.
		var v:Int = (on ? 1 : 0) | (cmp << 8);
		if (v == depthTest)
		{
			redundantSkipped++;
			return;
		}
		context.setDepthTest(on, cast cmp);
		var gl = lime.graphics.opengl.GL;
		if (on) gl.enable(gl.DEPTH_TEST) else gl.disable(gl.DEPTH_TEST);
		@:privateAccess
		{
			context.__contextState.__enableGLDepthTest = on;
		}
		depthTest = v;
		stateChanges++;
	}

	public static function setDepthMask(on:Bool):Void
	{
		var v = on ? 1 : 0;
		if (v == depthMask)
		{
			redundantSkipped++;
			return;
		}
		lime.graphics.opengl.GL.depthMask(on);
		depthMask = v;
		stateChanges++;
	}

	public static function setBlend(src:Int, dst:Int):Void
	{
		if (context == null) return;
		if (src == blendSrc && dst == blendDst)
		{
			redundantSkipped++;
			return;
		}
		context.setBlendFactors(cast src, cast dst);
		blendSrc = src;
		blendDst = dst;
		stateChanges++;
	}

	public static function bindTexture(unit:Int, tex:TextureBase):Void
	{
		if (context == null || tex == null) return;
		if (texAt[unit] == tex)
		{
			redundantSkipped++;
			return;
		}
		context.setTextureAt(unit, tex);
		texAt[unit] = tex;
		textureBinds++;
		stateChanges++;
	}

	public static function bindVertexBuffer(index:Int, buf:Dynamic, offset:Int, format:Int):Void
	{
		if (context == null || buf == null) return;
		if (attrAt[index] == buf && attrFmtAt[index] == format && attrCleared[index] != true)
		{
			redundantSkipped++;
			return;
		}
		context.setVertexBufferAt(index, buf, offset, cast format);
		attrAt[index] = buf;
		attrFmtAt[index] = format;
		attrCleared[index] = false;
		attrBinds++;
		stateChanges++;
	}

	public static function clearVertexBuffer(index:Int):Void
	{
		if (context == null) return;
		if (attrCleared[index] == true)
		{
			redundantSkipped++;
			return;
		}
		context.setVertexBufferAt(index, null);
		attrAt[index] = null;
		attrFmtAt[index] = -1;
		attrCleared[index] = true;
		attrBinds++;
		stateChanges++;
	}

	public static function stats():String
	{
		return "st " + stateChanges + " (skip " + redundantSkipped + ") / tex " + textureBinds
			+ " / prog " + programSwitches + " / attr " + attrBinds;
	}
}
