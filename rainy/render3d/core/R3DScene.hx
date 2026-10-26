package rainy.render3d.core;

import rainy.render3d.host.R3DEnv;

import rainy.render3d.host.R3DLog;
import rainy.render3d.core.R3DPost.R3DPostChain;
import flixel.FlxSprite;
import lime.graphics.opengl.GL;
import openfl.display3D.Context3D;
import openfl.display3D.Context3DBlendFactor;
import openfl.display3D.Context3DCompareMode;
import openfl.display3D.Context3DMipFilter;
import openfl.display3D.Context3DTextureFilter;
import openfl.display3D.Context3DTriangleFace;
import openfl.display3D.Context3DVertexBufferFormat;
import openfl.display3D.Context3DWrapMode;
import openfl.display3D.textures.Texture;
import openfl.display3D.textures.TextureBase;
import openfl.display.BitmapData;
import openfl.geom.Vector3D;
import rainy.render3d.core.R3D.R3DBlend;
import rainy.render3d.core.R3D.R3DFace;
import rainy.render3d.core.R3D.R3DFilter;
import rainy.render3d.core.R3DVendorPath.R3DSortStrategy;
import rainy.render3d.core.R3D.R3DMipFilter;
import rainy.render3d.core.R3D.R3DWrap;
import rainy.render3d.core.R3D.R3DBounds;
import rainy.render3d.core.R3DCamera;
import rainy.render3d.core.R3DMaterial;
import rainy.render3d.core.R3DMesh;
import rainy.render3d.core.R3DModel;
import rainy.render3d.core.R3DShader;
import rainy.render3d.core.R3DInst;
import rainy.render3d.core.R3DShadow;
import rainy.render3d.core.R3DTexture;

typedef R3DDraw = {
	var model:R3DModel;
	var mesh:R3DMesh;
	var material:R3DMaterial;
	var dist:Float;
}

class R3DScene extends FlxSprite
{
	public static var context:Context3D;

	public static var probe:String = "";

	public static var probeGpu:Bool = false;
	public static var msGpuWait:Float = 0;
	public static var gpuWaitSamples:Int = 0;

	public static var noCull:Bool = false;

	public static var glErr:String = "-";

	public static var dbgNoDepthStencil:Bool = false;

	public static var dbgNoRTT:Bool = false;

	public static var skipBlit:Bool = false;

	public static var directDefault:Bool = false;
	public var direct:Bool = R3DScene.directDefault;

	public static var fbStatus:String = "-";

	static var opts:Map<String, String> = null;

	public static function optGet(k:String, d:String):String
	{
		if (opts == null)
		{
			opts = new Map();
			var ini:String = null;
			for (cand in [R3DEnv.dataPath('drawmode.ini'), 'drawmode.ini'])
			{
				try
				{
					if (sys.FileSystem.exists(cand))
					{
						ini = cand;
						break;
					}
				}
				catch (e:Dynamic) { R3DLog.silentFailure("R3DScene.optGet.probe", e); }
			}
			if (ini != null)
			{
				try
				{
					var s = sys.io.File.getContent(ini);
					for (line in s.split("\n"))
					{
						var t = StringTools.trim(line);
						if (t.length == 0 || StringTools.startsWith(t, "#")) continue;
						var i = t.indexOf("=");
						if (i <= 0) continue;
						opts.set(t.substr(0, i), t.substr(i + 1));
					}
				}
				catch (e:Dynamic) { R3DLog.silentFailure("R3DScene.optGet", e); }
			}
		}
		return opts.exists(k) ? opts.get(k) : d;
	}

	public static function optOn(k:String):Bool
	{
		var v = optGet(k, "0");
		return v == "1" || v == "true";
	}

	static function bindOrClear(idx:Int, buf:Dynamic, format:Int):Void
	{
		if (idx < 0) return;
		if (buf == null) R3DGLStateCache.clearVertexBuffer(idx);
		else R3DGLStateCache.bindVertexBuffer(idx, buf, 0, format);
	}

	public static var dbgForceClear:Int = -1;

	function readCenter():String
	{
		try
		{
			var pw:Int = 6;
			var ph:Int = 6;
			var x0:Int = Std.int(sceneW / 2) - 3;
			var y0:Int = Std.int(sceneH / 2) - 3;
			var bytes:haxe.io.Bytes = haxe.io.Bytes.alloc(pw * ph * 4);
			var readFmt:Int = 0x80E1;
			try
			{
				readFmt = cast GL.getParameter(GL.IMPLEMENTATION_COLOR_READ_FORMAT);
			}
			catch (eFmt:Dynamic) { R3DLog.silentFailure("R3DScene.readCenter", eFmt); }
			GL.readPixels(x0, y0, pw, ph, readFmt, GL.UNSIGNED_BYTE, bytes);
			var mx:Int = 0;
			var sum:Int = 0;
			var n:Int = pw * ph * 4;
			var i:Int = 0;
			while (i < n)
			{
				var v:Int = bytes.get(i);
				if (v > mx) mx = v;
				sum += v;
				i += 1;
			}
			return "max=" + mx + " avg=" + Std.int(sum / n);
		}
		catch (e:Dynamic)
		{
			return "readback failed";
		}
	}

	public var views:Array<R3DCamera> = [];
	public var members:Array<R3DModel> = [];

	public var autoBatch(default, set):Bool = true;

	var batches:Array<R3DModel> = [];

	var batchSources:Array<R3DModel> = [];

	var batchSnapshot:Array<Float> = [];

	var batchDirty:Bool = true;

	function set_autoBatch(v:Bool):Bool
	{
		autoBatch = v;
		batchDirty = true;
		return v;
	}
	public var inst:R3DInstSet = new R3DInstSet();
	public var shadow:R3DShadow = null;
	public var target:R3DTexture;

