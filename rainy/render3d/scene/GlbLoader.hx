package rainy.render3d.scene;

import rainy.render3d.host.R3DEnv;

import haxe.Json;
import haxe.io.Bytes;
import openfl.display.BitmapData;
import rainy.render3d.core.R3D.R3DFace;
import rainy.render3d.core.R3D.R3DWrap;
import rainy.render3d.core.R3D.R3DFilter;
import rainy.render3d.core.R3D.R3DMipFilter;
import rainy.render3d.core.R3DMaterial;
import rainy.render3d.core.R3DMesh;
import rainy.render3d.core.R3DModel;
import rainy.render3d.core.R3DTexture;
import rainy.render3d.core.R3DShaders;
import rainy.render3d.host.R3DLog;
import sys.FileSystem;
import sys.io.File;

class GlbLoader
{
	public static var lastError:String = "";

	static var tmpSeq:Int = 0;

	public static function isGlb(path:String):Bool
	{
		var p = path == null ? "" : path.toLowerCase();
		return StringTools.endsWith(p, ".glb") || StringTools.endsWith(p, ".gltf");
	}

	public static function load(path:String):R3DModel
	{
		lastError = "";
		if (path == null || !FileSystem.exists(path))
		{
			lastError = "文件不存在 " + path;
			return null;
		}
		var json:Dynamic = null;
		var bin:Bytes = null;
		var dir = AssetLibrary.dirOf(path);
		try
		{
			var raw = File.getBytes(path);
			if (raw.length > 12 && raw.get(0) == 0x67 && raw.get(1) == 0x6C && raw.get(2) == 0x54 && raw.get(3) == 0x46)
			{
				var off = 12;
				while (off + 8 <= raw.length)
				{
					var clen = i32(raw, off);
					var ctype = i32(raw, off + 4);
					var start = off + 8;
					if (start + clen > raw.length) clen = raw.length - start;
					if (ctype == 0x4E4F534A)
						json = Json.parse(raw.getString(start, clen));
					else if (ctype == 0x004E4942)
						bin = raw.sub(start, clen);
					off = start + clen;
				}
			}
			else
				json = Json.parse(raw.getString(0, raw.length));
		}
		catch (e:Dynamic)
		{
			lastError = "解析失败 " + Std.string(e);
			return null;
		}
		if (json == null)
		{
			lastError = "无 glTF JSON";
			return null;
		}
		if (bin == null) bin = loadExternalBuffer(json, dir);
		ctxJson = json;
		ctxBin = bin;

		var accessors:Array<Dynamic> = arr(json, "accessors");
		var views:Array<Dynamic> = arr(json, "bufferViews");
		var mats:Array<Dynamic> = arr(json, "materials");
		var texs:Array<Dynamic> = arr(json, "textures");
		var imgs:Array<Dynamic> = arr(json, "images");
		var meshArr:Array<Dynamic> = arr(json, "meshes");
		var nodes:Array<Dynamic> = arr(json, "nodes");
		var root:Dynamic = json.scenes != null ? at(arr(json, "scenes"), intOf(json, "scene", 0)) : null;
		var roots:Array<Dynamic> = [];
		if (root != null) roots = arr(root, "nodes");
		else
			for (i in 0...nodes.length)
				roots.push(i);
		if (roots.length == 0)
		{
			lastError = "场景无节点";
			return null;
		}

		var cacheTex:Array<R3DTexture> = [];
		for (i in 0...imgs.length)
			cacheTex.push(null);
		var cacheMat:Array<R3DMaterial> = [];
		for (i in 0...mats.length)
			cacheMat.push(null);

		var model = new R3DModel(0, 0, 0);
		model.name = AssetLibrary.shortName(path);
		var ident = [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0];
		var count = 0;
		for (ri in roots)
		{
			var ni = Std.int(num(ri, -1));
			if (ni < 0 || ni >= nodes.length) continue;
			count += walk(nodes, ni, ident, meshArr, accessors, views, bin, dir, mats, texs, imgs, cacheMat, cacheTex, model);
		}
		if (count == 0)
		{
			lastError = lastError.length > 0 ? lastError : "没有可用的三角网格";
			return null;
		}
		R3DLog.info("Shop3D", "GLB 载入 " + path + " -> " + count + " 段网格");
		return model;
	}

