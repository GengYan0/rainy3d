package rainy.render3d.core;

import rainy.render3d.host.R3DLog;
import lime.utils.Float32Array;
import lime.utils.UInt16Array;
import openfl.display3D.IndexBuffer3D;
import openfl.display3D.VertexBuffer3D;
import rainy.render3d.core.R3D.R3DBounds;

class R3DMesh
{
	static function disposeBuf(b:Dynamic):Void
	{
		if (b == null) return;
		try b.dispose() catch (e:Dynamic) { R3DLog.silentFailure("R3DMesh.disposeBuf", e); }
	}

	public var vertexBuffer:VertexBuffer3D;
	public var uvBuffer:VertexBuffer3D;
	public var normalBuffer:VertexBuffer3D;
	public var colorBuffer:VertexBuffer3D;
	public var indexBuffer:IndexBuffer3D;
	public var wireIndexBuffer:IndexBuffer3D;
	public var wireCount:Int = 0;
	public var indices:Array<Int> = null;
	public var positions:Array<Float> = null;
	public var uvs:Array<Float> = null;
	public var normals:Array<Float> = null;
	public var material:R3DMaterial;
	public var vertices:Int = 0;
	public var triangles:Int = 0;
	public var indexCount:Int = 0;
	public var primitive:Int = 0;
	public var bounds:R3DBounds = new R3DBounds();
	public var disposed:Bool = false;

	public var boneIndices:Array<Int> = null;
	/** Four matching weights per vertex. Normalised by `setSkin`. */
	public var boneWeights:Array<Float> = null;
	/** Skeleton deforming this mesh, or null. */
	public var skeleton:R3DSkeleton = null;

	var skinnedPositions:Array<Float> = null;
	var skinnedNormals:Array<Float> = null;
	var skinVersion:Int = -1;

	public function new() {}

	public function setArrays(positions:Array<Float>, uvs:Array<Float>, indices:Array<Int>, mat:R3DMaterial, normals:Array<Float>,
			?colors:Array<Float>):Void
	{
		material = mat;
		var ctx = R3DShader.context == null ? openfl.Lib.current.stage.context3D : R3DShader.context;
		vertices = Std.int(positions.length / 3);
		triangles = Std.int(indices.length / 3);
		indexCount = indices.length;
		// Index buffers are 16-bit, so anything past 65535 wraps and the triangles connect to
		// unrelated vertices. `wireIndices()` has always guarded this; the primary path did
		// not, which turned an oversized mesh into silently scrambled geometry. Nothing can be
		// repaired here (the mesh has to be split), so at least say so.
		if (vertices > 65535)
		{
			R3DLog.warn('r3d', 'mesh 顶点 ' + vertices + ' 超出 16 位索引上限 65535，索引会回绕；需要拆分网格');
		}
		vertexBuffer = ctx.createVertexBuffer(vertices, 3);
		vertexBuffer.uploadFromTypedArray(f32(positions));
		if (uvs != null && uvs.length >= vertices * 2)
		{
			uvBuffer = ctx.createVertexBuffer(vertices, 2);
			uvBuffer.uploadFromTypedArray(f32(uvs));
		}
		if (normals != null && normals.length >= vertices * 3)
		{
			normalBuffer = ctx.createVertexBuffer(vertices, 3);
			normalBuffer.uploadFromTypedArray(f32(normals));
		}
		if (colors != null && colors.length >= vertices * 4)
		{
			colorBuffer = ctx.createVertexBuffer(vertices, 4);
			colorBuffer.uploadFromTypedArray(f32(colors));
		}
		indexBuffer = ctx.createIndexBuffer(indices.length);
		indexBuffer.uploadFromTypedArray(u16(indices));
		this.indices = indices;
		this.positions = positions;
		this.uvs = uvs;
		this.normals = normals;
		calculateBounds(positions);
	}

	static function f32(a:Array<Float>):Float32Array
	{
		var v = new Float32Array(a.length);
		var i = 0;
		while (i < a.length)
		{
			v[i] = a[i];
			i++;
		}
		return v;
	}

	static function u16(a:Array<Int>):UInt16Array
	{
		var v = new UInt16Array(a.length);
		var i = 0;
		while (i < a.length)
		{
			v[i] = a[i];
			i++;
		}
		return v;
	}

	public function setSkin(indices:Array<Int>, weights:Array<Float>, sk:R3DSkeleton):Void
	{
		if (indices == null || weights == null || sk == null || vertices == 0) return;
		if (indices.length < vertices * 4 || weights.length < vertices * 4) return;
		var i = 0;
		while (i < vertices)
		{
			var sum = weights[i * 4] + weights[i * 4 + 1] + weights[i * 4 + 2] + weights[i * 4 + 3];
			if (sum > 1e-6 && Math.abs(sum - 1.0) > 1e-4)
			{
				var inv = 1.0 / sum;
				var k = 0;
				while (k < 4)
				{
					weights[i * 4 + k] *= inv;
					k++;
				}
			}
			i++;
		}
		boneIndices = indices;
		boneWeights = weights;
		skeleton = sk;
		skinVersion = -1;
	}

