package rainy.render3d.core;

import rainy.render3d.core.R3D.R3DBounds;
import rainy.render3d.core.R3DMat4;
import rainy.render3d.core.R3DPick.R3DRay;
import openfl.geom.Matrix3D;
import openfl.geom.Vector3D;

class R3DCamera
{
	public var x:Float = 0;
	public var y:Float = 0;
	public var z:Float = 0;
	public var rotation:Vector3D = new Vector3D();
	public var fov:Float = 55;
	public var ortho:Bool = false;
	public var orthoSize:Float = 6.0;
	public var near:Float = 0.05;
	public var far:Float = 80;
	public var aspect:Float = 1.7778;
	public var active:Bool = true;
	public var bgColor:Int = 0xff101014;
	public var view:Array<Float> = [];
	public var proj:Array<Float> = [];
	public var viewProj:Array<Float> = [];
	public var invViewProj:Array<Float> = [];
	public var invView:Array<Float> = [];

	public var invProj:Array<Float> = [];
	public var viewMatrix:Matrix3D = new Matrix3D();
	public var planes:Array<Float> = [];
	public var name:String = "camera";
	public var label:String = "";

	public var yaw(get, set):Float;
	public var pitch(get, set):Float;

	inline function get_yaw():Float return rotation.y;
	inline function set_yaw(v:Float):Float { rotation.y = v; return v; }
	inline function get_pitch():Float return -rotation.x;
	inline function set_pitch(v:Float):Float { rotation.x = -v; return v; }

	static var _p:Array<Float> = [0.0, 0.0, 0.0, 0.0];
	static var _n:Array<Float> = [0.0, 0.0, 0.0];
	static var _f32:Array<Float> = null;

	public function new(x:Float = 0, y:Float = 0, z:Float = 0)
	{
		this.x = x;
		this.y = y;
		this.z = z;
		update();
	}

	public function forward(out:Array<Float>):Array<Float>
	{
		var cp = Math.cos(pitch);
		out[0] = -Math.sin(yaw) * cp;
		out[1] = -Math.sin(pitch);
		out[2] = -Math.cos(yaw) * cp;
		return out;
	}

	public function viewRotationOnly():Array<Float>
	{
		// Reused: this runs once per frame for the skybox, and copying the 16-float matrix
		// each time was a per-frame allocation for a value that is only read immediately.
		if (_viewRot.length != 16) _viewRot = view.copy();
		else for (i in 0...16) _viewRot[i] = view[i];
		if (_viewRot.length >= 16)
		{
			_viewRot[12] = 0;
			_viewRot[13] = 0;
			_viewRot[14] = 0;
		}
		return _viewRot;
	}

	var _viewRot:Array<Float> = [];

	public function update(?elapsed:Float):Void
	{
		forward(_n);
		view = R3DMat4.lookAt(x, y, z, x + _n[0], y + _n[1], z + _n[2], 0, 1, 0, view);
		if (ortho)
		{
			var hs = Math.max(orthoSize, 0.05) * 0.5;
			proj = R3DMat4.ortho(-hs * aspect, hs * aspect, -hs, hs, near, far, null, proj);
		}
		else
			proj = R3DMat4.perspectiveHalf(fov * Math.PI / 180.0, aspect, near, far, null, proj);
		viewProj = R3DMat4.multiplication(proj, view, viewProj);
		invViewProj = R3DMat4.inverse(viewProj, invViewProj);
		invView = R3DMat4.inverse(view, invView);
		invProj = R3DMat4.inverse(proj, invProj);
		extractPlanes();
		syncMatrix3D();
	}

	function syncMatrix3D():Void
	{
		var a:Array<Float> = [];
		for (r in 0...4)
			for (c in 0...4) a[c * 4 + r] = view[r * 4 + c];
		@:privateAccess
		{
			for (i in 0...16) viewMatrix.rawData[i] = a[i];
		}
	}

	public function getScreenPoint(world:Vector3D):Vector3D
	{
		R3DMat4.transformPoint(viewProj, world.x, world.y, world.z, _p);
		return new Vector3D(_p[0], _p[1], _p[2], _p[3]);
	}