	public static var wantDepthTexture(get, never):Bool;

	static function get_wantDepthTexture():Bool
	{
		return _depthForced || R3DSSAO.enabled;
	}

	static var _depthForced:Bool = false;

	public static function setDepthForced(on:Bool):Void
	{
		_depthForced = on;
	}

	static var _depthLogged:Bool = false;
	static var _depthWarned:Bool = false;
	public var fbComplete:Bool = false;
	public var ownFbo:R3DFramebuffer = null;
	public var depthTextureID:openfl.display3D._internal.GLTexture = null;
	public var depthTextureWidth:Int = 0;
	public var depthTextureHeight:Int = 0;
	public var bgColor:Int = 0xff101014;
	public var culling:Bool = true;
	public var wireframe:Bool = false;
	public var sortDraws:Bool = true;

	public var sceneW:Int = 0;
	public var sceneH:Int = 0;

	public var displayW:Int = 0;
	public var displayH:Int = 0;
	public var drawCalls:Int = 0;
	public var triangles:Int = 0;
	public var culled:Int = 0;
	public var materials:Int = 0;
	public var time:Float = 0;
	public var onBindShader:R3DShader->Void;
	public var onPreDraw:Void->Void;
	public var onPostDraw:Void->Void;
	public var onDiag:String->Void;
	public static var diagOnce:Bool = true;
	public static var msRender:Float = 0;
	public static var msBlit:Float = 0;
	public static var drawCount:Int = 0;
	static function fbDiag():String
	{
		var s = "";
		@:privateAccess
		{
			s = "直连=" + R3DScene.directDefault
				+ " stateRTT=" + (context.__state.renderToTexture != null)
				+ " ctxRTT=" + (context.__contextState.renderToTexture != null)
				+ " curFB=" + (context.__contextState.__currentGLFramebuffer == null ? "无" : "有")
				+ " 后台=" + context.backBufferWidth + "x" + context.backBufferHeight;
		}
		return s;
	}

	var draws:Array<R3DDraw> = [];
	var drawPool:Array<R3DDraw> = [];
	var lastTextureUnit:Int = 0;
	var _directViewport:Array<Dynamic> = null;
	var _disposed:Bool = false;
	var basePixels:BitmapData = null;
	static var samplerValid:Array<Bool> = [];

	static var samplerTex:Array<TextureBase> = [];
	static var samplerWrap:Array<Int> = [];
	static var samplerFilter:Array<Int> = [];
	static var samplerMip:Array<Int> = [];
	static var projTmp:Array<Float> = [0.0, 0.0, 0.0, 0.0];

	public function new(width:Int = 1280, height:Int = 720)
	{
		super(0, 0);
		flipY = true;
		context = openfl.Lib.current.stage.context3D;
		R3DShader.context = context;
		R3DGLStateCache.init(context);
		R3DCaps.init(context);
		setupTarget(width, height);
	}

	public function enablePost(?opts:Dynamic):Int
	{
		if (postChain == null) postChain = new R3DPostChain('scene');
		R3DPostPresets.attach(postChain, opts);
		return postChain.activeCount();
	}

	public function disablePost():Void
	{
		if (postChain == null) return;
		postChain.clear();
		postChain.dispose();
		postChain = null;
	}

	public function setupTarget(width:Int, height:Int):Void
	{
		if (displayW == width && displayH == height && target != null) return;
		displayW = width;
		displayH = height;

		var scale:Float = R3DEnv.superSample;
		if (scale < 0.25 || scale > 4.0 || Math.isNaN(scale)) scale = 1.0;
		sceneW = Std.int(Math.max(2, Math.round(width * scale)));
		sceneH = Std.int(Math.max(2, Math.round(height * scale)));

		if (target != null) target.dispose();
		target = R3DTexture.create(sceneW, sceneH);

		// The resolve target is created lazily by `presentResolved`: when the render size
		// already equals the display size it is never needed, and allocating a second
		// full screen texture per scene for nothing is exactly the kind of waste that
		// shows up as VRAM pressure later.
		if (presentOut != null)
		{
			presentOut.dispose();
			presentOut = null;
		}
		basePixels = target.asBitmapData();
		pixels = basePixels;
		presentPixels = null;
		presentPixelsTex = null;
		_disposed = false;
	}

	public function resizeTarget(width:Int, height:Int):Void
	{
		setupTarget(width, height);
	}

	public function add(m:R3DModel):R3DModel
	{
		if (m == null || members.indexOf(m) >= 0) return m;
		members.push(m);
		batchDirty = true;
		return m;
	}

	public function remove(m:R3DModel):R3DModel
	{
		if (m != null) members.remove(m);
		batchDirty = true;
		return m;
	}

	public function clear():Void
	{
		members = [];
		batchDirty = true;
	}

	public function invalidateBatches():Void
	{
		batchDirty = true;
	}

	public function batchInfo():String
	{
		return R3DBatch.info() + '  active ' + batches.length + ' group(s)';
	}

	public function addCamera(c:R3DCamera):R3DCamera
	{
		if (c != null && views.indexOf(c) < 0) views.push(c);
		return c;
	}

	public function removeCamera(c:R3DCamera):Void
	{
		if (c != null) views.remove(c);
	}

	public static function bindTexture(unit:Int, t:R3DTexture):Void
	{
		var h = (t == null) ? null : t.handle();
		if (context == null || h == null) return;
		var w:Int = cast wrapOf(t.wrapMode);
		var f:Int = cast filterOf(t.filter);
		var m:Int = cast mipOf(t.mipFilter);
		if (samplerValid[unit] && samplerTex[unit] == h && samplerWrap[unit] == w
			&& samplerFilter[unit] == f && samplerMip[unit] == m)
		{
			R3DGLStateCache.redundantSkipped++;
			return;
		}
		context.setTextureAt(unit, h);
		context.setSamplerStateAt(unit, wrapOf(t.wrapMode), filterOf(t.filter), mipOf(t.mipFilter));
		samplerTex[unit] = h;
		samplerWrap[unit] = w;
		samplerFilter[unit] = f;
		samplerMip[unit] = m;
		samplerValid[unit] = true;
		R3DGLStateCache.textureBinds++;
	}

