package rainy.render3d.core;

import rainy.render3d.host.R3DLog;

import lime.graphics.opengl.GL;
import openfl.display3D.Context3D;
import openfl.display3D.Context3DVertexBufferFormat;
import openfl.display3D.textures.Texture;
import rainy.render3d.core.R3DGeom.R3DMeshData;
import rainy.render3d.core.R3DMesh;

class R3DSSAO
{
	public static var enabled:Bool = false;
	public static var radius:Float = 0.55;
	public static var intensity:Float = 0.9;
	public static var bias:Float = 0.03;
	public static var debugUV:Bool = false;
	public static var debugCopy:Bool = false;
	public static var dof:Float = 0;
	public static var focus:Float = 12;
	public static var dofRange:Float = 20;
	public static var rays:Float = 0;
	public static var sunX:Float = 0.5;
	public static var sunY:Float = 0.18;
	public static var ssr:Float = 0;
	public static var ssrStep:Float = 0.4;
	public static var ssrMaxDist:Float = 12;
	public static var ssrThickness:Float = 0.5;
	public static var lastError:String = '';
	public static var outMean:Float = -1;
	public static var outColors:Int = -1;
	public static var outSamples:Int = 0;

	static var shader:R3DShader = null;
	static var quad:R3DMesh = null;
	static var outFbo:R3DFramebuffer = null;
	static var uvShader:R3DShader = null;
	static var copyShader:R3DShader = null;

	public static function reset():Void
	{
		shader = null;
		quad = null;
		if (outFbo != null) outFbo.dispose();
		outFbo = null;
	}

	public static function available():Bool
	{
		return shader != null && !shader.failed && quad != null;
	}

	static function ensure():Bool
	{
		if (shader == null)
		{
			shader = R3DShader.fromSources(VERT, FRAG);
			if (shader == null || shader.failed)
			{
				lastError = 'SSAO 着色器编译失败';
				enabled = false;
				R3DLog.error('ssao', lastError + ' ' + R3DShader.lastErrors());
				return false;
			}
		}
		if (debugUV && uvShader == null)
		{
			uvShader = R3DShader.fromSources(VERT, UV_FRAG);
			if (uvShader != null && uvShader.failed) uvShader = null;
		}
		if (debugCopy && copyShader == null)
		{
			copyShader = R3DShader.fromSources(VERT, COPY_FRAG);
			if (copyShader != null && copyShader.failed) copyShader = null;
		}
		if (quad == null)
		{
			var d:R3DMeshData = new R3DMeshData();
			d.addVert(-1, -1, 0, 0, 1, 0, 0, 1);
			d.addVert(1, -1, 0, 1, 1, 0, 0, 1);
			d.addVert(1, 1, 0, 1, 0, 0, 0, 1);
			d.addVert(-1, 1, 0, 0, 0, 0, 0, 1);
			d.addQuadIndexed(0, 1, 2, 3, false);
			quad = R3D.mesh(d, null);
			if (quad == null)
			{
				lastError = 'SSAO 全屏四边形构造失败';
				enabled = false;
				return false;
			}
		}
		return true;
	}