	static function walk(nodes:Array<Dynamic>, i:Int, parent:Array<Float>, meshArr:Array<Dynamic>, accessors:Array<Dynamic>,
			views:Array<Dynamic>, bin:Bytes, dir:String, mats:Array<Dynamic>, texs:Array<Dynamic>, imgs:Array<Dynamic>,
			cacheMat:Array<R3DMaterial>, cacheTex:Array<R3DTexture>, out:R3DModel):Int
	{
		if (i < 0 || i >= nodes.length) return 0;
		var n:Dynamic = nodes[i];
		var local = localMatrix(n);
		var world = parent == null ? local : mul(parent, local);
		var n0 = 0;
		var mi = intOf(n, "mesh", -1);
		if (mi >= 0 && mi < meshArr.length)
			n0 += emit(meshArr[mi], world, accessors, views, bin, dir, mats, texs, imgs, cacheMat, cacheTex, out);
		for (ci in arr(n, "children"))
		{
			var idx = Std.int(num(ci, -1));
			if (idx >= 0) n0 += walk(nodes, idx, world, meshArr, accessors, views, bin, dir, mats, texs, imgs, cacheMat, cacheTex, out);
		}
		return n0;
	}

	static function emit(mesh:Dynamic, world:Array<Float>, accessors:Array<Dynamic>, views:Array<Dynamic>, bin:Bytes, dir:String,
			mats:Array<Dynamic>, texs:Array<Dynamic>, imgs:Array<Dynamic>, cacheMat:Array<R3DMaterial>,
			cacheTex:Array<R3DTexture>, out:R3DModel):Int
	{
		var prims:Array<Dynamic> = arr(mesh, "primitives");
		var made = 0;
		for (p in prims)
		{
			if (intOf(p, "mode", 4) != 4) continue;
			var att:Dynamic = Reflect.field(p, "attributes");
			if (att == null) continue;
			var pos = readAccessor(accessors, views, bin, intOf(att, "POSITION", -1), dir);
			if (pos == null || pos.length < 9) continue;
			var nrm = readAccessor(accessors, views, bin, intOf(att, "NORMAL", -1), dir);
			var texUv = readAccessor(accessors, views, bin, intOf(att, "TEXCOORD_0", -1), dir);
			var idx = readAccessor(accessors, views, bin, intOf(p, "indices", -1), dir);
			var vcount = Std.int(pos.length / 3);
			var indices:Array<Int> = [];
			if (idx != null && idx.length > 0)
				for (v in idx)
					indices.push(Std.int(v));
			else
				for (v in 0...vcount)
					indices.push(v);
			if (indices.length < 3) continue;
			for (k in 0...indices.length)
				if (indices[k] < 0 || indices[k] >= vcount) indices[k] = 0;

			var wp:Array<Float> = [];
			var wn:Array<Float> = [];
			var i3 = 0;
			while (i3 < vcount)
			{
				var x = pos[i3 * 3];
				var y = pos[i3 * 3 + 1];
				var z = pos[i3 * 3 + 2];
				wp.push(world[0] * x + world[4] * y + world[8] * z + world[12]);
				wp.push(world[1] * x + world[5] * y + world[9] * z + world[13]);
				wp.push(world[2] * x + world[6] * y + world[10] * z + world[14]);
				if (nrm != null && nrm.length >= vcount * 3)
				{
					var nx = nrm[i3 * 3];
					var ny = nrm[i3 * 3 + 1];
					var nz = nrm[i3 * 3 + 2];
					var tx = world[0] * nx + world[4] * ny + world[8] * nz;
					var ty = world[1] * nx + world[5] * ny + world[9] * nz;
					var tz = world[2] * nx + world[6] * ny + world[10] * nz;
					var l = Math.sqrt(tx * tx + ty * ty + tz * tz);
					if (l < 1e-6) l = 1;
					wn.push(tx / l);
					wn.push(ty / l);
					wn.push(tz / l);
				}
				else
				{
					wn.push(0.0);
					wn.push(0.0);
					wn.push(1.0);
				}
				i3++;
			}
			var uv:Array<Float> = [];
			var i2 = 0;
			while (i2 < vcount)
			{
				if (texUv != null && texUv.length >= vcount * 2)
				{
					uv.push(texUv[i2 * 2]);
					uv.push(1.0 - texUv[i2 * 2 + 1]);
				}
				else
				{
					uv.push(0.0);
					uv.push(0.0);
				}
				i2++;
			}
			var mat = materialOf(intOf(p, "material", -1), mats, texs, imgs, cacheMat, cacheTex, dir);
			var meshOut = new R3DMesh();
			try
			{
				meshOut.setArrays(wp, uv, indices, mat, wn);
			}
			catch (e:Dynamic)
			{
				lastError = "网格上传失败 " + Std.string(e);
				continue;
			}
			out.addMesh(meshOut);
			made++;
		}
		return made;
	}