	static function wrapOf(w:R3DWrap):Context3DWrapMode
	{
		return switch (w)
		{
			case R3DWrap.REPEAT: Context3DWrapMode.REPEAT;
			case R3DWrap.MIRROR: Context3DWrapMode.REPEAT;
			default: Context3DWrapMode.CLAMP;
		}
	}

	static function filterOf(f:R3DFilter):Context3DTextureFilter
	{
		return switch (f)
		{
			case R3DFilter.LINEAR: Context3DTextureFilter.LINEAR;
			default: Context3DTextureFilter.NEAREST;
		}
	}

	static function mipOf(m:R3DMipFilter):Context3DMipFilter
	{
		return switch (m)
		{
			case R3DMipFilter.MIPLINEAR: Context3DMipFilter.MIPLINEAR;
			case R3DMipFilter.MIPNEAREST: Context3DMipFilter.MIPNEAREST;
			default: Context3DMipFilter.MIPNONE;
		}
	}

	static function resetSamplers():Void
	{
		// Clear in place: this runs at least once per pass, and a fresh array here is one
		// more allocation on the frame path for no benefit.
		samplerValid.resize(0);
	}

	static var blendTmp:Array<Int> = [0, 0];

	static function applyBlend(mode:R3DBlend):Void
	{
		R3DMaterial.blendFactors(mode, blendTmp);
		R3DGLStateCache.setBlend(blendTmp[0], blendTmp[1]);
	}

	public function renderScene():Bool
	{
		if (context == null || target == null || target.glTexture == null)
		{
			super.draw();
			return true;
		}
		if (autoBatch && (batchDirty || batchSourcesMoved())) rebuildBatches();
		drawCalls = 0;
		R3DScene.drawCount++;
		triangles = 0;
		culled = 0;
		materials = 0;

		if (onPreDraw != null) onPreDraw();
		// Poses have to be uploaded before the draw list is built: `collect` reads mesh
		// bounds, and those follow the deformed vertices.
		for (m in members)
			if (m != null) m.skinMeshes();
		var t0 = haxe.Timer.stamp();
		beginTarget();
		diagPending = null;
		for (cam in views)
			renderCamera(cam);
		endTarget();

		current = this;

		var resolved:R3DTexture = target;
		if (R3DSSAO.enabled && hasDepthTexture() && views.length > 0 && ensurePostTarget())
		{
			if (R3DSSAO.render(context, target.glTexture, depthTextureID, postTarget.glTexture, sceneW, sceneH, views[0]))
				resolved = postTarget;
		}
		// Post effects run at rasterisation size, before the resolve: bloom and vignette
		// are resolution independent, and doing them after the upscale would pay the cost
		// at display size for no visible gain.
		if (postChain != null && postChain.activeCount() > 0)
		{
			var shaded:R3DTexture = postChain.process(resolved);
			if (shaded != null) resolved = shaded;
		}
		if (!direct)
		{
			presentResolved(resolved);
			backToFlixel();
		}
		msRender += (haxe.Timer.stamp() - t0) * 1000.0;
		if (onPostDraw != null) onPostDraw();

		if (R3DCaps.vramSupported && (frameCount & 63) == 0) R3DCaps.pollVram();

		if (frameCount % 60 == 1)
		{
			try
			{
				glErr = "0x" + StringTools.hex(GL.getError(), 4);
			}
			catch (eG:Dynamic)
			{
				glErr = "err";
			}
		}
		return false;
	}

	public function blitScene():Void
	{
		var t1 = haxe.Timer.stamp();
		if (!skipBlit && !direct) super.draw();
		msBlit += (haxe.Timer.stamp() - t1) * 1000.0;
		if (diagPending != null && onDiag != null)
		{
			onDiag(diagPending);
			diagPending = null;
			diagOnce = false;
		}
	}

	override public function draw():Void
	{
		if (!renderScene()) blitScene();
	}

	var frameCount:Int = 0;
	var diagPending:String = null;
	var savedProgram:Dynamic = null;
	var savedIndexBuffer:Dynamic = null;

	function diagString(cam:R3DCamera, sh:R3DShader):String
	{
		if (sh == null) return "诊断: 无着色器";
		var gl:Dynamic = R3DShader.glOf(context);
		var gp:Dynamic = sh.glProgram();
		var sb = new StringBuf();
		try
		{
			sb.add("活动 uniform=" + gl.getProgramParameter(gp, gl.ACTIVE_UNIFORMS));
			for (nm in ["uProj", "uView", "uModel", "uTime", "iResolution", "uTint", "uAlbedo"])
				sb.add(" " + nm + "=" + sh.location(nm));
			sb.add(" | 属性 pos=" + sh.attrPosition + " uv=" + sh.attrTexCoord + " nrm=" + sh.attrNormal + " col=" + sh.attrColor);
			var l = sh.location("uTime");
			if (l >= 0)
			{
				var back:Dynamic = gl.getUniformf(gp, cast l);
				sb.add(" | uTime 回读=" + back + "(应=" + time + ")");
			}
			sb.add(" | 视口=" + gl.getParameter(gl.VIEWPORT));
			sb.add(" | FRONT_FACE=" + gl.getParameter(gl.FRONT_FACE));
			sb.add(" | CULL=" + gl.getParameter(gl.CULL_FACE));
			sb.add(" | DEPTH_TEST=" + gl.getParameter(gl.DEPTH_TEST));
			sb.add(" | proj[0..3]=" + cam.proj[0] + "," + cam.proj[1] + "," + cam.proj[2] + "," + cam.proj[3]);
			sb.add(" | 提交=" + drawCalls + " 三角=" + triangles + " 剔除=" + culled);
			sb.add(" | fbBinding=" + fbDiag());
			sb.add(" | 相机=" + flixel.FlxG.cameras.list.length + " bgColor=0x" + StringTools.hex(flixel.FlxG.cameras.bgColor, 8));
			sb.add(" | " + probe);
			sb.add(" | glGetError=" + gl.getError());
		}
		catch (e:Dynamic)
		{
			sb.add(" 诊断异常 " + e);
		}
		return sb.toString();
	}