	public static function render(context:Context3D, colorTex:Texture, depthTex:Dynamic, outTex:Texture,
		w:Int, h:Int, cam:R3DCamera):Bool
	{
		if (!enabled || w < 2 || h < 2) return false;
		if (colorTex == null || depthTex == null || outTex == null) return false;
		if (!ensure()) return false;

		var ok:Bool = false;
		try
		{
			if (outFbo == null) outFbo = new R3DFramebuffer();
			if (!outFbo.complete || outFbo.width != w || outFbo.height != h)
			{
				var ot:Dynamic = @:privateAccess outTex.__textureID;
				if (!outFbo.attach(cast ot, w, h))
				{
					lastError = 'SSAO 输出 FBO 不完整: ' + outFbo.statusText();
					R3DLog.error('ssao', lastError);
					return false;
				}
			}
			outFbo.bind();
			GL.viewport(0, 0, w, h);
			R3DGLStateCache.invalidate();
			R3DGLStateCache.invalidateOpenfl();
			R3DShader.invalidate();
			GL.disable(GL.DEPTH_TEST);
			GL.disable(GL.BLEND);
			GL.disable(GL.CULL_FACE);

			var active:R3DShader = shader;
			if (debugUV && uvShader != null) active = uvShader;
			else if (debugCopy && copyShader != null) active = copyShader;
			active.bind();
			if (active == shader || active == copyShader)
			{
				var invProj:Array<Float> = cam == null ? R3DMat4.identity() : cam.invProj;
				shader.setInt('uScene', 0);
				shader.setInt('uDepth', 1);
				shader.setVec2('uTexel', 1.0 / w, 1.0 / h);
				shader.setFloat('uRadius', radius);
				shader.setFloat('uIntensity', intensity);
				shader.setFloat('uBias', bias);
				shader.setFloat('uNear', cam == null ? 0.05 : cam.near);
				shader.setFloat('uFar', cam == null ? 80 : cam.far);
				shader.setFloat('uDof', dof);
				shader.setFloat('uFocus', focus);
				shader.setFloat('uDofRange', dofRange);
				shader.setFloat('uRay', rays);
				shader.setVec2('uSun', sunX, sunY);
				shader.setMat4('uInvProj', invProj);
				shader.setMat4('uProj', cam == null ? R3DMat4.identity() : cam.proj);
				shader.setFloat('uSsr', ssr);
				shader.setFloat('uSsrStep', ssrStep);
				shader.setFloat('uSsrMaxDist', ssrMaxDist);
				shader.setFloat('uSsrThickness', ssrThickness);
				shader.setFloat('uDepthSign', R3DDepth.sign);
			}

			GL.activeTexture(GL.TEXTURE0);
			GL.bindTexture(GL.TEXTURE_2D, @:privateAccess colorTex.__textureID);
			GL.activeTexture(GL.TEXTURE1);
			GL.bindTexture(GL.TEXTURE_2D, cast depthTex);
			GL.activeTexture(GL.TEXTURE0);
			R3DGLStateCache.invalidateOpenfl();

			var prog:Dynamic = active.glProgram();
			var locPos:Int = prog == null ? -1 : GL.getAttribLocation(prog, 'aPos');
			var locUv:Int = prog == null ? -1 : GL.getAttribLocation(prog, 'aUv');
			if (locPos >= 0)
			{
				GL.enableVertexAttribArray(locPos);
				GL.bindBuffer(GL.ARRAY_BUFFER, @:privateAccess quad.vertexBuffer.__id);
				GL.vertexAttribPointer(locPos, 3, GL.FLOAT, false, 0, cast 0);
			}
			if (locUv >= 0)
			{
				GL.enableVertexAttribArray(locUv);
				GL.bindBuffer(GL.ARRAY_BUFFER, @:privateAccess quad.uvBuffer.__id);
				GL.vertexAttribPointer(locUv, 2, GL.FLOAT, false, 0, cast 0);
			}
			if (outSamples < 2)
				R3DLog.info('ssao', 'rawLoc pos=' + locPos + ' uv=' + locUv
					+ ' idx=' + quad.indexCount
					+ ' uScene=' + shader.location('uScene') + ' uDepth=' + shader.location('uDepth'));

			@:privateAccess
			{
				context.__flushGL();
				GL.bindBuffer(GL.ELEMENT_ARRAY_BUFFER, quad.indexBuffer.__id);
				GL.drawElements(GL.TRIANGLES, quad.indexCount, GL.UNSIGNED_SHORT, 0);
			}
			if (outSamples < 2)
			{
				var ge:Int = 0;
				try ge = GL.getError() catch (e:Dynamic) { R3DLog.silentFailure("R3DSSAO.glError", e); }
				R3DLog.info('ssao', 'after draw glError=0x' + StringTools.hex(ge, 4));
			}

			R3DShader.invalidate();
			R3DGLStateCache.program = null;
			ok = true;
		}
		catch (e:Dynamic)
		{
			lastError = 'SSAO 渲染失败: ' + e;
			R3DLog.capture(e, 'ssao', 'render');
		}
		if (ok) probeOutput();
		if (outFbo != null && outFbo.bound) outFbo.unbind();
		return ok;
	}

	public static var VERT:String = '
attribute vec3 aPos;
attribute vec2 aUv;
varying vec2 vUv;

void main(void)
{
	vUv = aUv;
	gl_Position = vec4(aPos.xy, 0.0, 1.0);
}';