	public function toFlixelScreenPoint(ndc:Vector3D, w:Float, h:Float):Vector3D
	{
		return new Vector3D((ndc.x * 0.5 + 0.5) * w, (0.5 - ndc.y * 0.5) * h);
	}

	public function viewDepth(px:Float, py:Float, pz:Float):Float
	{
		R3DMat4.transformPoint(view, px, py, pz, _p);
		return _p[2];
	}

	function extractPlanes():Void
	{
		// Reused in place: six planes are rebuilt every frame and throwing away the array
		// each time was the largest single allocator in the camera update.
		var m = viewProj;
		if (planes.length != 24) planes.resize(24);
		var i = 0;
		i = setPlane(i, m[12] + m[0], m[13] + m[1], m[14] + m[2], m[15] + m[3]);
		i = setPlane(i, m[12] - m[0], m[13] - m[1], m[14] - m[2], m[15] - m[3]);
		i = setPlane(i, m[12] + m[4], m[13] + m[5], m[14] + m[6], m[15] + m[7]);
		i = setPlane(i, m[12] - m[4], m[13] - m[5], m[14] - m[6], m[15] - m[7]);
		i = setPlane(i, m[12] + m[8], m[13] + m[9], m[14] + m[10], m[15] + m[11]);
		setPlane(i, m[12] - m[8], m[13] - m[9], m[14] - m[10], m[15] - m[11]);
	}

	inline function setPlane(at:Int, a:Float, b:Float, c:Float, d:Float):Int
	{
		var l = Math.sqrt(a * a + b * b + c * c);
		if (l < 1e-9) l = 1;
		planes[at] = a / l;
		planes[at + 1] = b / l;
		planes[at + 2] = c / l;
		planes[at + 3] = d / l;
		return at + 4;
	}

	public function worldToScreen(px:Float, py:Float, pz:Float, w:Float, h:Float, out:Array<Float>):Bool
	{
		R3DMat4.transformPoint(viewProj, px, py, pz, _p);
		if (_p[3] <= 0.0001) return false;
		out[0] = (_p[0] * 0.5 + 0.5) * w;
		out[1] = (0.5 - _p[1] * 0.5) * h;
		out[2] = _p[3];
		return true;
	}

	public function screenRay(sx:Float, sy:Float, w:Float, h:Float):R3DRay
	{
		var nx = sx / w * 2.0 - 1.0;
		var ny = 1.0 - sy / h * 2.0;
		// The near/far NDC z follows the depth convention: with reversed depth the near
		// plane sits at +1, so a ray built from -0.99..0.99 would start behind the eye.
		R3DMat4.transformPoint(invViewProj, nx, ny, R3DDepth.ndcNear * 0.99, _rayO);
		R3DMat4.transformPoint(invViewProj, nx, ny, R3DDepth.ndcFar * 0.99, _rayE);
		return new R3DRay(_rayO[0], _rayO[1], _rayO[2], _rayE[0] - _rayO[0], _rayE[1] - _rayO[1], _rayE[2] - _rayO[2]);
	}

	static var _rayO:Array<Float> = [0.0, 0.0, 0.0, 0.0];
	static var _rayE:Array<Float> = [0.0, 0.0, 0.0, 0.0];

	public function seesSphere(cx:Float, cy:Float, cz:Float, r:Float):Bool
	{
		var i = 0;
		while (i + 3 < planes.length)
		{
			var d = planes[i] * cx + planes[i + 1] * cy + planes[i + 2] * cz + planes[i + 3];
			if (d < -r) return false;
			i += 4;
		}
		return true;
	}

	public function seesBounds(b:R3DBounds):Bool
	{
		var cx = (b.minX + b.maxX) * 0.5;
		var cy = (b.minY + b.maxY) * 0.5;
		var cz = (b.minZ + b.maxZ) * 0.5;
		return seesSphere(cx, cy, cz, b.radius(cx, cy, cz));
	}
}
