package rainy.render3d.core;

import openfl.geom.Vector3D;
import rainy.render3d.core.R3DCamera;
import rainy.render3d.core.R3DMat4;
import rainy.render3d.core.R3DLight;
import rainy.render3d.core.R3DModel;

enum abstract R3DNodeKind(Int) from Int to Int
{
	var GROUP = 0;
	var MODEL = 1;
	var LIGHT = 2;
	var CAMERA = 3;
	var EMPTY = 4;

	public function label():String
	{
		return switch (cast this : Int)
		{
			case 0: "组";
			case 1: "模型";
			case 2: "灯光";
			case 3: "相机";
			default: "空物体";
		}
	}

	public function icon():String
	{
		return switch (cast this : Int)
		{
			case 0: "[G]";
			case 1: "[M]";
			case 2: "[L]";
			case 3: "[C]";
			default: "[E]";
		}
	}
}

class R3DNode
{
	public var id:Int = 0;
	public var name:String = "node";
	public var kind:R3DNodeKind = R3DNodeKind.EMPTY;
	public var enabled:Bool = true;
	public var tag:String = "";
	public var asset:String = "";
	public var pos:Vector3D = new Vector3D();
	public var rot:Vector3D = new Vector3D();
	public var scl:Vector3D = new Vector3D(1, 1, 1);
	public var parent:R3DNode = null;
	public var children:Array<R3DNode> = [];
	public var expanded:Bool = true;
	public var locked:Bool = false;
	public var model:R3DModel = null;
	public var light:R3DLight = null;
	public var cam:R3DCamera = null;
	public var collider:R3DCollider = null;

	public function new(?n:String, ?k:R3DNodeKind)
	{
		if (n != null) name = n;
		if (k != null) kind = k;
	}

	public function local():Array<Float>
	{
		return R3DMat4.compose(pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, scl.x, scl.y, scl.z);
	}

	public function world():Array<Float>
	{
		var m = local();
		var p = parent;
		var guard = 0;
		while (p != null && guard < 32)
		{
			m = R3DMat4.multiplication(p.local(), m);
			p = p.parent;
			guard++;
		}
		return m;
	}

	public function worldPos(out:Array<Float>):Array<Float>
	{
		var m = world();
		out[0] = m[3];
		out[1] = m[7];
		out[2] = m[11];
		return out;
	}

	public function worldScale():Float
	{
		var m = world();
		var sx = Math.sqrt(m[0] * m[0] + m[1] * m[1] + m[2] * m[2]);
		return sx;
	}

	public function depth():Int
	{
		var d = 0;
		var p = parent;
		while (p != null)
		{
			d++;
			p = p.parent;
		}
		return d;
	}

	public function isAncestorOf(n:R3DNode):Bool
	{
		var p = n == null ? null : n.parent;
		var guard = 0;
		while (p != null && guard < 64)
		{
			if (p == this) return true;
			p = p.parent;
			guard++;
		}
		return false;
	}

	public function toJson():Dynamic
	{
		return {
			id: id, name: name, kind: kind, on: enabled, tag: tag, asset: asset,
			px: pos.x, py: pos.y, pz: pos.z,
			rx: rot.x, ry: rot.y, rz: rot.z,
			sx: scl.x, sy: scl.y, sz: scl.z,
			parent: parent == null ? 0 : parent.id,
			expanded: expanded, locked: locked,
			col: collider == null ? null : collider.toJson()
		};
	}

	public function copy(from:R3DNode):R3DNode
	{
		if (from == null) return this;
		name = from.name;
		kind = from.kind;
		enabled = from.enabled;
		tag = from.tag;
		asset = from.asset;
		pos.setTo(from.pos.x, from.pos.y, from.pos.z);
		rot.setTo(from.rot.x, from.rot.y, from.rot.z);
		scl.setTo(from.scl.x, from.scl.y, from.scl.z);
		expanded = from.expanded;
		locked = from.locked;
		return this;
	}
}

class R3DSceneGraph
{
	public var nodes:Array<R3DNode> = [];
	public var onRebind:R3DNode->Void;
	public var nextId:Int = 1;

	public var version:Int = 0;