	public static var FRAG:String = '
#ifdef GL_ES
precision highp float;
#endif

uniform sampler2D uScene;
uniform sampler2D uDepth;
uniform vec2 uTexel;
uniform float uRadius;
uniform float uIntensity;
uniform float uBias;
uniform float uNear;
uniform float uFar;
uniform float uDof;
uniform float uFocus;
uniform float uDofRange;
uniform float uRay;
uniform vec2 uSun;
uniform mat4 uInvProj;
uniform mat4 uProj;
uniform float uSsr;
uniform float uSsrStep;
uniform float uSsrMaxDist;
uniform float uSsrThickness;
// +1 with reversed depth, -1 otherwise; see R3DDepth.
uniform float uDepthSign;

varying vec2 vUv;

float linDepth(float d)
{
	float z = d * 2.0 - 1.0;
	return (2.0 * uNear * uFar) / ((uFar + uNear) + uDepthSign * z * (uFar - uNear));
}

// The far plane holds no geometry. With reversed depth that is 0, without it 1.
bool isSky(float d)
{
	return (uDepthSign > 0.0) ? (d <= 0.0001) : (d >= 0.9999);
}

// Rebuild view-space position from screen uv + non-linear depth.
// There is no normal buffer, so SSR relies entirely on depth: position from the inverse
// projection, normal from the cross product of neighbouring positions.
{
	vec4 ndc = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
	vec4 v = uInvProj * ndc;
	return v.xyz / v.w;
}

void main(void)
{
	vec4 base = texture2D(uScene, vUv);
	float dc = texture2D(uDepth, vUv).r;
	vec3 col = base.rgb;
	bool sky = isSky(dc);
	float zc = linDepth(dc);

	if (uIntensity > 0.001 && !sky)
	{
		float occ = 0.0;
		for (int i = 0; i < 8; i++)
		{
			float a = float(i) * 0.7853982;
			vec2 off = vec2(cos(a), sin(a)) * uTexel * uRadius * (1.0 + float(i));
			float dz = linDepth(texture2D(uDepth, vUv + off).r);
			if (dz < zc - uBias) occ += 1.0;
		}
		col *= clamp(1.0 - (occ / 8.0) * uIntensity, 0.0, 1.0);
	}

	if (uSsr > 0.001 && !sky)
	{
		// Reconstruct view-space position from depth, then cross neighbouring positions into a normal (no GLSL derivative extension needed).
		// Reconstruct view-space position from depth, then cross neighbouring positions into a normal (no GLSL derivative extension needed).
		float dl = texture2D(uDepth, vUv - vec2(uTexel.x, 0.0)).r;
		float dr = texture2D(uDepth, vUv + vec2(uTexel.x, 0.0)).r;
		float db = texture2D(uDepth, vUv - vec2(0.0, uTexel.y)).r;
		float dt = texture2D(uDepth, vUv + vec2(0.0, uTexel.y)).r;
		vec3 Pl = viewPos(vUv - vec2(uTexel.x, 0.0), dl);
		vec3 Pr = viewPos(vUv + vec2(uTexel.x, 0.0), dr);
		vec3 Pb = viewPos(vUv - vec2(0.0, uTexel.y), db);
		vec3 Pt = viewPos(vUv + vec2(0.0, uTexel.y), dt);
		vec3 N = normalize(cross(Pr - Pl, Pt - Pb));
		vec3 V = normalize(-P);
		if (dot(N, V) < 0.0) N = -N;
		vec3 R = reflect(V, N);

		float stepLen = max(uSsrStep, 0.05);
		vec3 pos = P + R * stepLen;
		vec2 hitUv = vUv;
		float hitDist = 0.0;
		bool hit = false;
		bool escaped = false;
		for (int i = 0; i < 24; i++)
		{
			vec4 clip = uProj * vec4(pos, 1.0);
			if (clip.w <= 0.0) { escaped = true; break; }
			vec2 suv = (clip.xy / clip.w) * 0.5 + 0.5;
			if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) { escaped = true; break; }
			float sd = texture2D(uDepth, suv).r;
			if (isSky(sd)) { escaped = true; break; }
			float sviewz = viewPos(suv, sd).z;
			float pviewz = pos.z;
			// View-space z is negative and grows more negative with distance, so the ray
			// point is behind the surface exactly when it is the smaller of the two, and
			// the gap has to stay inside the thickness or the ray slipped past the slab.
			float gap = sviewz - pviewz;
			if (gap > 0.0 && gap < uSsrThickness)
			{
				hit = true;
				hitUv = suv;
				hitDist = length(pos - P);
				break;
			}
			pos += R * stepLen;
			if (length(pos - P) > uSsrMaxDist) { escaped = true; break; }
		}
		if (hit && !escaped)
		{
			vec3 refl = texture2D(uScene, hitUv).rgb;
			float fres = pow(1.0 - max(dot(N, V), 0.0), 5.0);
			fres = mix(0.04, 1.0, fres);
			vec2 ef = smoothstep(vec2(0.0), vec2(0.12), hitUv) * smoothstep(vec2(0.0), vec2(0.12), 1.0 - hitUv);
			float edge = ef.x * ef.y;
			float distFade = clamp(1.0 - hitDist / uSsrMaxDist, 0.0, 1.0);
			float w = uSsr * fres * edge * distFade;
			col = mix(col, refl, clamp(w, 0.0, 1.0));
		}
	}

