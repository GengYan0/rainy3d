package rainy.render3d.core;

import rainy.render3d.host.R3DLog;
import openfl.geom.Vector3D;
import rainy.render3d.core.R3D.R3DBounds;
import rainy.render3d.core.R3DAnim.R3DAnimPlayer;
import rainy.render3d.core.R3DAnim.R3DClip;
import rainy.render3d.core.R3DAnim.R3DFlipbook;
import rainy.render3d.core.R3DLod.R3DLodLevel;

class R3DModel
{
	public var position:Vector3D = new Vector3D();
	public var rotation:Vector3D = new Vector3D();
	public var scale:Vector3D = new Vector3D(1, 1, 1);
	public var meshes:Array<R3DMesh> = [];
	public var visible:Bool = true;
	public var name:String = "";
	public var bounds:R3DBounds = new R3DBounds();

	public var lodMesh:R3DMesh = null;
	public var lodDist:Float = 0;

	public var lodLevels:Array<R3DLodLevel> = null;

	public var anim:R3DAnimPlayer = null;
	/** Spritesheet animation on the primary material, or null. */
	public var flipbook:R3DFlipbook = null;
	public var world:Array<Float> = [];

	public var worldDirty(get, set):Bool;
	var _worldDirty:Bool = true;

	var boundsDirty:Bool = true;
	public var parent:R3DModel = null;
	public var children:Array<R3DModel> = [];
	public var layer:Int = 0;

	var _m:Array<Float> = [];
	static var _out:Array<Float> = [0.0, 0.0, 0.0];

	public var x(get, set):Float;
	public var y(get, set):Float;
	public var z(get, set):Float;
	public var angleY(get, set):Float;

	public function new(x:Float = 0, y:Float = 0, z:Float = 0)
	{
		position.setTo(x, y, z);
	}

	inline function get_x():Float return position.x;
	inline function set_x(v:Float):Float { position.x = v; worldDirty = true; return v; }
	inline function get_y():Float return position.y;
	inline function set_y(v:Float):Float { position.y = v; worldDirty = true; return v; }
	inline function get_z():Float return position.z;
	inline function set_z(v:Float):Float { position.z = v; worldDirty = true; return v; }
	inline function get_angleY():Float return rotation.y * 180 / Math.PI;
	// `worldDirty` matters here: a billboard sets `angleY` every frame to face the camera, and
	// without the flag `updateWorld()` short-circuits and the model keeps rendering with the
	// transform it was built with.
	inline function set_angleY(v:Float):Float { rotation.y = v * Math.PI / 180; worldDirty = true; return v; }

	inline function get_worldDirty():Bool return _worldDirty;

	inline function set_worldDirty(v:Bool):Bool
	{
		_worldDirty = v;
		if (v) boundsDirty = true;
		return v;
	}

	public function setPosition(x:Float = 0, y:Float = 0, z:Float = 0):Void
	{
		position.setTo(x, y, z);
		worldDirty = true;
	}

	public function playClip(clip:R3DClip, loop:Bool = true):R3DAnimPlayer
	{
		if (clip == null) return anim;
		if (anim == null) anim = R3DAnim.player(clip);
		clip.loop = loop;
		anim.play(clip);
		return anim;
	}

	public function spritesheet(cols:Int, rows:Int, frameTime:Float = 0.1):R3DFlipbook
	{
		var mat = meshes.length > 0 && meshes[0] != null ? meshes[0].material : null;
		if (flipbook == null) flipbook = R3DFlipbook.make(cols, rows, frameTime, mat);
		else flipbook.bind(mat);
		return flipbook.play();
	}

	public function skinMeshes():Void
	{
		for (m in meshes)
			if (m != null && m.skeleton != null) m.skin();
	}

	public function primary():R3DMesh
	{
		return meshes.length > 0 ? meshes[0] : null;
	}

	public function setLodLevels(levels:Array<R3DLodLevel>):Void
	{
		if (levels == null || levels.length == 0)
		{
			lodLevels = null;
			return;
		}
		levels.sort(function(a, b) return a == null ? 1 : (b == null ? -1 : (a.minScreenRadius > b.minScreenRadius ? -1 : (a.minScreenRadius < b.minScreenRadius ? 1 : 0))));
		lodLevels = levels;
	}

	public function invalidateBounds():Void
	{
		boundsDirty = true;
	}

	public function addMesh(m:R3DMesh):R3DMesh
	{
		if (m == null) return null;
		meshes.push(m);
		worldDirty = true;
		return m;
	}

	public function removeMesh(m:R3DMesh):Void
	{
		meshes.remove(m);
	}

	public function addChild(c:R3DModel):R3DModel
	{
		if (c == null) return null;
		c.parent = this;
		children.push(c);
		return c;
	}

	public function removeChild(c:R3DModel):Void
	{
		if (c == null) return;
		children.remove(c);
		c.parent = null;
	}

	public function invalidate():Void
	{
		worldDirty = true;
		for (c in children) c.invalidate();
	}

	public function updateWorld(force:Bool = false):Void
	{
		// A moved parent invalidates this model's world matrix even though none of this model's
		// own inputs changed. Without `inherited` the early-out below would keep the stale
		// matrix and the child would stay where it was while its parent walked away.
		var inherited:Bool = false;
		if (parent != null && parent.worldDirty)
		{
			parent.updateWorld(true);
			inherited = true;
		}

		if (!_worldDirty && !force && !inherited) return;

		_m = R3DMat4.compose(position.x, position.y, position.z, rotation.x, rotation.y, rotation.z,
			scale.x, scale.y, scale.z);
		world = parent == null ? _m : R3DMat4.multiplication(parent.world, _m);
		boundsDirty = true;
		_worldDirty = false;
	}

	public function worldBounds():R3DBounds
	{
		if (!_worldDirty && !boundsDirty) return bounds;

		updateWorld();
		bounds.empty();
		for (m in meshes)
		{
			var b = m.bounds;
			if (!b.valid()) continue;
			for (c in 0...8)
			{
				R3DMat4.transformPoint(world, (c & 1) != 0 ? b.maxX : b.minX, (c & 2) != 0 ? b.maxY : b.minY,
					(c & 4) != 0 ? b.maxZ : b.minZ, _out);
				bounds.addPoint(_out[0], _out[1], _out[2]);
			}
		}
		boundsDirty = false;
		return bounds;
	}

	public function worldPoint(lx:Float, ly:Float, lz:Float, out:Array<Float>):Array<Float>
	{
		updateWorld();
		R3DMat4.transformPoint(world, lx, ly, lz, out);
		return out;
	}

	public function destroy():Void
	{
		dispose();
	}

	public function dispose():Void
	{
		if (lodMesh != null)
		{
			lodMesh.dispose();
			lodMesh = null;
		}
		for (m in meshes)
			if (m != null) m.dispose();
		meshes = [];
		children = [];
		parent = null;
	}
}
