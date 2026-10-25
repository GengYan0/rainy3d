package rainy.render3d.core;

import openfl.display3D.Context3DVertexBufferFormat;

class R3DFullscreen
{
	static var quad:R3DMesh = null;
	static var ident:Array<Float> = null;

	public static function mesh():R3DMesh
	{
		if (quad != null && quad.indexBuffer != null) return quad;
		var v:Array<Float> = [
			-1.0, -1.0, 0.0,
			1.0, -1.0, 0.0,
			1.0, 1.0, 0.0,
			-1.0, 1.0, 0.0
		];
		var u:Array<Float> = [0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0];
		var i:Array<Int> = [0, 1, 2, 0, 2, 3];
		quad = new R3DMesh();
		quad.setArrays(v, u, i, null, null, null);
		return quad;
	}

	public static function identity():Array<Float>
	{
		if (ident == null) ident = R3DMat4.identity();
		return ident;
	}

	public static function draw(context:openfl.display3D.Context3D, sh:R3DShader):Bool
	{
		var q = mesh();
		if (q == null || sh == null || context == null) return false;
		R3DGLStateCache.bindVertexBuffer(sh.attrPosition, q.vertexBuffer, 0, cast Context3DVertexBufferFormat.FLOAT_3);
		if (sh.attrTexCoord >= 0)
			R3DGLStateCache.bindVertexBuffer(sh.attrTexCoord, q.uvBuffer, 0, cast Context3DVertexBufferFormat.FLOAT_2);
		if (sh.attrNormal >= 0) R3DGLStateCache.clearVertexBuffer(sh.attrNormal);
		if (sh.attrColor >= 0) R3DGLStateCache.clearVertexBuffer(sh.attrColor);
		context.drawTriangles(q.indexBuffer, 0, 2);
		return true;
	}

	public static function dispose():Void
	{
		if (quad != null) quad.destroy();
		quad = null;
		ident = null;
	}
}
