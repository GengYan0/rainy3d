package rainy.render3d.core;

import lime.graphics.opengl.GL;
import rainy.render3d.core.R3D.R3DBounds;
import rainy.render3d.core.R3D.R3DFilter;
import rainy.render3d.core.R3D.R3DMipFilter;
import rainy.render3d.core.R3D.R3DWrap;
import rainy.render3d.core.R3DMaterial;
import rainy.render3d.core.R3DMesh;
import rainy.render3d.core.R3DModel;
import rainy.render3d.core.R3DTexture;
import rainy.render3d.core.R3DLight.R3DLight;
import rainy.render3d.core.R3DLight.R3DLightRig;
import rainy.render3d.core.R3DLight.R3DLightType;
import rainy.render3d.core.R3DShader;

class R3DShadow
{
	public static var enabled:Bool = false;
	public static var size:Int = 1024;
	public static var bias:Float = 0.0022;
	public static var strength:Float = 0.72;
	public static var pullback:Float = 12.0;
	public static var pad:Float = 0.6;
	public static var orthoFov:Float = 1.05;
	public static var cullFront:Bool = true;
	public static var layerFilter:Int = -1;
	public static var fadeStart:Float = 0.0;
	public static var fadeEnd:Float = 0.0;

	public var light:R3DLight;
	public var rig:R3DLightRig = null;
	public var tex:R3DTexture = null;
	public var vp:Array<Float> = [];
	public var drawn:Int = 0;
	public var lastError:String = "";

	var shader:R3DShader = null;
	var ident:Array<Float> = [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0];
	var b:R3DBounds = new R3DBounds();
	var scratch:Array<Float> = [0.0, 0.0, 0.0];

	public function new(?l:R3DLight)
	{
		light = l;
		gl();
	}

	function gl():R3DTexture
	{
		if (tex != null && tex.width == size) return tex;
		if (tex != null)
		{
			tex.dispose();
			tex = null;
		}
		tex = R3DTexture.create(size, size);
		if (tex != null)
		{
			tex.wrapMode = R3DWrap.CLAMP;
			tex.filter = R3DFilter.NEAREST;
			tex.mipFilter = R3DMipFilter.MIPNONE;
		}
		return tex;
	}

	public function shaderOf():R3DShader
	{
		if (shader == null || shader.failed)
		{
			shader = R3DShaders.shadowShader();
			if (shader != null && shader.failed) lastError = "阴影着色器失败";
		}
		return shader;
	}

	public function resize(n:Int):Void
	{
		size = n < 128 ? 128 : (n > 4096 ? 4096 : n);
		gl();
	}

	public function boundsOf(models:Array<R3DModel>):R3DBounds
	{
		b.empty();
		if (models == null) return b;
		for (m in models)
		{
			if (m == null || !m.visible) continue;
			var w = m.worldBounds();
			if (!w.valid()) continue;
			for (c in 0...8)
			{
				R3DMat4.transformPoint(m.world, (c & 1) != 0 ? w.maxX : w.minX,
					(c & 2) != 0 ? w.maxY : w.minY, (c & 4) != 0 ? w.maxZ : w.minZ, scratch);
				b.addPoint(scratch[0], scratch[1], scratch[2]);
			}
		}
		return b;
	}

	public function updateVP(models:Array<R3DModel>):Bool
	{
		if (light == null) return false;
		var bb = boundsOf(models);
		if (!bb.valid()) return false;
		var cx = (bb.minX + bb.maxX) * 0.5;
		var cy = (bb.minY + bb.maxY) * 0.5;
		var cz = (bb.minZ + bb.maxZ) * 0.5;
		var eyeX:Float;
		var eyeY:Float;
		var eyeZ:Float;
		if (light.type == R3DLightType.DIRECTIONAL)
		{
			eyeX = cx - light.dirX * pullback;
			eyeY = cy - light.dirY * pullback;
			eyeZ = cz - light.dirZ * pullback;
		}
		else
		{
			eyeX = light.x;
			eyeY = light.y;
			eyeZ = light.z;
		}
		var view = R3DMat4.lookAt(eyeX, eyeY, eyeZ, cx, cy, cz, 0.0, 1.0, 0.0);
		var proj:Array<Float>;
		if (light.type == R3DLightType.DIRECTIONAL)
		{
			var rx = Math.max(Math.abs(bb.maxX - cx), Math.abs(bb.minX - cx)) + pad;
			var ry = Math.max(Math.abs(bb.maxY - cy), Math.abs(bb.minY - cy)) + pad;
			var rz = Math.max(Math.abs(bb.maxZ - cz), Math.abs(bb.minZ - cz)) + pad;
			var ext = Math.sqrt(rx * rx + ry * ry + rz * rz) * 1.15;
			var n = -ext;
			var f = pullback + ext;
			proj = R3DMat4.ortho(n, ext, n, ext, n, f);
		}
		else
		{
			var dx = cx - eyeX;
			var dy = cy - eyeY;
			var dz = cz - eyeZ;
			var dist = Math.sqrt(dx * dx + dy * dy + dz * dz);
			var ext = Math.sqrt((bb.maxX - cx) * (bb.maxX - cx) + (bb.maxY - cy) * (bb.maxY - cy) + (bb.maxZ - cz) * (bb.maxZ - cz)) + pad;
			var near = Math.max(dist - ext, 0.05);
			var far = dist + ext + pullback;
			proj = R3DMat4.perspectiveHalf(Math.max(orthoFov, 0.2), 1.0, near, far);
		}
		vp = R3DMat4.multiplication(proj, view);
		return true;
	}

