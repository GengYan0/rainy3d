package rainy.render3d.scene;

import sys.io.File;
import sys.FileSystem;
import StringTools;
import rainy.render3d.host.R3DLog;

typedef FaceBox = {
	var minX:Float;
	var minY:Float;
	var minZ:Float;
	var maxX:Float;
	var maxY:Float;
	var maxZ:Float;
	var mode:Bool;
};

class ObjData
{
	public var positions:Array<Float>;
	public var normals:Array<Float>;
	public var uvs:Array<Float>;
	public var indices:Array<Int>;
	public var hasUv:Bool = false;
	public var minX:Float = 0;
	public var minY:Float = 0;
	public var minZ:Float = 0;
	public var maxX:Float = 0;
	public var maxY:Float = 0;
	public var maxZ:Float = 0;
	public var vertexCount:Int = 0;
	public var faceCount:Int = 0;

	public function new()
	{
		positions = [];
		normals = [];
		uvs = [];
		indices = [];
	}

	public function centerX():Float return (minX + maxX) * 0.5;
	public function centerZ():Float return (minZ + maxZ) * 0.5;
	public function sizeX():Float return maxX - minX;
	public function sizeY():Float return maxY - minY;
	public function sizeZ():Float return maxZ - minZ;
}

class ObjLoader
{
	static var cache:Map<String, ObjData> = new Map();

	public static function load(absPath:String):ObjData
	{
		if (absPath == null) return null;
		if (cache.exists(absPath)) return cache.get(absPath);
		if (!FileSystem.exists(absPath))
		{
			R3DLog.warn("Shop3D", "OBJ 不存在: " + absPath);
			return null;
		}
		var data:ObjData = null;
		try
		{
			data = parse(File.getContent(absPath));
		}
		catch (e:Dynamic)
		{
			R3DLog.warn("Shop3D", "OBJ 解析失败: " + absPath + " -> " + e);
			return null;
		}
		if (data != null) cache.set(absPath, data);
		return data;
	}

	static function splitWS(s:String):Array<String>
	{
		var out:Array<String> = [];
		var n = s.length;
		var start = -1;
		var i = 0;
		while (i < n)
		{
			var c = StringTools.fastCodeAt(s, i);
			if (c == 32 || c == 9 || c == 13)
			{
				if (start >= 0)
				{
					out.push(s.substr(start, i - start));
					start = -1;
				}
			}
			else if (start < 0) start = i;
			i++;
		}
		if (start >= 0) out.push(s.substr(start, n - start));
		return out;
	}

	static inline function vIdx(tok:String, count:Int):Int
	{
		var slash = tok.indexOf("/");
		var a = slash < 0 ? tok : tok.substr(0, slash);
		var v = Std.parseInt(a);
		if (v == null) return -1;
		if (v < 0) v = count + v;
		else v -= 1;
		return v;
	}

	static inline function tIdx(tok:String, count:Int):Int
	{
		var p1 = tok.indexOf("/");
		if (p1 < 0) return -1;
		var p2 = tok.indexOf("/", p1 + 1);
		var s = (p2 < 0) ? tok.substr(p1 + 1) : tok.substr(p1 + 1, p2 - p1 - 1);
		if (s == "") return -1;
		var v = Std.parseInt(s);
		if (v == null) return -1;
		if (v < 0) v = count + v;
		else v -= 1;
		return v;
	}

	static inline function nIdx(tok:String, count:Int):Int
	{
		var p1 = tok.indexOf("/");
		if (p1 < 0) return -1;
		var p2 = tok.indexOf("/", p1 + 1);
		if (p2 < 0) return -1;
		var s = tok.substr(p2 + 1);
		if (s == "") return -1;
		var v = Std.parseInt(s);
		if (v == null) return -1;
		if (v < 0) v = count + v;
		else v -= 1;
		return v;
	}