	public function dumpTarget(path:String):Void
	{
		try
		{
			var w = sceneW;
			var h = sceneH;
			var bytes = haxe.io.Bytes.alloc(w * h * 4);
			var fmt:Int = 0x80E1;
			try fmt = cast GL.getParameter(GL.IMPLEMENTATION_COLOR_READ_FORMAT) catch (eF:Dynamic) { R3DLog.silentFailure("R3DScene.dumpTarget", eF); }
			GL.readPixels(0, 0, w, h, fmt, GL.UNSIGNED_BYTE, bytes);
			sys.io.File.saveBytes(path, bytes);
		}
		catch (e:Dynamic) { R3DLog.silentFailure("R3DScene.dumpTarget", e); }
	}

	public function grabTarget(path:String):Int
	{
		if (target == null || sceneW < 8 || sceneH < 8) return -1;
		rebindTarget();
		try
		{
			dumpTarget(path);
		}
		catch (e:Dynamic) { R3DLog.silentFailure("R3DScene.grabTarget", e); }
		backToFlixel();
		return sceneW * sceneH * 4;
	}

	function beginTarget():Void
	{
		if (probeGpu && (frameCount & 31) == 0)
		{
			// Nothing extra is submitted here, so this cannot create work: it only waits
			// for work already in flight. The wait is the GPU backlog.
			var g0:Float = haxe.Timer.stamp();
			try
			{
				GL.finish();
				msGpuWait += (haxe.Timer.stamp() - g0) * 1000.0;
				gpuWaitSamples++;
			}
			catch (eGpu:Dynamic) { R3DLog.silentFailure("R3DScene.gpuProbe", eGpu); }
		}
		frameCount++;
		R3DGLStateCache.beginFrame();
		R3DGLStateCache.invalidate();
		R3DShader.invalidate();
		savedProgram = @:privateAccess context.__state.program;
		R3DEnv.probeBegin(frameCount);
		try
		{
			savedIndexBuffer = GL.getParameter(GL.ELEMENT_ARRAY_BUFFER_BINDING);
		}
		catch (eIB:Dynamic)
		{
			savedIndexBuffer = null;
		}
		resetSamplers();
		if (optOn("magenta")) bgColor = 0xFFFF00FF;
		var noDS = dbgNoDepthStencil || optOn("nods");
		if (wantDepthTexture && direct)
		{
			direct = false;
			if (!_depthLogged)
			{
				_depthLogged = true;
				R3DLog.info('r3d', 'depth texture needs RTT, direct mode disabled');
			}
		}
		if (direct)
		{
			@:privateAccess
			{
				context.setRenderToBackBuffer();
				context.__flushGLFramebuffer();
			}
			try { _directViewport = GL.getParameter(GL.VIEWPORT); } catch (e:Dynamic) { _directViewport = null; }
			GL.viewport(0, 0, displayW > 0 ? displayW : context.backBufferWidth, displayH > 0 ? displayH : context.backBufferHeight);
			GL.enable(GL.DEPTH_TEST);
			GL.enable(GL.STENCIL_TEST);
			R3DGLStateCache.invalidateOpenfl();
		}
		else
		{
			if (!dbgNoRTT)
			{
				@:privateAccess
				{
					openfl.display3D.textures.TextureBase.depthTextureEnabled = false;
					context.__state.renderToTexture = target.glTexture;
					context.__state.renderToTextureDepthStencil = !noDS;
					context.__flushGLFramebuffer();
				}
				if (wantDepthTexture)
				{
					// `ownFbo` is the only source of a depth texture; the context has no depth attachment here.
					if (ensureOwnFbo())
					{
						ownFbo.bind();
					}
					else if (!_depthWarned)
					{
						_depthWarned = true;
						R3DLog.warn('r3d', 'no depth texture: self FBO failed ('
							+ (ownFbo == null ? 'null' : ownFbo.statusText()) + '); SSAO/SSR render without depth');
					}
				}
			}
			R3DGLStateCache.invalidateOpenfl();
			GL.viewport(0, 0, sceneW, sceneH);
		}
		if (noCull || optOn("nocull"))
		{
			try
			{
				GL.disable(GL.CULL_FACE);
			}
			catch (eC:Dynamic) { R3DLog.silentFailure("R3DScene.beginTarget", eC); }
		}
		R3DGLStateCache.setDepthTest(true, R3DDepth.compareMode());
		R3DGLStateCache.setCulling(cast Context3DTriangleFace.BACK);
		R3DGLStateCache.setBlend(cast Context3DBlendFactor.SOURCE_ALPHA, cast Context3DBlendFactor.ONE_MINUS_SOURCE_ALPHA);
		R3DGLStateCache.setDepthMask(true);
		if (frameCount % 60 == 1)
		{
			try
			{
				fbStatus = StringTools.hex(GL.checkFramebufferStatus(GL.FRAMEBUFFER), 4);
			}
			catch (eF:Dynamic)
			{
				fbStatus = "n/a";
			}
		}
		var cc:Int = dbgForceClear >= 0 ? dbgForceClear : bgColor;
		GL.clearColor(((cc >> 16) & 0xFF) / 255.0, ((cc >> 8) & 0xFF) / 255.0, (cc & 0xFF) / 255.0, 1.0);
		GL.clearDepthf(R3DDepth.clearValue);
		GL.clearStencil(0);
		GL.clear(GL.COLOR_BUFFER_BIT | GL.DEPTH_BUFFER_BIT | GL.STENCIL_BUFFER_BIT);
	}