	public function render(scene:R3DScene, models:Array<R3DModel>):Void
	{
		drawn = 0;
		if (!enabled || light == null || light.castShadow == false) return;
		var t = gl();
		if (t == null || t.glTexture == null) return;
		var sh = shaderOf();
		if (sh == null || sh.failed) return;
		if (!updateVP(models)) return;
		var ctx = R3DScene.context;
		if (ctx == null) return;
		R3DGLStateCache.invalidate();
		R3DShader.invalidate();
		@:privateAccess
		{
			ctx.__state.renderToTexture = t.glTexture;
			ctx.__state.renderToTextureDepthStencil = true;
			ctx.__flushGLFramebuffer();
		}
		GL.viewport(0, 0, size, size);
		R3DGLStateCache.invalidateOpenfl();
		R3DGLStateCache.setDepthTest(true, R3DDepth.compareMode());
		R3DGLStateCache.setDepthMask(true);
		R3DGLStateCache.setCulling(cullFront ? cast openfl.display3D.Context3DTriangleFace.FRONT : cast openfl.display3D.Context3DTriangleFace.BACK);
		R3DGLStateCache.setBlend(cast openfl.display3D.Context3DBlendFactor.ONE, cast openfl.display3D.Context3DBlendFactor.ZERO);
		// Empty shadow map means "nothing occludes": that is the far plane, which is 0
		// with reversed depth and 1 otherwise.
		var far:Float = R3DDepth.clearValue;
		GL.clearColor(far, far, far, 1);
		GL.clearDepthf(far);
		GL.clear(GL.COLOR_BUFFER_BIT | GL.DEPTH_BUFFER_BIT | GL.STENCIL_BUFFER_BIT);
		sh.bind();
		sh.setMat4("uLightVP", vp);
		sh.setMat4("uModel", ident);
		sh.setVec2("iResolution", size, size);
		sh.setFloat("uTime", 0);
		for (m in models)
		{
			if (m == null || !m.visible) continue;
			if (layerFilter >= 0 && m.layer != layerFilter) continue;
			m.updateWorld();
			for (mesh in m.meshes)
			{
				if (mesh == null || mesh.indexBuffer == null) continue;
				if (sh.attrPosition < 0) continue;
				R3DGLStateCache.bindVertexBuffer(sh.attrPosition, mesh.vertexBuffer, 0, cast openfl.display3D.Context3DVertexBufferFormat.FLOAT_3);
				sh.setMat4("uModel", m.world);
				@:privateAccess
				{
					ctx.__flushGL();
					GL.bindBuffer(GL.ELEMENT_ARRAY_BUFFER, mesh.indexBuffer.__id);
					GL.drawElements(GL.TRIANGLES, mesh.indexCount, GL.UNSIGNED_SHORT, 0);
				}
				drawn++;
			}
		}
		scene.rebindTarget();
	}

	public function uploadTo(sh:R3DShader, rig:R3DLightRig):Void
	{
		if (sh == null) return;
		var on = enabled && light != null && light.castShadow && tex != null && tex.glTexture != null;
		// Set before the early return: a shader that includes the shadow chunk needs a
		// defined sign even while shadows are off, otherwise the compare runs with 0.
		sh.setFloat("uDepthSign", R3DDepth.sign);
		sh.setFloat("uShadowOn", on ? 1.0 : 0.0);
		sh.setFloat("uShadowFadeStart", fadeStart);
		sh.setFloat("uShadowFadeEnd", fadeEnd);
		if (!on) return;
		var idx = rig == null ? 0 : rig.indexOf(light);
		var n = 0;
		if (idx >= 0 && rig != null)
		{
			for (i in 0...idx + 1)
			{
				var l = rig.lights[i];
				if (l != null && l.enabled) n++;
			}
			idx = n - 1;
		}
		if (idx < 0) idx = 0;
		sh.setFloat("uShadowLight", idx);
		sh.setFloat("uShadowBias", bias);
		sh.setFloat("uShadowStrength", strength);
		sh.setFloat("uShadowTexel", 1.0 / Math.max(size, 1));
		sh.setMat4("uShadowVP", vp.length == 16 ? vp : R3DMat4.identity());
		var unit = 15;
		R3DScene.bindTexture(unit, tex);
		sh.setTexture("uShadowMap", unit);
	}

	public function info():String
	{
		return "阴影 " + (enabled ? "开" : "关") + " " + size + "px · 投影 " + drawn
			+ (light == null ? "" : " · " + light.name)
			+ (layerFilter >= 0 ? (" · 仅层级 " + layerFilter) : "")
			+ (fadeEnd > fadeStart ? (" · 淡出 " + fadeStart + "~" + fadeEnd) : "");
	}

	public function dispose():Void
	{
		if (tex != null)
		{
			tex.dispose();
			tex = null;
		}
	}
}