	public static function parse(text:String):ObjData
	{
		var data = new ObjData();
		var posRaw:Array<Float> = [];
		var nrmRaw:Array<Float> = [];
		var uvRaw:Array<Float> = [];
		var posCount = 0;
		var nrmCount = 0;
		var uvCount = 0;
		var map:Map<String, Int> = new Map();
		var cur = 0;
		var face:Array<Int> = [];
		var has = false;

		var lines = text.split("\n");
		for (raw in lines)
		{
			var line = StringTools.trim(raw);
			if (line.length < 2) continue;
			var c0 = StringTools.fastCodeAt(line, 0);
			var c1 = StringTools.fastCodeAt(line, 1);
			if (c0 == 118)
			{
				if (c1 == 32 || c1 == 9)
				{
					var t = splitWS(line);
					if (t.length >= 4)
					{
						var x = Std.parseFloat(t[1]);
						var y = Std.parseFloat(t[2]);
						var z = Std.parseFloat(t[3]);
						posRaw.push(x);
						posRaw.push(y);
						posRaw.push(z);
						if (!has)
						{
							data.minX = data.maxX = x;
							data.minY = data.maxY = y;
							data.minZ = data.maxZ = z;
							has = true;
						}
						else
						{
							if (x < data.minX) data.minX = x;
							if (x > data.maxX) data.maxX = x;
							if (y < data.minY) data.minY = y;
							if (y > data.maxY) data.maxY = y;
							if (z < data.minZ) data.minZ = z;
							if (z > data.maxZ) data.maxZ = z;
						}
						posCount++;
					}
				}
				else if (c1 == 110)
				{
					var t = splitWS(line);
					if (t.length >= 4)
					{
						nrmRaw.push(Std.parseFloat(t[1]));
						nrmRaw.push(Std.parseFloat(t[2]));
						nrmRaw.push(Std.parseFloat(t[3]));
						nrmCount++;
					}
				}
				else if (c1 == 116)
				{
					var t = splitWS(line);
					if (t.length >= 3)
					{
						uvRaw.push(Std.parseFloat(t[1]));
						uvRaw.push(1 - Std.parseFloat(t[2]));
						uvCount++;
						data.hasUv = true;
					}
				}
			}
			else if (c0 == 102)
			{
				if (c1 != 32 && c1 != 9) continue;
				var t = splitWS(line);
				face = [];
				var i = 1;
				while (i < t.length)
				{
					var tok = t[i];
					if (map.exists(tok))
					{
						face.push(map.get(tok));
						i++;
						continue;
					}
					var vi = vIdx(tok, posCount);
					if (vi < 0 || vi * 3 + 2 >= posRaw.length)
					{
						i++;
						continue;
					}
					data.positions.push(posRaw[vi * 3]);
					data.positions.push(posRaw[vi * 3 + 1]);
					data.positions.push(posRaw[vi * 3 + 2]);
					var ni = nIdx(tok, nrmCount);
					if (ni >= 0 && ni * 3 + 2 < nrmRaw.length)
					{
						data.normals.push(nrmRaw[ni * 3]);
						data.normals.push(nrmRaw[ni * 3 + 1]);
						data.normals.push(nrmRaw[ni * 3 + 2]);
					}
					else
					{
						data.normals.push(0);
						data.normals.push(1);
						data.normals.push(0);
					}
					var ui = tIdx(tok, uvCount);
					if (ui >= 0 && ui * 2 + 1 < uvRaw.length)
					{
						data.uvs.push(uvRaw[ui * 2]);
						data.uvs.push(uvRaw[ui * 2 + 1]);
					}
					else
					{
						data.uvs.push(0);
						data.uvs.push(0);
					}
					map.set(tok, cur);
					face.push(cur);
					cur++;
					i++;
				}
				var len = face.length;
				if (len == 3)
				{
					data.indices.push(face[0]);
					data.indices.push(face[1]);
					data.indices.push(face[2]);
					data.faceCount++;
				}
				else if (len > 3)
				{
					var k = 1;
					while (k < len - 1)
					{
						data.indices.push(face[0]);
						data.indices.push(face[k]);
						data.indices.push(face[k + 1]);
						data.faceCount++;
						k++;
					}
				}
			}
		}

		data.vertexCount = cur;
		return data;
	}