	function presentResolved(src:R3DTexture):Void
	{
		if (src == null) return;
		if (present == null) present = new R3DPresent();
		if (aa == null) aa = new R3DAA();

		var needsResolve:Bool = src.width != displayW || src.height != displayH;
		if (needsResolve && presentOut == null)
			presentOut = R3DTexture.create(displayW, displayH);

		var shown:R3DTexture = present.apply(src, displayW, displayH, presentOut);
		if (shown == null) return;
		var aaShown:R3DTexture = aa.apply(shown, displayW, displayH);
		if (aaShown != null) shown = aaShown;
		publish(shown);
	}

	function publish(t:R3DTexture):Void
	{
		if (t == null) return;
		if (presentPixelsTex != t || presentPixels == null)
		{
			presentPixelsTex = t;
			presentPixels = t.asBitmapData();
		}
		if (presentPixels != null && pixels != presentPixels) pixels = presentPixels;
	}

	var postTarget:R3DTexture = null;
	var postPixels:openfl.display.BitmapData = null;

	public var postChain:R3DPostChain = null;

	public static var current:R3DScene = null;

	var present:R3DPresent = null;
	var aa:R3DAA = null;

	var presentOut:R3DTexture = null;
	var presentPixels:openfl.display.BitmapData = null;
	var presentPixelsTex:R3DTexture = null;

	function ensurePostTarget():Bool
	{
		if (postTarget != null && postPixels != null && postTarget.width == sceneW && postTarget.height == sceneH)
			return true;
		postTarget = R3DTexture.create(sceneW, sceneH);
		postPixels = postTarget == null ? null : postTarget.asBitmapData();
		if (postTarget == null || postPixels == null)
		{
			R3DLog.warn('r3d', 'SSAO output target creation failed');
			return false;
		}
		return true;
	}

	public function setSSAO(on:Bool):Bool
	{
		// `wantDepthTexture` derives from `R3DSSAO.enabled`, so there is nothing to assign
		// here. Setting it explicitly was what pinned the flag on forever.
		R3DSSAO.enabled = on;
		return R3DSSAO.enabled;
	}

	public function hasDepthTexture():Bool
	{
		return depthTextureID != null;
	}

	function ensureOwnFbo():Bool
	{
		if (target == null || target.glTexture == null) return false;
		if (ownFbo != null && ownFbo.complete && ownFbo.width == sceneW && ownFbo.height == sceneH)
			return true;
		if (ownFbo == null) ownFbo = new R3DFramebuffer();
		var ct:Dynamic = @:privateAccess target.glTexture.__textureID;
		var ok:Bool = ownFbo.attach(cast ct, sceneW, sceneH);
		R3DLog.info('r3d', 'self FBO: ' + ownFbo.statusText());
		if (ok)
		{
			depthTextureID = ownFbo.depthTex;
			depthTextureWidth = sceneW;
			depthTextureHeight = sceneH;
			fbComplete = true;
		}
		else
		{
			depthTextureID = null;
			fbComplete = false;
		}
		return ok;
	}

	function endTarget():Void
	{
		if (ownFbo != null && ownFbo.bound) ownFbo.unbind();
		if (frameCount % 60 == 1)
		{
			probe = "中心 " + readCenter() + " | 相机=" + views.length + " 成员=" + members.length
				+ " 可见=" + (visible ? "1" : "0") + " 尺寸=" + sceneW + "x" + sceneH
				+ " | pixels=" + (pixels == null ? "null" : pixels.width + "x" + pixels.height);
		}
		for (i in 0...5)
			context.setVertexBufferAt(i, null);
		R3DGLStateCache.invalidate();
		R3DShader.invalidate();
		if (!direct && !dbgNoRTT)
		{
			@:privateAccess
			{
				context.__state.renderToTexture = null;
				context.__state.renderToTextureDepthStencil = false;
				context.__flushGLFramebuffer();
			}
		}
		backToFlixel();
	}

	function backToFlixel():Void
	{
		var ctx = context;
		if (ctx == null) return;
		try
		{
			ctx.setRenderToBackBuffer();
			@:privateAccess ctx.__flushGLFramebuffer();
			ctx.setDepthTest(false, cast Context3DCompareMode.ALWAYS);
			ctx.setCulling(cast Context3DTriangleFace.NONE);
			ctx.setBlendFactors(cast Context3DBlendFactor.SOURCE_ALPHA, cast Context3DBlendFactor.ONE_MINUS_SOURCE_ALPHA);
			ctx.setStencilActions();
			ctx.setStencilReferenceValue(0);
			ctx.setScissorRectangle(null);
			ctx.setColorMask(true, true, true, true);
			@:privateAccess
			{
				ctx.__state.program = savedProgram;
				ctx.__contextState.program = null;
				ctx.__flushGL();
			}
		}
		catch (e:Dynamic) { R3DLog.silentFailure("R3DScene.backToFlixel", e); }
		try
		{
			GL.disable(GL.DEPTH_TEST);
			GL.disable(GL.STENCIL_TEST);
			GL.disable(GL.SCISSOR_TEST);
			GL.depthMask(false);
			if (savedIndexBuffer != null) GL.bindBuffer(GL.ELEMENT_ARRAY_BUFFER, cast savedIndexBuffer);
			GL.enable(GL.BLEND);
			GL.blendFunc(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA);
			if (direct && _directViewport != null)
			{
				try { GL.viewport(_directViewport[0], _directViewport[1], _directViewport[2], _directViewport[3]); } catch (e:Dynamic) { R3DLog.silentFailure("R3DScene.backToFlixel", e); }
				_directViewport = null;
			}
			else
			{
				GL.viewport(0, 0, ctx.backBufferWidth, ctx.backBufferHeight);
			}
			@:privateAccess
			{
				ctx.__contextState.__enableGLDepthTest = false;
				ctx.__contextState.depthMask = false;
			}
			R3DGLStateCache.depthTest = 0;
			R3DGLStateCache.depthMask = 0;
		}
		catch (e2:Dynamic) { R3DLog.silentFailure("R3DScene.backToFlixel", e2); }
		R3DGLStateCache.invalidateOpenfl();
	}