	var _flat:Array<R3DNode> = [];
	var _flatVer:Int = -1;
	var _roots:Array<R3DNode> = [];
	var _rootsVer:Int = -1;

	public function new() {}

	public function clear():Void
	{
		nodes = [];
		nextId = 1;
		version++;
	}

	public function add(n:R3DNode, ?parent:R3DNode):R3DNode
	{
		if (n == null) return null;
		if (n.id <= 0)
		{
			n.id = nextId++;
		}
		else if (n.id >= nextId) nextId = n.id + 1;
		nodes.push(n);
		version++;
		if (parent != null) attach(n, parent);
		return n;
	}

	public function attach(n:R3DNode, parent:R3DNode):Void
	{
		if (n == null || parent == null || n == parent) return;
		if (n.isAncestorOf(parent)) return;
		if (n.parent != null) n.parent.children.remove(n);
		n.parent = parent;
		if (parent.children.indexOf(n) < 0) parent.children.push(n);
		version++;
	}

	public function detach(n:R3DNode):Void
	{
		if (n == null) return;
		if (n.parent != null) n.parent.children.remove(n);
		n.parent = null;
		version++;
	}

	public function remove(n:R3DNode):Void
	{
		if (n == null) return;
		var kids = n.children.copy();
		for (k in kids) remove(k);
		detach(n);
		nodes.remove(n);
		version++;
	}

	public function duplicate(n:R3DNode):R3DNode
	{
		if (n == null) return null;
		var c = new R3DNode();
		c.copy(n);
		c.name = n.name + " copy";
		c.id = nextId++;
		nodes.push(c);
		attach(c, n.parent);
		version++;
		return c;
	}

	public function byId(id:Int):R3DNode
	{
		for (n in nodes)
			if (n.id == id) return n;
		return null;
	}

	public function byName(s:String):R3DNode
	{
		for (n in nodes)
			if (n.name == s) return n;
		return null;
	}

	public function roots():Array<R3DNode>
	{
		if (_rootsVer == version) return _roots;
		_roots.resize(0);
		for (n in nodes)
			if (n.parent == null) _roots.push(n);
		_rootsVer = version;
		return _roots;
	}

	public function flat():Array<R3DNode>
	{
		if (_flatVer == version) return _flat;
		_flat.resize(0);
		for (r in roots()) walk(r, _flat, 0);
		_flatVer = version;
		return _flat;
	}

	function walk(n:R3DNode, out:Array<R3DNode>, d:Int):Void
	{
		if (n == null || d > 32) return;
		out.push(n);
		for (c in n.children) walk(c, out, d + 1);
	}

	public static function decompose(m:Array<Float>, outPos:Array<Float>, outRot:Array<Float>, outScl:Array<Float>):Void
	{
		outPos[0] = m[3];
		outPos[1] = m[7];
		outPos[2] = m[11];
		var sx = Math.sqrt(m[0] * m[0] + m[1] * m[1] + m[2] * m[2]);
		var sy = Math.sqrt(m[4] * m[4] + m[5] * m[5] + m[6] * m[6]);
		var sz = Math.sqrt(m[8] * m[8] + m[9] * m[9] + m[10] * m[10]);
		if (sx < 1e-9) sx = 1e-9;
		if (sy < 1e-9) sy = 1e-9;
		if (sz < 1e-9) sz = 1e-9;
		outScl[0] = sx;
		outScl[1] = sy;
		outScl[2] = sz;
		var b12 = m[6] / sy;
		if (b12 < -1) b12 = -1;
		if (b12 > 1) b12 = 1;
		outRot[0] = Math.asin(-b12);
		outRot[1] = Math.atan2(m[2] / sx, m[10] / sz);
		outRot[2] = Math.atan2(m[4] / sy, m[5] / sy);
	}

	static var dPos:Array<Float> = [0.0, 0.0, 0.0];
	static var dRot:Array<Float> = [0.0, 0.0, 0.0];
	static var dScl:Array<Float> = [1.0, 1.0, 1.0];