	static function materialOf(mi:Int, mats:Array<Dynamic>, texs:Array<Dynamic>, imgs:Array<Dynamic>,
			cacheMat:Array<R3DMaterial>, cacheTex:Array<R3DTexture>, dir:String):R3DMaterial
	{
		var useIndex = mi >= 0 && mi < mats.length;
		if (useIndex && cacheMat[mi] != null) return cacheMat[mi];
		var src:Dynamic = useIndex ? mats[mi] : null;
		var mat = new R3DMaterial(R3DShaders.litShader());
		mat.name = src != null && Reflect.hasField(src, "name") ? Std.string(Reflect.field(src, "name")) : "glb";
		mat.blendMode = rainy.render3d.core.R3D.R3DBlend.MIX;
		if (src != null)
		{
			var pbr:Dynamic = Reflect.field(src, "pbrMetallicRoughness");
			if (pbr != null)
			{
				var bc:Dynamic = Reflect.field(pbr, "baseColorFactor");
				if (bc != null && Std.isOfType(bc, Array))
				{
					var bca:Array<Dynamic> = cast bc;
					if (bca.length >= 3)
					{
						mat.colorR = num(bca[0], 1);
						mat.colorG = num(bca[1], 1);
						mat.colorB = num(bca[2], 1);
						mat.colorA = bca.length > 3 ? num(bca[3], 1) : 1;
					}
				}
				mat.metallic = num(Reflect.field(pbr, "metallicFactor"), 1);
				mat.roughness = num(Reflect.field(pbr, "roughnessFactor"), 1);
				var bct:Dynamic = Reflect.field(pbr, "baseColorTexture");
				if (bct != null)
				{
					var ti = intOf(bct, "index", -1);
					var tex = textureOf(ti, texs, imgs, cacheTex, dir);
					if (tex != null) mat.textures.set("uAlbedoMap", tex);
				}
			}
			if (Reflect.field(src, "doubleSided") == true) mat.culling = R3DFace.BOTH;
			var am:Dynamic = Reflect.field(src, "alphaMode");
			if (am != null && Std.string(am) == "MASK")
			{
				mat.alphaScissor = num(Reflect.field(src, "alphaCutoff"), 0.5);
				mat.opaque = false;
			}
		}
		if (useIndex) cacheMat[mi] = mat;
		return mat;
	}

	static function textureOf(ti:Int, texs:Array<Dynamic>, imgs:Array<Dynamic>, cacheTex:Array<R3DTexture>, dir:String):R3DTexture
	{
		if (ti < 0 || ti >= texs.length) return null;
		var si = intOf(texs[ti], "source", -1);
		if (si < 0 || si >= imgs.length) return null;
		if (cacheTex[si] != null) return cacheTex[si];
		var bmp = imageOf(imgs[si], dir);
		if (bmp == null) return null;
		var tex = R3DTexture.fromBitmapData(bmp, null, true, {wrapMode: R3DWrap.REPEAT, filter: R3DFilter.LINEAR, mipFilter: R3DMipFilter.MIPLINEAR});
		cacheTex[si] = tex;
		return tex;
	}

	static function imageOf(img:Dynamic, dir:String):BitmapData
	{
		var uri:Dynamic = Reflect.field(img, "uri");
		if (uri != null)
		{
			var s = Std.string(uri);
			if (StringTools.startsWith(s, "data:")) return decode(dataBytes(s), s);
			var p = dir.length == 0 ? s : dir + "/" + s;
			try
			{
				return BitmapData.fromFile(p);
			}
			catch (e:Dynamic)
			{
				lastError = "贴图载入失败 " + p;
				return null;
			}
		}
		var bv = intOf(img, "bufferView", -1);
		if (bv < 0) return null;
		var raw = viewBytes(bv);
		if (raw == null) return null;
		return decode(raw, Std.string(Reflect.field(img, "mimeType")));
	}

	static function decode(raw:Bytes, hint:String):BitmapData
	{
		if (raw == null) return null;
		var ext = hint != null && hint.indexOf("jpeg") >= 0 ? ".jpg" : ".png";
		var p = R3DEnv.logPath("glb_tex_" + (tmpSeq++) + ext);
		try
		{
			File.saveBytes(p, raw);
			var b = BitmapData.fromFile(p);
			FileSystem.deleteFile(p);
			return b;
		}
		catch (e:Dynamic)
		{
			lastError = "内嵌贴图解码失败";
			return null;
		}
	}

