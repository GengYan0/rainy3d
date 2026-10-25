package rainy.render3d.core;

import lime.graphics.opengl.GL;
import openfl.display3D.Context3DVertexBufferFormat;
import rainy.render3d.host.R3DLog;
import rainy.render3d.core.R3DMesh;
import rainy.render3d.core.R3DGeom.R3DMeshData;

class R3DSkybox
{
	public static var enabled:Bool = false;
	public static var intensity:Float = 1.0;
	public static var rotationOnly:Bool = true;

	static var cubemap:R3DCubemap = null;
	static var shader:R3DShader = null;
	static var cube:R3DMesh = null;
	static var lastError:String = '';
	static var drawCount:Int = 0;

	public static function cubeShaderVert():String
	{
		return '
#include "r3d/inc/r3d.glsl"
#include "r3d/inc/mesh.glsl"

varying vec3 vSkyDir;

void main(void)
{
	vec4 lp = vec4(r3d_Position.xyz, 1.0);
	vSkyDir = lp.xyz;
	vec4 vp = uView * lp;
	gl_Position = uProj * vp;
	// Pushed out to the far plane: depth writes are off, so this guarantees geometry can never occlude it
	gl_Position.z = gl_Position.w;
}';
	}

	public static function cubeShaderFrag():String
	{
		return '
#include "r3d/inc/r3d.glsl"

#ifdef GL_ES
precision highp float;
#endif

varying vec3 vSkyDir;
uniform samplerCube uSky;
uniform float uSkyIntensity;

void main() {
	vec3 d = normalize(vSkyDir);
	vec3 c = textureCube(uSky, d).rgb * uSkyIntensity;
	gl_FragColor = vec4(c, 1.0);
}';
	}

	public static function setCubemapFolder(dir:String, ?ext:String = 'png'):Bool
	{
		var c:R3DCubemap = null;
		try
			c = R3DCubemap.fromFolder(dir, ext)
		catch (e:Dynamic)
		{
			lastError = 'fromFolder 异常: ' + e;
			R3DLog.capture(e, 'skybox', 'load ' + dir);
			return false;
		}
		return setCubemap(c);
	}

	public static function setCubemap(c:R3DCubemap):Bool
	{
		if (c == null)
		{
			lastError = 'cubemap 为空';
			return false;
		}
		cubemap = c;
		lastError = '';
		R3DLog.info('skybox', 'cubemap ready faceSize=' + c.faceSize + ' path=' + c.path);
		return true;
	}

	public static function hasCubemap():Bool
	{
		return cubemap != null && !cubemap.disposed;
	}

	public static function clear():Void
	{
		cubemap = null;
		enabled = false;
	}

	public static function render(cam:R3DCamera, proj:Array<Float>, view:Array<Float>, ?viewRotOnly:Array<Float>):Bool
	{
		if (!enabled || cubemap == null || cam == null) return false;

		if (shader == null)
		{
			shader = R3DShader.fromSources(cubeShaderVert(), cubeShaderFrag());
			if (shader == null || shader.failed)
			{
				lastError = 'skybox shader 编译失败';
				R3DLog.error('skybox', lastError);
				enabled = false;
				return false;
			}
		}
		if (cube == null) cube = buildCube();
		if (cube == null || cube.indexBuffer == null)
		{
			lastError = 'skybox 立方体建失败';
			enabled = false;
			return false;
		}

		var ok:Bool = false;
		try
		{
			shader.bind();
			shader.setMat4('uProj', proj);
			shader.setMat4('uView', rotationOnly && viewRotOnly != null ? viewRotOnly : view);
			shader.setMat4('uModel', R3DMat4.identity());
			shader.setVec4('uTint', 1, 1, 1, 1);

			@:privateAccess
			{
				GL.activeTexture(GL.TEXTURE0);
				GL.bindTexture(GL.TEXTURE_CUBE_MAP, cubemap.glTexture.__textureID);
			}
			R3DGLStateCache.invalidateOpenfl();
			shader.setTexture('uSky', 0);
			shader.setFloat('uSkyIntensity', intensity);

			R3DGLStateCache.bindVertexBuffer(shader.attrPosition, cube.vertexBuffer, 0, cast Context3DVertexBufferFormat.FLOAT_3);
			if (shader.attrTexCoord >= 0 && cube.uvBuffer != null)
				R3DGLStateCache.bindVertexBuffer(shader.attrTexCoord, cube.uvBuffer, 0, cast Context3DVertexBufferFormat.FLOAT_2);

			var prevMask = R3DGLStateCache.depthMask;
			R3DGLStateCache.depthMask = 0;
			GL.depthMask(false);
			GL.depthFunc(GL.LEQUAL);

			@:privateAccess
			{
				var ctx = R3DShader.context;
				ctx.__flushGL();
				GL.bindBuffer(GL.ELEMENT_ARRAY_BUFFER, cube.indexBuffer.__id);
				GL.drawElements(GL.TRIANGLES, cube.indexCount, GL.UNSIGNED_SHORT, 0);
			}

			GL.depthMask(true);
			GL.depthFunc(GL.LESS);
			R3DGLStateCache.depthMask = prevMask;

			drawCount++;
			ok = true;
			var err:Int = GL.getError();
			if (err != 0)
			{
				lastError = 'GL error 0x' + StringTools.hex(err, 4);
				R3DLog.warn('skybox', lastError);
			}
		}
		catch (e:Dynamic)
		{
			lastError = Std.string(e);
			R3DLog.capture(e, 'skybox', 'render');
			enabled = false;
		}
		return ok;
	}

	static function buildCube():R3DMesh
	{
		try
		{
			var d:R3DMeshData = new R3DMeshData();
			var s:Float = 1.0;
			pushQuads(d, s);
			return R3D.mesh(d);
		}
		catch (e:Dynamic)
		{
			R3DLog.capture(e, 'skybox', 'buildCube');
			return null;
		}
	}

	static function pushQuads(d:R3DMeshData, s:Float):Void
	{
		var faces:Array<Array<Float>> = [
			[-s, -s,  s,  s, -s,  s,  s,  s,  s, -s,  s,  s], // +Z
			[ s, -s, -s, -s, -s, -s, -s,  s, -s,  s,  s, -s], // -Z
			[-s,  s,  s,  s,  s,  s,  s,  s, -s, -s,  s, -s], // +Y
			[-s, -s, -s,  s, -s, -s,  s, -s,  s, -s, -s,  s], // -Y
			[ s, -s,  s,  s, -s, -s,  s,  s, -s,  s,  s,  s], // +X
			[-s, -s, -s, -s, -s,  s, -s,  s,  s, -s,  s, -s], // -X
		];
		for (f in faces)
			R3DGeom.pushQuad(d, f, 0, 0, 0, true);
	}

	public static function status():String
	{
		return 'skybox enabled=' + enabled + ' cubemap=' + (cubemap != null)
			+ ' faceSize=' + (cubemap == null ? 0 : cubemap.faceSize)
			+ ' draws=' + drawCount + (lastError.length > 0 ? ' err=' + lastError : '');
	}
}