	public function applyTransforms():Void
	{
		for (n in nodes)
		{
			if (n.kind != R3DNodeKind.MODEL && n.kind != R3DNodeKind.GROUP) continue;
			if (n.model == null) continue;
			var billboard = n.tag == "billboard";
			if (n.parent == null)
			{
				n.model.setPosition(n.pos.x, n.pos.y, n.pos.z);
				if (!billboard)
				{
					n.model.rotation.setTo(n.rot.x, n.rot.y, n.rot.z);
					n.model.scale.setTo(n.scl.x, n.scl.y, n.scl.z);
				}
			}
			else
			{
				decompose(n.world(), dPos, dRot, dScl);
				n.model.setPosition(dPos[0], dPos[1], dPos[2]);
				if (!billboard)
				{
					n.model.rotation.setTo(dRot[0], dRot[1], dRot[2]);
					n.model.scale.setTo(dScl[0], dScl[1], dScl[2]);
				}
			}
			n.model.visible = n.enabled;
			n.model.worldDirty = true;
		}
		for (n in nodes)
		{
			if (n.light == null) continue;
			var p = n.parent == null ? n.pos : null;
			if (p == null)
			{
				var m = n.world();
				n.light.x = m[3];
				n.light.y = m[7];
				n.light.z = m[11];
			}
			else n.light.setPos(p.x, p.y, p.z);
			n.light.enabled = n.enabled;
		}
		for (n in nodes)
		{
			if (n.cam == null) continue;
			var m = n.world();
			n.cam.x = m[3];
			n.cam.y = m[7];
			n.cam.z = m[11];
			n.cam.rotation.y = n.rot.y;
			n.cam.rotation.x = -n.rot.x;
			n.cam.active = n.enabled;
		}
	}

	public function toJson(?name:String):Dynamic
	{
		var arr:Array<Dynamic> = [];
		for (n in nodes) arr.push(n.toJson());
		return {r3d: 1, name: name == null ? "scene" : name, nextId: nextId, nodes: arr};
	}

	public function fromJson(o:Dynamic):Bool
	{
		if (o == null) return false;
		var arr:Dynamic = Reflect.field(o, "nodes");
		if (arr == null || !Std.isOfType(arr, Array)) return false;
		clear();
		var saved:Array<Dynamic> = cast arr;
		for (it in saved)
		{
			if (it == null) continue;
			var n = new R3DNode();
			n.id = Std.int(num(Reflect.field(it, "id"), nextId));
			n.name = Reflect.field(it, "name") == null ? ("node" + n.id) : Std.string(Reflect.field(it, "name"));
			n.kind = cast Std.int(num(Reflect.field(it, "kind"), 4));
			n.enabled = Reflect.field(it, "on") != false;
			n.tag = Reflect.field(it, "tag") == null ? "" : Std.string(Reflect.field(it, "tag"));
			n.asset = Reflect.field(it, "asset") == null ? "" : Std.string(Reflect.field(it, "asset"));
			n.pos.setTo(num(Reflect.field(it, "px"), 0), num(Reflect.field(it, "py"), 0), num(Reflect.field(it, "pz"), 0));
			n.rot.setTo(num(Reflect.field(it, "rx"), 0), num(Reflect.field(it, "ry"), 0), num(Reflect.field(it, "rz"), 0));
			n.scl.setTo(num(Reflect.field(it, "sx"), 1), num(Reflect.field(it, "sy"), 1), num(Reflect.field(it, "sz"), 1));
			n.expanded = Reflect.field(it, "expanded") != false;
			n.locked = Reflect.field(it, "locked") == true;
			n.collider = R3DCollider.fromJson(Reflect.field(it, "col"));
			nodes.push(n);
			if (n.id >= nextId) nextId = n.id + 1;
		}
		for (it in saved)
		{
			var nid = Std.int(num(Reflect.field(it, "id"), 0));
			var pid = Std.int(num(Reflect.field(it, "parent"), 0));
			if (pid <= 0) continue;
			var n = byId(nid);
			var p = byId(pid);
			if (n != null && p != null) attach(n, p);
		}
		if (onRebind != null)
			for (n in nodes) onRebind(n);
		return true;
	}

	public static function num(v:Dynamic, d:Float):Float
		return R3DLight.num(v, d);
}