	static function dataBytes(uri:String):Bytes
	{
		var comma = uri.indexOf(",");
		if (comma < 0) return null;
		var head = uri.substr(0, comma);
		var body = uri.substr(comma + 1);
		if (head.indexOf("base64") >= 0)
		{
			try
			{
				return haxe.crypto.Base64.decode(body);
			}
			catch (e:Dynamic)
			{
				return null;
			}
		}
		return Bytes.ofString(StringTools.urlDecode(body));
	}

	static function viewBytes(bv:Int):Bytes
	{
		var views:Array<Dynamic> = arr(ctxJson, "bufferViews");
		if (bv < 0 || bv >= views.length) return null;
		var v:Dynamic = views[bv];
		var buf = ctxBin;
		if (buf == null) return null;
		var off = intOf(v, "byteOffset", 0);
		var len = intOf(v, "byteLength", 0);
		if (off < 0 || len <= 0 || off + len > buf.length) return null;
		return buf.sub(off, len);
	}

	public static var ctxJson:Dynamic = null;
	public static var ctxBin:Bytes = null;

	static function loadExternalBuffer(json:Dynamic, dir:String):Bytes
	{
		var bufs:Array<Dynamic> = arr(json, "buffers");
		if (bufs.length == 0) return null;
		var uri:Dynamic = Reflect.field(bufs[0], "uri");
		if (uri == null) return null;
		var p = dir.length == 0 ? Std.string(uri) : dir + "/" + Std.string(uri);
		try
		{
			return File.getBytes(p);
		}
		catch (e:Dynamic)
		{
			lastError = "外部缓冲载入失败 " + p;
			return null;
		}
	}

	static function readAccessor(accessors:Array<Dynamic>, views:Array<Dynamic>, bin:Bytes, ai:Int, dir:String):Array<Float>
	{
		if (ai < 0 || ai >= accessors.length) return null;
		var a:Dynamic = accessors[ai];
		var bv = intOf(a, "bufferView", -1);
		if (bv < 0) return null;
		var buf = bin != null ? bin : viewBytes(bv);
		if (buf == null) return null;
		var off = intOf(a, "byteOffset", 0) + (bin == null ? 0 : intOf(at(views, bv), "byteOffset", 0));
		var ct = intOf(a, "componentType", 5126);
		var type = Std.string(Reflect.field(a, "type"));
		var comps = switch (type)
		{
			case "SCALAR": 1;
			case "VEC2": 2;
			case "VEC3": 3;
			case "VEC4": 4;
			case "MAT4": 16;
			default: 1;
		}
		var size = switch (ct)
		{
			case 5120, 5121: 1;
			case 5122, 5123: 2;
			case 5125, 5126: 4;
			default: 4;
		}
		var stride = intOf(at(views, bv), "byteStride", 0);
		if (stride <= 0) stride = comps * size;
		var normalized:Bool = Reflect.field(a, "normalized") == true;
		var scale:Float = normalized ? normalizeScale(ct) : 1;
		var n = intOf(a, "count", 0);
		var out:Array<Float> = [];
		var p = off;
		var i = 0;
		while (i < n)
		{
			if (p + comps * size > buf.length) break;
			for (c in 0...comps)
				out.push(readComponent(buf, p + c * size, ct) * scale);
			p += stride;
			i++;
		}
		return out;
	}

	static inline function normalizeScale(ct:Int):Float
	{
		return switch (ct)
		{
			case 5120: 1 / 127;
			case 5121: 1 / 255;
			case 5122: 1 / 32767;
			case 5123: 1 / 65535;
			default: 1;
		}
	}

	static function readComponent(b:Bytes, off:Int, ct:Int):Float
	{
		if (off < 0 || off >= b.length) return 0;
		return switch (ct)
		{
			case 5126: fp32(b, off);
			case 5125: i32(b, off);
			case 5123: b.get(off) | (b.get(off + 1) << 8);
			case 5122:
				var v = b.get(off) | (b.get(off + 1) << 8);
				(v > 32767) ? v - 65536 : v;
			case 5121: b.get(off);
			case 5120:
				var v = b.get(off);
				(v > 127) ? v - 256 : v;
			default: fp32(b, off);
		}
	}

	static function localMatrix(n:Dynamic):Array<Float>
	{
		var m:Dynamic = Reflect.field(n, "matrix");
		if (m != null && Std.isOfType(m, Array))
		{
			var a:Array<Dynamic> = cast m;
			var out:Array<Float> = [];
			for (v in a)
				out.push(num(v, 0));
			while (out.length < 16)
				out.push(0);
			return out;
		}
		var t = vec3(n, "translation", 0, 0, 0);
		var r = vec4(n, "rotation", 0, 0, 0, 1);
		var s = vec3(n, "scale", 1, 1, 1);
		return compose(t, r, s);
	}