	public static function filterByBoxes(data:ObjData, scale:Float, offsetX:Float, offsetY:Float, offsetZ:Float,
		boxes:Array<FaceBox>):ObjData
	{
		if (boxes == null || boxes.length == 0 || data == null || data.indices.length == 0) return data;
		var pos = data.positions;
		var nrm = data.normals;
		var uvs = data.uvs;
		var idx = data.indices;

		var newPos:Array<Float> = [];
		var newNrm:Array<Float> = [];
		var newUvs:Array<Float> = [];
		var newIdx:Array<Int> = [];
		var remap:Map<Int, Int> = new Map();
		var nextIdx:Int = 0;
		var faceCount:Int = 0;

		var t = 0;
		while (t + 2 < idx.length)
		{
			var a = idx[t], b = idx[t + 1], c = idx[t + 2];
			t += 3;
			if (a < 0 || b < 0 || c < 0) continue;
			if (a * 3 + 2 >= pos.length || b * 3 + 2 >= pos.length || c * 3 + 2 >= pos.length) continue;

			var ax = pos[a * 3] * scale + offsetX;
			var ay = pos[a * 3 + 1] * scale + offsetY;
			var az = pos[a * 3 + 2] * scale + offsetZ;
			var bx = pos[b * 3] * scale + offsetX;
			var by = pos[b * 3 + 1] * scale + offsetY;
			var bz = pos[b * 3 + 2] * scale + offsetZ;
			var cx = pos[c * 3] * scale + offsetX;
			var cy = pos[c * 3 + 1] * scale + offsetY;
			var cz = pos[c * 3 + 2] * scale + offsetZ;

			var cenX = (ax + bx + cx) / 3.0;
			var cenY = (ay + by + cy) / 3.0;
			var cenZ = (az + bz + cz) / 3.0;

			var drop = false;
			for (bb in boxes)
			{
				var inside = cenX >= bb.minX && cenX <= bb.maxX
					&& cenY >= bb.minY && cenY <= bb.maxY
					&& cenZ >= bb.minZ && cenZ <= bb.maxZ;
				if (bb.mode != inside)
				{
					drop = true;
					break;
				}
			}
			if (drop) continue;

			for (v in [a, b, c])
			{
				var nv = remap.get(v);
				if (nv == null)
				{
					nv = nextIdx++;
					remap.set(v, nv);
					newPos.push(pos[v * 3]);
					newPos.push(pos[v * 3 + 1]);
					newPos.push(pos[v * 3 + 2]);
					newNrm.push(nrm[v * 3]);
					newNrm.push(nrm[v * 3 + 1]);
					newNrm.push(nrm[v * 3 + 2]);
					newUvs.push(uvs[v * 2]);
					newUvs.push(uvs[v * 2 + 1]);
				}
				newIdx.push(nv);
			}
			faceCount++;
		}

		var out = new ObjData();
		out.positions = newPos;
		out.normals = newNrm;
		out.uvs = newUvs;
		out.indices = newIdx;
		out.hasUv = data.hasUv;
		out.vertexCount = nextIdx;
		out.faceCount = faceCount;
		var has = false;
		for (i in 0...nextIdx)
		{
			var x = newPos[i * 3], y = newPos[i * 3 + 1], z = newPos[i * 3 + 2];
			if (!has)
			{
				out.minX = out.maxX = x;
				out.minY = out.maxY = y;
				out.minZ = out.maxZ = z;
				has = true;
			}
			else
			{
				if (x < out.minX) out.minX = x;
				if (x > out.maxX) out.maxX = x;
				if (y < out.minY) out.minY = y;
				if (y > out.maxY) out.maxY = y;
				if (z < out.minZ) out.minZ = z;
				if (z > out.maxZ) out.maxZ = z;
			}
		}
		return out;
	}
}