	function drawMesh(mesh:R3DMesh):Void
	{
		@:privateAccess
		{
			context.__flushGL();
			GL.bindBuffer(GL.ELEMENT_ARRAY_BUFFER, mesh.indexBuffer.__id);
			GL.drawElements(GL.TRIANGLES, mesh.indexCount, GL.UNSIGNED_SHORT, 0);
		}
	}

	static function byDrawOrder(a:R3DDraw, b:R3DDraw):Int
	{
		// Opaque before transparent, always: depth writes have to finish before anything
		// that relies on blending, and no vendor strategy changes that.
		var oa = (a.material == null) || a.material.opaque;
		var ob = (b.material == null) || b.material.opaque;
		if (oa != ob) return oa ? -1 : 1;

		if (oa && R3DVendorPath.sortStrategy == R3DSortStrategy.PROGRAM)
		{
			// Program first: on drivers where a program switch revalidates uniforms, this
			// is worth more than material grouping.
			var sa = shaderIdOf(a);
			var sb = shaderIdOf(b);
			if (sa != sb) return sa < sb ? -1 : 1;
		}

		var pa = a.material == null ? 0 : a.material.priority;
		var pb = b.material == null ? 0 : b.material.priority;
		if (pa != pb) return pa < pb ? -1 : 1;
		return a.dist < b.dist ? 1 : -1;
	}

	static function shaderIdOf(d:R3DDraw):Int
	{
		if (d.material == null || d.material.shader == null) return -1;
		return d.material.shader.uid;
	}

	inline function pushDraw(model:R3DModel, mesh:R3DMesh, material:R3DMaterial, dist:Float):Void
	{
		var i:Int = draws.length;
		var d:R3DDraw = drawPool[i];
		if (d == null)
		{
			d = {model: null, mesh: null, material: null, dist: 0.0};
			drawPool[i] = d;
		}
		d.model = model;
		d.mesh = mesh;
		d.material = material;
		d.dist = dist;
		draws.push(d);
	}

	public function rebuildBatches():Void
	{
		for (m in batches)
		{
			if (m == null) continue;
			for (mesh in m.meshes)
				if (mesh != null) mesh.dispose();
			m.meshes = [];
			m.dispose();
		}
		batches.resize(0);
		for (m in batchSources)
			if (m != null) m.visible = true;
		batchSources.resize(0);
		batchSnapshot.resize(0);
		batchDirty = false;

		if (!autoBatch) return;

		var candidates:Array<R3DModel> = [];
		for (m in members)
		{
			if (m == null || !m.visible || m.parent != null) continue;
			if (m.lodLevels != null && m.lodLevels.length > 0) continue;
			if (m.meshes == null || m.meshes.length != 1) continue;
			var mesh = m.meshes[0];
			if (mesh == null || mesh.indexBuffer == null || mesh.material == null) continue;
			if (!mesh.material.opaque) continue;
			// A skinned mesh rewrites its vertex buffer every posed frame, so a merged copy
			// would freeze at the bind pose.
			if (mesh.skeleton != null) continue;
			candidates.push(m);
		}
		if (candidates.length < 2) return;

		for (b in R3DBatch.bake(candidates))
			batches.push(b);
		for (m in candidates)
			batchSources.push(m);
		captureBatchSnapshot();
	}

	function batchSourcesMoved():Bool
	{
		var n:Int = batchSources.length;
		if (n == 0) return false;
		if (batchSnapshot.length != n * 3) return true;
		var i:Int = 0;
		for (m in batchSources)
		{
			if (m != null && (m.x != batchSnapshot[i] || m.y != batchSnapshot[i + 1] || m.z != batchSnapshot[i + 2])) return true;
			i += 3;
		}
		return false;
	}

	function captureBatchSnapshot():Void
	{
		batchSnapshot.resize(batchSources.length * 3);
		var i:Int = 0;
		for (m in batchSources)
		{
			if (m != null)
			{
				batchSnapshot[i] = m.x;
				batchSnapshot[i + 1] = m.y;
				batchSnapshot[i + 2] = m.z;
			}
			i += 3;
		}
	}