	if (uDof > 0.001 && !sky)
	{
		float coc = clamp(abs(zc - uFocus) / max(uDofRange, 0.5), 0.0, 1.0) * uDof;
		if (coc > 0.02)
		{
			vec3 acc = col;
			float ws = 1.0;
			for (int i = 0; i < 5; i++)
			{
				float a = float(i) * 1.2566371;
				vec2 off = vec2(cos(a), sin(a)) * uTexel * (2.0 + coc * 14.0);
				acc += texture2D(uScene, vUv + off).rgb;
				ws += 1.0;
			}
			col = mix(col, acc / ws, coc);
		}
	}

	if (uRay > 0.001)
	{
		vec2 dir = (uSun - vUv) * 0.1;
		float acc = 0.0;
		vec2 p = vUv;
		for (int i = 0; i < 10; i++)
		{
			p += dir;
			float d = texture2D(uDepth, p).r;
			acc += isSky(d) ? 1.0 : 0.12;
		}
		col += vec3(1.0, 0.92, 0.78) * (acc / 10.0) * uRay * 0.35;
	}

	gl_FragColor = vec4(col, base.a);
}';

	public static var UV_FRAG:String = '
#ifdef GL_ES
precision highp float;
#endif

varying vec2 vUv;

void main(void)
{
	gl_FragColor = vec4(vUv, 0.0, 1.0);
}';

	public static var COPY_FRAG:String = '
#ifdef GL_ES
precision highp float;
#endif

uniform sampler2D uScene;
varying vec2 vUv;

void main(void)
{
	gl_FragColor = texture2D(uScene, vUv);
}';

	static function probeOutput():Void
	{
		try
		{
			var n:Int = 32;
			var buf:haxe.io.Bytes = haxe.io.Bytes.alloc(n * n * 4);
			GL.readPixels(Std.int((outFbo.width - n) * 0.5), Std.int((outFbo.height - n) * 0.5), n, n,
				GL.RGBA, GL.UNSIGNED_BYTE, buf);
			var sum:Float = 0;
			var cnt:Int = 0;
			var seen:Map<Int, Bool> = new Map();
			var i:Int = 0;
			var total:Int = n * n * 4;
			while (i < total)
			{
				var r:Int = buf.get(i);
				var g:Int = buf.get(i + 1);
				var b:Int = buf.get(i + 2);
				sum += (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
				cnt++;
				seen.set(((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3), true);
				i += 4;
			}
			outMean = cnt > 0 ? Math.round(sum / cnt * 1000) / 1000 : -1;
			var cc:Int = 0;
			for (_ in seen.keys()) cc++;
			outColors = cc;
			outSamples++;
			if (outSamples == 1 || outSamples % 60 == 0)
				R3DLog.info('ssao', 'out mean=' + outMean + ' colors=' + outColors + ' #' + outSamples);
		}
		catch (e:Dynamic)
			R3DLog.capture(e, 'ssao', 'probe');
	}

	public static function status():String
	{
		return 'ssao enabled=' + enabled + ' available=' + available()
			+ ' radius=' + radius + ' intensity=' + intensity + ' bias=' + bias
			+ ' ssr=' + ssr + ' ssrStep=' + ssrStep + ' ssrMax=' + ssrMaxDist
			+ ' out mean=' + outMean + ' colors=' + outColors
			+ (lastError.length > 0 ? ' err=' + lastError : '');
	}
}