	static function compose(t:Array<Float>, q:Array<Float>, s:Array<Float>):Array<Float>
	{
		var x = q[0], y = q[1], z = q[2], w = q[3];
		var x2 = x + x, y2 = y + y, z2 = z + z;
		var xx = x * x2, xy = x * y2, xz = x * z2;
		var yy = y * y2, yz = y * z2, zz = z * z2;
		var wx = w * x2, wy = w * y2, wz = w * z2;
		var sx = s[0], sy = s[1], sz = s[2];
		var m:Array<Float> = [];
		m[0] = (1 - (yy + zz)) * sx;
		m[1] = (xy + wz) * sx;
		m[2] = (xz - wy) * sx;
		m[3] = 0;
		m[4] = (xy - wz) * sy;
		m[5] = (1 - (xx + zz)) * sy;
		m[6] = (yz + wx) * sy;
		m[7] = 0;
		m[8] = (xz + wy) * sz;
		m[9] = (yz - wx) * sz;
		m[10] = (1 - (xx + yy)) * sz;
		m[11] = 0;
		m[12] = t[0];
		m[13] = t[1];
		m[14] = t[2];
		m[15] = 1;
		return m;
	}

	static function mul(a:Array<Float>, b:Array<Float>):Array<Float>
	{
		var o:Array<Float> = [];
		for (c in 0...4)
			for (r in 0...4)
			{
				var s = 0.0;
				for (k in 0...4)
					s += a[k * 4 + r] * b[c * 4 + k];
				o[c * 4 + r] = s;
			}
		return o;
	}

	static function vec3(o:Dynamic, f:String, dx:Float, dy:Float, dz:Float):Array<Float>
	{
		var v:Dynamic = Reflect.field(o, f);
		if (v == null || !Std.isOfType(v, Array)) return [dx, dy, dz];
		var a:Array<Dynamic> = cast v;
		return [a.length > 0 ? num(a[0], dx) : dx, a.length > 1 ? num(a[1], dy) : dy, a.length > 2 ? num(a[2], dz) : dz];
	}

	static function vec4(o:Dynamic, f:String, dx:Float, dy:Float, dz:Float, dw:Float):Array<Float>
	{
		var v:Dynamic = Reflect.field(o, f);
		if (v == null || !Std.isOfType(v, Array)) return [dx, dy, dz, dw];
		var a:Array<Dynamic> = cast v;
		return [
			a.length > 0 ? num(a[0], dx) : dx,
			a.length > 1 ? num(a[1], dy) : dy,
			a.length > 2 ? num(a[2], dz) : dz,
			a.length > 3 ? num(a[3], dw) : dw
		];
	}

	static function arr(o:Dynamic, f:String):Array<Dynamic>
	{
		if (o == null) return [];
		var v:Dynamic = Reflect.field(o, f);
		if (v == null || !Std.isOfType(v, Array)) return [];
		return cast v;
	}

	static function at(a:Array<Dynamic>, i:Int):Dynamic
	{
		if (a == null || i < 0 || i >= a.length) return null;
		return a[i];
	}

	static function intOf(o:Dynamic, f:String, d:Int):Int
	{
		if (o == null) return d;
		var v:Dynamic = Reflect.field(o, f);
		if (v == null) return d;
		if (Std.isOfType(v, Int)) return cast v;
		if (Std.isOfType(v, Float)) return Std.int(cast v);
		return d;
	}

	static function num(v:Dynamic, d:Float):Float
	{
		if (v == null) return d;
		if (Std.isOfType(v, Float)) return cast v;
		if (Std.isOfType(v, Int)) return cast v;
		return d;
	}

	static function i32(b:Bytes, off:Int):Int
	{
		return b.get(off) | (b.get(off + 1) << 8) | (b.get(off + 2) << 16) | (b.get(off + 3) << 24);
	}

	static function fp32(b:Bytes, off:Int):Float
	{
		var i = b.get(off) | (b.get(off + 1) << 8) | (b.get(off + 2) << 16) | (b.get(off + 3) << 24);
		var sign = (i >>> 31) == 0 ? 1.0 : -1.0;
		var e = (i >>> 23) & 0xFF;
		var m = i & 0x7FFFFF;
		if (e == 0) return sign * m * 1.401298464324817e-45;
		if (e == 255) return m != 0 ? Math.NaN : sign * Math.POSITIVE_INFINITY;
		return sign * (1.0 + m / 8388608.0) * Math.pow(2, e - 127);
	}
}