	function collect(cam:R3DCamera):Void
	{
		draws.resize(0);
		for (m in members)
		{
			if (m == null || !m.visible) continue;
			var b = m.worldBounds();
			if (!b.valid()) continue;
			if (culling && !cam.seesBounds(b))
			{
				culled++;
				continue;
			}
			var px = cam.x < b.minX ? b.minX : (cam.x > b.maxX ? b.maxX : cam.x);
			var py = cam.y < b.minY ? b.minY : (cam.y > b.maxY ? b.maxY : cam.y);
			var pz = cam.z < b.minZ ? b.minZ : (cam.z > b.maxZ ? b.maxZ : cam.z);
			var dx = px - cam.x, dy = py - cam.y, dz = pz - cam.z;
			var d = Math.sqrt(dx * dx + dy * dy + dz * dz);
			// The screen-space ladder, when present, replaces the distance rule entirely:
			// mixing the two would let a model qualify for a level and its legacy
			// fallback at the same time.
			if (m.lodLevels != null && m.lodLevels.length > 0)
			{
				var lodMesh = R3DLod.pickMesh(m, cam, d, sceneH);
				if (lodMesh == null || lodMesh.indexBuffer == null)
				{
					culled++;
					continue;
				}
				pushDraw(m, lodMesh, lodMesh.material, d);
				continue;
			}
			if (m.lodMesh != null && m.lodDist > 0 && d > m.lodDist)
			{
				pushDraw(m, m.lodMesh, m.lodMesh.material, d);
				continue;
			}
			for (mesh in m.meshes)
			{
				if (mesh == null || mesh.indexBuffer == null) continue;
				pushDraw(m, mesh, mesh.material, d);
			}
		}
		// Batches are baked in world space at the origin, so they need no transform work
		// beyond the identity matrix they already carry.
		for (m in batches)
		{
			if (m == null || !m.visible) continue;
			var bb = m.worldBounds();
			if (!bb.valid()) continue;
			if (culling && !cam.seesBounds(bb))
			{
				culled++;
				continue;
			}
			var bm = m.meshes.length > 0 ? m.meshes[0] : null;
			if (bm == null || bm.indexBuffer == null) continue;
			pushDraw(m, bm, bm.material, 0.0);
		}
		if (sortDraws) draws.sort(byDrawOrder);
	}

	public function drawOrderInfo():String
	{
		var s = Std.string(draws.length) + ":";
		for (i in 0...draws.length)
		{
			if (i >= 12)
			{
				s += "...";
				break;
			}
			var d = draws[i];
			var nm = (d.model == null || d.model.name == null || d.model.name.length == 0) ? "未命名" : d.model.name;
			var pr = (d.material == null) ? "?" : "" + d.material.priority;
			s += nm + "(d" + (Math.round(d.dist * 100) / 100) + " p" + pr + ") ";
		}
		return s;
	}

	public function rebindTarget():Void
	{
		if (context == null || target == null || target.glTexture == null) return;
		@:privateAccess
		{
			context.__state.renderToTexture = target.glTexture;
			context.__state.renderToTextureDepthStencil = !dbgNoDepthStencil;
			context.__flushGLFramebuffer();
		}
		GL.viewport(0, 0, sceneW, sceneH);
		R3DGLStateCache.invalidateOpenfl();
		R3DGLStateCache.invalidate();
		R3DShader.invalidate();
		// The flush above lets openfl reconsider its own texture bindings, so the sampler
		// dedupe cache can no longer be trusted.
		resetSamplers();
		R3DGLStateCache.setDepthTest(true, R3DDepth.compareMode());
		R3DGLStateCache.setCulling(cast Context3DTriangleFace.BACK);
		R3DGLStateCache.setBlend(cast Context3DBlendFactor.SOURCE_ALPHA, cast Context3DBlendFactor.ONE_MINUS_SOURCE_ALPHA);
		R3DGLStateCache.setDepthMask(true);
	}

	function bindFrameUniforms(sh:R3DShader, cam:R3DCamera, w:Float, h:Float, t:Float):Void
	{
		sh.setMat4("uProj", cam.proj);
		sh.setMat4("uView", cam.view);
		sh.setMat4("uInvView", cam.invView);
		sh.setVec2("iResolution", w, h);
		sh.setFloat("uTime", t);
	}

	function renderCamera(cam:R3DCamera):Void
	{
		if (cam == null || !cam.active) return;
		cam.aspect = sceneW / sceneH;
		cam.update();
		collect(cam);
		if (draws.length == 0) return;
		R3DShader.invalidate();
		R3DGLStateCache.program = null;

		if (R3DSkybox.enabled && R3DSkybox.hasCubemap())
		{
			try
				R3DSkybox.render(cam, cam.proj, cam.view, cam.viewRotationOnly())
			catch (eSky:Dynamic)
				R3DLog.capture(eSky, 'R3DScene.skybox', 'render');
		}

		var currentMat:R3DMaterial = null;
		var lastShader:R3DShader = null;
		for (d in draws)
		{
			var mat = d.material;
			var sh = mat.shader;
			if (sh == null) continue;
			if (mat != currentMat)
			{
				lastShader = sh;
				var noC: Bool = noCull || optOn("nocull");
				R3DGLStateCache.setCulling(noC ? cast Context3DTriangleFace.NONE
					: cast (mat.culling == R3DFace.BOTH ? Context3DTriangleFace.NONE
						: (mat.culling == R3DFace.FRONT ? Context3DTriangleFace.FRONT : Context3DTriangleFace.BACK)));
				R3DGLStateCache.setDepthTest(mat.depthTest, R3DDepth.compareMode());
				R3DGLStateCache.setDepthMask(mat.depthWrite);
				applyBlend(mat.blendMode);
				sh.bind();
				bindFrameUniforms(sh, cam, sceneW, sceneH, time);
				if (onBindShader != null) onBindShader(sh);
				if (shadow != null) shadow.uploadTo(sh, shadow.rig);
				mat.bind();
				currentMat = mat;
				materials++;
			}
			else
			{
				if (sh != lastShader)
				{
					sh.bind();
					bindFrameUniforms(sh, cam, sceneW, sceneH, time);
					lastShader = sh;
				}
			}
			if (sh.attrPosition < 0) continue;
			// A mesh that was disposed (or never got `setArrays`) still sits in the collected
			// draw list, and every branch below dereferences `indexBuffer.__id` directly.
			if (d.mesh.indexBuffer == null) continue;
			R3DGLStateCache.bindVertexBuffer(sh.attrPosition, d.mesh.vertexBuffer, 0, cast Context3DVertexBufferFormat.FLOAT_3);
			bindOrClear(sh.attrTexCoord, d.mesh.uvBuffer, cast Context3DVertexBufferFormat.FLOAT_2);
			bindOrClear(sh.attrNormal, d.mesh.normalBuffer, cast Context3DVertexBufferFormat.FLOAT_3);
			bindOrClear(sh.attrColor, d.mesh.colorBuffer, cast Context3DVertexBufferFormat.FLOAT_4);
			d.model.updateWorld();
			sh.setMat4("uModel", d.model.world);
			if (d.mesh.primitive == 1)
			{
				context.drawTriangles(d.mesh.indexBuffer, 0, 0);
				@:privateAccess GL.bindBuffer(GL.ELEMENT_ARRAY_BUFFER, d.mesh.indexBuffer.__id);
				GL.drawElements(GL.LINES, d.mesh.indexCount, GL.UNSIGNED_SHORT, 0);
			}
			else if (wireframe)
			{
				var wi = d.mesh.wireIndices();
				if (wi == null)
					context.drawTriangles(d.mesh.indexBuffer, 0, d.mesh.triangles);
				else
				{
					context.drawTriangles(d.mesh.indexBuffer, 0, 0);
					@:privateAccess GL.bindBuffer(GL.ELEMENT_ARRAY_BUFFER, wi.__id);
					GL.drawElements(GL.LINES, d.mesh.wireCount, GL.UNSIGNED_SHORT, 0);
				}
			}
			else
			{
				drawMesh(d.mesh);
			}
			drawCalls++;
			triangles += d.mesh.triangles;
		}
		renderBatches(cam);

		if (R3DEnv.probeEnabled())
		{
			try
				R3DEnv.probeGrab(sceneW, sceneH)
			catch (eP:Dynamic)
				R3DLog.capture(eP, 'R3DScene.frameProbe', 'grab');
		}
		currentMat = null;
		if (diagOnce && diagPending == null) diagPending = diagString(cam, lastShader);
	}