	public function skin():Bool
	{
		if (skeleton == null || boneIndices == null || boneWeights == null) return false;
		if (vertexBuffer == null || positions == null) return false;
		if (skinVersion == skeleton.version) return false;
		var bones = skeleton.bones;
		var bn = bones.length;
		if (bn == 0) return false;

		var n = vertices;
		if (skinnedPositions == null || skinnedPositions.length < n * 3)
		{
			skinnedPositions = [];
			skinnedPositions.resize(n * 3);
		}
		var hasNor = normals != null && normals.length >= n * 3;
		if (hasNor && (skinnedNormals == null || skinnedNormals.length < n * 3))
		{
			skinnedNormals = [];
			skinnedNormals.resize(n * 3);
		}

		var i = 0;
		while (i < n)
		{
			var x = positions[i * 3];
			var y = positions[i * 3 + 1];
			var z = positions[i * 3 + 2];
			var vnx = hasNor ? normals[i * 3] : 0.0;
			var vny = hasNor ? normals[i * 3 + 1] : 0.0;
			var vnz = hasNor ? normals[i * 3 + 2] : 0.0;
			var ox = 0.0, oy = 0.0, oz = 0.0;
			var nx = 0.0, ny = 0.0, nz = 0.0;
			var k = 0;
			while (k < 4)
			{
				var w = boneWeights[i * 4 + k];
				if (w != 0)
				{
					var bi = boneIndices[i * 4 + k];
					if (bi >= 0 && bi < bn)
					{
						var m = bones[bi].skin;
						ox += w * (m[0] * x + m[4] * y + m[8] * z + m[12]);
						oy += w * (m[1] * x + m[5] * y + m[9] * z + m[13]);
						oz += w * (m[2] * x + m[6] * y + m[10] * z + m[14]);
						if (hasNor)
						{
							nx += w * (m[0] * vnx + m[4] * vny + m[8] * vnz);
							ny += w * (m[1] * vnx + m[5] * vny + m[9] * vnz);
							nz += w * (m[2] * vnx + m[6] * vny + m[10] * vnz);
						}
					}
				}
				k++;
			}
			skinnedPositions[i * 3] = ox;
			skinnedPositions[i * 3 + 1] = oy;
			skinnedPositions[i * 3 + 2] = oz;
			if (hasNor)
			{
				var l = Math.sqrt(nx * nx + ny * ny + nz * nz);
				if (l < 1e-6) l = 1;
				skinnedNormals[i * 3] = nx / l;
				skinnedNormals[i * 3 + 1] = ny / l;
				skinnedNormals[i * 3 + 2] = nz / l;
			}
			i++;
		}

		try
		{
			vertexBuffer.uploadFromTypedArray(f32(skinnedPositions));
			if (hasNor && normalBuffer != null) normalBuffer.uploadFromTypedArray(f32(skinnedNormals));
		}
		catch (e:Dynamic)
		{
			R3DLog.silentFailure("R3DMesh.skin", e);
			return false;
		}
		skinVersion = skeleton.version;
		// Picking reads the CPU copy, so it has to follow the pose or clicks land on the
		// bind pose while the screen shows the deformed one.
		calculateBounds(skinnedPositions);
		return true;
	}

	public function wireIndices():IndexBuffer3D
	{
		if (wireIndexBuffer != null) return wireIndexBuffer;
		if (indices == null || indices.length < 3) return null;
		if (vertices > 65535) return null;
		var n = Std.int(indices.length / 3);
		var out:Array<Int> = [];
		out.resize(n * 6);
		var w = 0;
		var i = 0;
		while (i + 2 < indices.length)
		{
			var a = indices[i];
			var b = indices[i + 1];
			var c = indices[i + 2];
			out[w++] = a;
			out[w++] = b;
			out[w++] = b;
			out[w++] = c;
			out[w++] = c;
			out[w++] = a;
			i += 3;
		}
		var ctx = R3DShader.context == null ? openfl.Lib.current.stage.context3D : R3DShader.context;
		wireIndexBuffer = ctx.createIndexBuffer(out.length);
		wireIndexBuffer.uploadFromVector(cast out, 0, out.length);
		wireCount = out.length;
		return wireIndexBuffer;
	}

	public function updatePositions(positions:Array<Float>):Void
	{
		if (vertexBuffer == null) return;
		vertexBuffer.uploadFromTypedArray(f32(positions));
	}

	public function destroy():Void
	{
		dispose();
	}

	public function calculateBounds(v:Array<Float>):Void
	{
		bounds.empty();
		var i = 0;
		while (i + 2 < v.length)
		{
			bounds.addPoint(v[i], v[i + 1], v[i + 2]);
			i += 3;
		}
	}

	public function dispose():Void
	{
		if (disposed) return;
		disposed = true;
		disposeBuf(vertexBuffer);
		disposeBuf(uvBuffer);
		disposeBuf(normalBuffer);
		disposeBuf(colorBuffer);
		disposeBuf(indexBuffer);
		disposeBuf(wireIndexBuffer);
		vertexBuffer = null;
		uvBuffer = null;
		normalBuffer = null;
		colorBuffer = null;
		indexBuffer = null;
		wireIndexBuffer = null;
		indices = null;
	}
}