	static var instIdent:Array<Float> = [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0];

	function renderBatches(cam:R3DCamera):Void
	{
		if (inst == null || inst.batches.length == 0) return;
		var currentMat:R3DMaterial = null;
		for (b in inst.batches)
		{
			if (b == null || !b.visible || b.count <= 0) continue;
			var m = b.mesh;
			if (m == null || m.indexBuffer == null) continue;
			var mat = b.material;
			if (mat == null || mat.shader == null) continue;
			if (culling && b.bounds.valid() && !cam.seesBounds(b.bounds))
			{
				culled++;
				continue;
			}
			b.upload();
			if (mat != currentMat)
			{
				var noC: Bool = noCull || optOn("nocull");
				R3DGLStateCache.setCulling(noC ? cast Context3DTriangleFace.NONE
					: cast (mat.culling == R3DFace.BOTH ? Context3DTriangleFace.NONE
						: (mat.culling == R3DFace.FRONT ? Context3DTriangleFace.FRONT : Context3DTriangleFace.BACK)));
				R3DGLStateCache.setDepthTest(mat.depthTest, R3DDepth.compareMode());
				R3DGLStateCache.setDepthMask(mat.depthWrite);
				applyBlend(mat.blendMode);
				shBind(mat.shader, cam);
				mat.bind();
				currentMat = mat;
			}
			var sh = mat.shader;
			R3DGLStateCache.bindVertexBuffer(sh.attrPosition, m.vertexBuffer, 0, cast Context3DVertexBufferFormat.FLOAT_3);
			bindOrClear(sh.attrTexCoord, m.uvBuffer, cast Context3DVertexBufferFormat.FLOAT_2);
			bindOrClear(sh.attrNormal, m.normalBuffer, cast Context3DVertexBufferFormat.FLOAT_3);
			bindOrClear(sh.attrColor, m.colorBuffer, cast Context3DVertexBufferFormat.FLOAT_4);
			if (!b.bind(sh)) continue;
			@:privateAccess
			{
				context.__flushGL();
				GL.bindBuffer(GL.ELEMENT_ARRAY_BUFFER, m.indexBuffer.__id);
				GL.drawElementsInstanced(GL.TRIANGLES, m.indexCount, GL.UNSIGNED_SHORT, 0, b.count);
			}
			b.unbind(sh);
			drawCalls++;
			triangles += m.triangles * b.count;
		}
	}

	function shBind(sh:R3DShader, cam:R3DCamera):Void
	{
		sh.bind();
		sh.setMat4("uProj", cam.proj);
		sh.setMat4("uView", cam.view);
		sh.setMat4("uInvView", cam.invView);
		sh.setVec2("iResolution", sceneW, sceneH);
		sh.setFloat("uTime", time);
		sh.setMat4("uModel", instIdent);
		if (onBindShader != null) onBindShader(sh);
	}

	override public function destroy():Void
	{
		dispose();
		super.destroy();
	}

	public function dispose():Void
	{
		if (_disposed) return;
		_disposed = true;
		if (target != null)
		{
			target.dispose();
			target = null;
		}
		if (presentOut != null)
		{
			presentOut.dispose();
			presentOut = null;
		}
		if (present != null)
		{
			present.dispose();
			present = null;
		}
		if (aa != null)
		{
			aa.dispose();
			aa = null;
		}
		if (postChain != null)
		{
			postChain.dispose();
			postChain = null;
		}
		if (current == this) current = null;
		if (inst != null) inst.dispose();
		if (shadow != null) shadow.dispose();
		for (m in batches)
		{
			if (m == null) continue;
			for (mesh in m.meshes)
				if (mesh != null) mesh.dispose();
			m.dispose();
		}
		batches.resize(0);
		batchSources.resize(0);
		members = [];
		views = [];
		draws = [];
	}
}
