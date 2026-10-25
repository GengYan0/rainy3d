package rainy.render3d.core;

import rainy.render3d.host.R3DEnv;

import haxe.ds.StringMap;
import haxe.ds.IntMap;
import rainy.render3d.host.R3DEnv.RGB;

typedef MatNode = {
	var id:Int;
	var type:String;
	var x:Float;
	var y:Float;
	var w:Float;
	var v:Array<Float>;
	var tex:String;
	var title:String;
}

typedef MatLink = {
	var from:Int;
	var fromSlot:Int;
	var to:Int;
	var toSlot:Int;
}

typedef MatNodeDef = {
	var type:String;
	var label:String;
	var ins:Array<String>;
	var outs:Array<String>;
	var params:Array<String>;
}

class R3DMaterialGraph
{
	public static var DEFS:Array<MatNodeDef> = [
		{type: "output", label: "输出 Surface", ins: ["基础色", "法线", "粗糙度", "金属度", "自发光", "高光色", "遮蔽"], outs: [], params: []},
		{type: "color", label: "颜色 Color", ins: [], outs: ["RGBA", "RGB"], params: ["R", "G", "B", "A"]},
		{type: "float", label: "数值 Float", ins: [], outs: ["值"], params: ["值"]},
		{type: "uv", label: "UV 坐标", ins: [], outs: ["UV"], params: ["缩放U", "缩放V", "偏移U", "偏移V"]},
		{type: "tex", label: "贴图采样", ins: ["UV"], outs: ["RGBA", "RGB"], params: ["通道", "各向异性"]},
		{type: "multiply", label: "相乘", ins: ["A", "B"], outs: ["结果"], params: []},
		{type: "add", label: "相加", ins: ["A", "B"], outs: ["结果"], params: []},
		{type: "mix", label: "混合", ins: ["A", "B", "系数"], outs: ["结果"], params: []},
		{type: "power", label: "幂", ins: ["底", "指数"], outs: ["结果"], params: []},
		{type: "oneminus", label: "反相", ins: ["输入"], outs: ["结果"], params: []},
		{type: "normalmap", label: "法线贴图", ins: ["贴图"], outs: ["法线"], params: ["强度"]},
		{type: "fresnel", label: "菲涅尔", ins: [], outs: ["系数"], params: ["指数"]},
		{type: "noise", label: "噪声", ins: ["UV"], outs: ["值"], params: ["尺寸", "速度"]},
		{type: "time", label: "时间", ins: [], outs: ["值"], params: ["速度"]},
		{type: "dot", label: "点乘", ins: ["A", "B"], outs: ["值"], params: []},
		{type: "split", label: "分量拆分", ins: ["输入"], outs: ["X", "Y", "Z", "W"], params: []},
		{type: "gradient", label: "渐变", ins: ["UV"], outs: ["RGB"], params: ["方向", "强度"]}
	];

	public var nodes:Array<MatNode> = [];
	public var links:Array<MatLink> = [];
	public var nextId:Int = 1;
	public var version:Int = 1;

	var byId:IntMap<MatNode> = new IntMap();
	var inLinks:IntMap<Array<MatLink>> = new IntMap();
	var emitCache:IntMap<String> = new IntMap();
	var visiting:IntMap<Bool> = new IntMap();
	var outputNodeId:Int = -1;

	public function new() {}

	public static function def(type:String):MatNodeDef
	{
		for (d in DEFS)
			if (d.type == type) return d;
		return DEFS[0];
	}

	public static function labelOf(type:String):String
	{
		return def(type).label;
	}

	public function build():Void
	{
		byId = new IntMap();
		outputNodeId = -1;
		for (n in nodes)
		{
			byId.set(n.id, n);
			if (n.type == "output" && outputNodeId < 0) outputNodeId = n.id;
		}
	}

	public function addNode(type:String, x:Float = 0, y:Float = 0):MatNode
	{
		var d = def(type);
		var n:MatNode = {
			id: nextId++,
			type: type,
			x: x,
			y: y,
			w: 168,
			v: [for (p in d.params) (type == "color" && p == "A" ? 1.0 : (type == "float" ? 1.0 : 0.0))],
			tex: "",
			title: d.label
		};
		if (type == "color") n.v = [0.8, 0.8, 0.8, 1.0];
		if (type == "uv") n.v = [1.0, 1.0, 0.0, 0.0];
		if (type == "float") n.v = [1.0];
		if (type == "normalmap") n.v = [1.0, 0.0];
		if (type == "fresnel") n.v = [3.0];
		if (type == "noise") n.v = [6.0, 0.0];
		if (type == "time") n.v = [1.0];
		if (type == "gradient") n.v = [0.0, 1.0];
		nodes.push(n);
		build();
		return n;
	}

	public function node(id:Int):MatNode
	{
		return byId.get(id);
	}

	public function removeNode(id:Int):Void
	{
		var n = byId.get(id);
		if (n == null || n.type == "output") return;
		nodes.remove(n);
		var keep = [];
		for (l in links)
			if (l.from != id && l.to != id) keep.push(l);
		links = keep;
		build();
	}

	public function connect(from:Int, fromSlot:Int, to:Int, toSlot:Int):Bool
	{
		if (from == to) return false;
		if (byId.get(from) == null || byId.get(to) == null) return false;
		if (wouldCycle(from, to)) return false;
		var keep = [];
		for (l in links)
			if (!(l.to == to && l.toSlot == toSlot)) keep.push(l);
		links = keep;
		links.push({from: from, fromSlot: fromSlot, to: to, toSlot: toSlot});
		return true;
	}

	public function disconnectTo(to:Int, toSlot:Int):Void
	{
		var keep = [];
		for (l in links)
			if (!(l.to == to && l.toSlot == toSlot)) keep.push(l);
		links = keep;
	}

	public function linkAt(to:Int, toSlot:Int):MatLink
	{
		for (l in links)
			if (l.to == to && l.toSlot == toSlot) return l;
		return null;
	}

	function wouldCycle(from:Int, to:Int):Bool
	{
		var stack = [to];
		var seen = new IntMap<Bool>();
		while (stack.length > 0)
		{
			var cur = stack.pop();
			if (cur == from) return true;
			if (seen.exists(cur)) continue;
			seen.set(cur, true);
			for (l in links)
				if (l.to == cur) stack.push(l.from);
		}
		return false;
	}

	public function samplers():Array<String>
	{
		var out = [];
		for (n in nodes)
			if (n.type == "tex") out.push("uNodeTex" + n.id);
		return out;
	}

	public function textureNodes():Array<MatNode>
	{
		var out = [];
		for (n in nodes)
			if (n.type == "tex") out.push(n);
		return out;
	}

	public function defaultFor(type:String, slot:Int):String
	{
		switch (type)
		{
			case "output":
				switch (slot)
				{
					case 0: return "vec4(uAlbedo, 1.0)";
					case 1: return "vec4(0.0, 0.0, 1.0, 1.0)";
					case 2: return "vec4(uRoughness, uRoughness, uRoughness, 1.0)";
					case 3: return "vec4(uMetallic, uMetallic, uMetallic, 1.0)";
					case 4: return "vec4(uEmissive, 1.0)";
					case 5: return "vec4(uSpecular, 1.0)";
					case 6: return "vec4(uOcclusion, uOcclusion, uOcclusion, 1.0)";
				}
				return "vec4(0.0)";
			case "tex":
				return "vec4(uv, 0.0, 1.0)";
			case "multiply":
				return "vec4(1.0)";
			case "add":
				return "vec4(0.0)";
			case "mix":
				return slot == 2 ? "vec4(0.5)" : "vec4(0.0)";
			case "power":
				return "vec4(1.0)";
			case "oneminus":
				return "vec4(0.0)";
			case "normalmap":
				return "vec4(0.5, 0.5, 1.0, 1.0)";
			case "noise":
				return "vec4(uv, 0.0, 1.0)";
			case "dot":
				return "vec4(0.0, 0.0, 1.0, 1.0)";
			case "split":
				return "vec4(0.0)";
			case "gradient":
				return "vec4(uv, 0.0, 1.0)";
		}
		return "vec4(0.0)";
	}

	public function exprOf(id:Int, slot:Int):String
	{
		var key = id * 16 + slot;
		if (emitCache.exists(key)) return emitCache.get(key);
		if (visiting.exists(id))
		{
			emitCache.set(key, "vec4(0.0)");
			return "vec4(0.0)";
		}
		var n = byId.get(id);
		if (n == null) return "vec4(0.0)";
		visiting.set(id, true);
		var e = buildExpr(n, slot);
		visiting.remove(id);
		emitCache.set(key, e);
		return e;
	}

	function inputOf(id:Int, slot:Int):String
	{
		var l = linkAt(id, slot);
		if (l == null)
		{
			var n = byId.get(id);
			return n == null ? "vec4(0.0)" : defaultFor(n.type, slot);
		}
		return exprOf(l.from, l.fromSlot);
	}

	function buildExpr(n:MatNode, slot:Int):String
	{
		switch (n.type)
		{
			case "color":
				var a = f(n.v, 0);
				var b = f(n.v, 1);
				var c = f(n.v, 2);
				var d = f(n.v, 3);
				return slot == 0 ? ("vec4(" + a + ", " + b + ", " + c + ", " + d + ")") : ("vec3(" + a + ", " + b + ", " + c + ")");
			case "float":
				var v = f(n.v, 0);
				return "vec4(" + v + ", " + v + ", " + v + ", 1.0)";
			case "uv":
				return "vec4(r3d_TexCoordv * vec2(" + f(n.v, 0) + ", " + f(n.v, 1) + ") + vec2(" + f(n.v, 2)
					+ ", " + f(n.v, 3) + "), 0.0, 1.0)";
			case "tex":
				var uv = inputOf(n.id, 0);
				var s = "texture2D(" + uni(n) + ", (" + uv + ").xy)";
				return slot == 1 ? ("(" + s + ").rgb") : s;
			case "multiply":
				return "((" + inputOf(n.id, 0) + ") * (" + inputOf(n.id, 1) + "))";
			case "add":
				return "((" + inputOf(n.id, 0) + ") + (" + inputOf(n.id, 1) + "))";
			case "mix":
				return "mix((" + inputOf(n.id, 0) + "), (" + inputOf(n.id, 1) + "), (" + inputOf(n.id, 2) + ").x)";
			case "power":
				return "pow(max((" + inputOf(n.id, 0) + "), vec4(0.0)), vec4(max((" + inputOf(n.id, 1) + ").x, 0.0001)))";
			case "oneminus":
				return "(vec4(1.0) - (" + inputOf(n.id, 0) + "))";
			case "normalmap":
				var t = "(" + inputOf(n.id, 0) + ")";
				var s = f(n.v, 0);
				return "normalize(vec4((" + t + ").xyz * 2.0 - 1.0, 1.0)) * vec4(" + s + ", " + s + ", 1.0, 1.0)";
			case "fresnel":
				return "vec4(vec3(r3d_fresnel(Nw, Vw, " + f(n.v, 0) + ")), 1.0)";
			case "noise":
				var uv = "(" + inputOf(n.id, 0) + ").xy";
				var sc = f(n.v, 0);
				var spv:Float = (n.v != null && n.v.length > 1) ? n.v[1] : 0.0;
				var t = spv <= 0.0 ? "0.0" : ("uTime * " + f(n.v, 1));
				return "vec4(vec3(r3d_fbm(" + uv + " * " + sc + " + vec2(" + t + "))), 1.0)";
			case "time":
				return "vec4(vec3(uTime * " + f(n.v, 0) + "), 1.0)";
			case "dot":
				return "vec4(vec3(max(dot(normalize((" + inputOf(n.id, 0) + ").xyz), normalize((" + inputOf(n.id, 1)
					+ ").xyz)), 0.0)), 1.0)";
			case "split":
				var src = "(" + inputOf(n.id, 0) + ")";
				var sw = switch (slot)
				{
					case 0: ".x";
					case 1: ".y";
					case 2: ".z";
					default: ".w";
				}
				return "vec4(vec3((" + src + ")" + sw + "), 1.0)";
			case "gradient":
				var uv = "(" + inputOf(n.id, 0) + ").xy";
				var dirv:Float = (n.v != null && n.v.length > 0) ? n.v[0] : 0.0;
				var dir = Std.int(dirv);
				var amt = f(n.v, 1);
				var base = dir == 0 ? ("(" + uv + ").x") : (dir == 1 ? ("(" + uv + ").y") : ("length((" + uv + ") - vec2(0.5))"));
				return "vec4(vec3(clamp(" + base + " * " + amt + ", 0.0, 1.0)), 1.0)";
		}
		return "vec4(0.0)";
	}

	static function f(v:Array<Float>, i:Int):String
	{
		var x = (v != null && i < v.length) ? v[i] : 0.0;
		return Std.string(x);
	}

	public static function uni(n:MatNode):String
	{
		return "uNodeTex" + n.id;
	}

	public function fragSource():String
	{
		build();
		emitCache = new IntMap();
		visiting = new IntMap();
		var sb = new StringBuf();
		sb.add("#include \"r3d/inc/r3d.glsl\"\n");
		sb.add("#include \"r3d/inc/material.glsl\"\n");
		sb.add("#include \"r3d/inc/lighting.glsl\"\n\n");
		sb.add("varying vec3 vWorldNormal;\n");
		sb.add("varying vec3 vWorldTangent;\n");
		sb.add("varying vec3 vWorldBitangent;\n");
		sb.add("varying vec3 vWorldPos;\n\n");
		for (s in samplers())
			sb.add("uniform sampler2D " + s + ";\n");
		sb.add("\nvoid main()\n{\n");
		sb.add("\tvec2 uv = r3d_TexCoordv;\n");
		sb.add("\tvec3 Nw = normalize(vWorldNormal);\n");
		sb.add("\tvec3 Tw = normalize(vWorldTangent - vWorldNormal * dot(vWorldTangent, vWorldNormal));\n");
		sb.add("\tvec3 Bw = normalize(cross(Nw, Tw));\n");
		sb.add("\tvec3 Vw = normalize(r3d_cameraPos() - vWorldPos);\n");

		if (outputNodeId < 0) addNode("output", 0, 0);
		build();

		var albedo = inputOf(outputNodeId, 0);
		var normal = inputOf(outputNodeId, 1);
		var rough = inputOf(outputNodeId, 2);
		var metal = inputOf(outputNodeId, 3);
		var emissive = inputOf(outputNodeId, 4);
		var spec = inputOf(outputNodeId, 5);
		var occ = inputOf(outputNodeId, 6);

		sb.add("\tvec4 gAlbedo = " + albedo + ";\n");
		sb.add("\tvec4 gNormal = " + normal + ";\n");
		sb.add("\tvec4 gRough = " + rough + ";\n");
		sb.add("\tvec4 gMetal = " + metal + ";\n");
		sb.add("\tvec4 gEmis = " + emissive + ";\n");
		sb.add("\tvec4 gSpec = " + spec + ";\n");
		sb.add("\tvec4 gOcc = " + occ + ";\n");
		sb.add("\tvec3 tn = normalize(vec3(gNormal.xy * uNormalScale, max(gNormal.z, 0.05)));\n");
		sb.add("\tvec3 N = normalize(Tw * tn.x + Bw * tn.y + Nw * tn.z);\n");
		sb.add("\tvec3 base = max(gAlbedo.rgb * uTint.rgb, vec3(0.0)) * uTint.a;\n");
		sb.add("\tvec3 col = r3d_shade(N, Vw, vWorldPos, base, gSpec.rgb, clamp(gRough.x, 0.02, 1.0), clamp(gMetal.x, 0.0, 1.0));\n");
		sb.add("\tcol *= clamp(gOcc.x, 0.0, 1.0);\n");
		sb.add("\tcol += gEmis.rgb * uEmissiveBoost;\n");
		sb.add("\tcol = r3d_fog(col, vWorldPos);\n");
		sb.add("\tif (uAlphaScissor > 0.0 && gAlbedo.a * uTint.a < uAlphaScissor) discard;\n");
		sb.add("\tgl_FragData[0] = vec4(col, 1.0);\n}\n");
		return sb.toString();
	}

	public function toJson():Dynamic
	{
		var ns = [];
		for (n in nodes)
			ns.push({id: n.id, t: n.type, x: n.x, y: n.y, v: n.v, tex: n.tex, title: n.title});
		var ls = [];
		for (l in links)
			ls.push({f: l.from, fs: l.fromSlot, t: l.to, ts: l.toSlot});
		return {version: version, nextId: nextId, nodes: ns, links: ls};
	}

	public function fromJson(o:Dynamic):Bool
	{
		if (o == null) return false;
		var ns:Dynamic = Reflect.field(o, "nodes");
		if (ns == null || !Std.isOfType(ns, Array)) return false;
		nodes = [];
		links = [];
		nextId = Std.int(R3DLight.num(Reflect.field(o, "nextId"), 1));
		for (it in (cast ns : Array<Dynamic>))
		{
			var t = Std.string(Reflect.field(it, "t"));
			var n:MatNode = {
				id: Std.int(R3DLight.num(Reflect.field(it, "id"), 1)),
				type: t,
				x: R3DLight.num(Reflect.field(it, "x"), 0),
				y: R3DLight.num(Reflect.field(it, "y"), 0),
				w: 168,
				v: [],
				tex: Reflect.field(it, "tex") == null ? "" : Std.string(Reflect.field(it, "tex")),
				title: Reflect.field(it, "title") == null ? labelOf(t) : Std.string(Reflect.field(it, "title"))
			};
			var vv:Dynamic = Reflect.field(it, "v");
			if (vv != null && Std.isOfType(vv, Array))
				for (x in (cast vv : Array<Dynamic>))
					n.v.push(R3DLight.num(x, 0));
			nodes.push(n);
			if (n.id >= nextId) nextId = n.id + 1;
		}
		var ls:Dynamic = Reflect.field(o, "links");
		if (ls != null && Std.isOfType(ls, Array))
			for (it in (cast ls : Array<Dynamic>))
				links.push({
					from: Std.int(R3DLight.num(Reflect.field(it, "f"), -1)),
					fromSlot: Std.int(R3DLight.num(Reflect.field(it, "fs"), 0)),
					to: Std.int(R3DLight.num(Reflect.field(it, "t"), -1)),
					toSlot: Std.int(R3DLight.num(Reflect.field(it, "ts"), 0))
				});
		build();
		return true;
	}

	public static function defaultGraph():R3DMaterialGraph
	{
		var g = new R3DMaterialGraph();
		var out = g.addNode("output", 540, 80);
		var col = g.addNode("color", 100, 60);
		col.v = [0.85, 0.85, 0.85, 1.0];
		var t = g.addNode("tex", 300, 60);
		var uv = g.addNode("uv", 100, 220);
		var mul = g.addNode("multiply", 320, 240);
		g.connect(col.id, 0, mul.id, 0);
		g.connect(t.id, 1, mul.id, 1);
		g.connect(t.id, 0, out.id, 0);
		g.connect(uv.id, 0, t.id, 0);
		var rough = g.addNode("float", 100, 380);
		rough.v = [0.72];
		g.connect(rough.id, 0, out.id, 2);
		var metal = g.addNode("float", 300, 380);
		metal.v = [0.05];
		g.connect(metal.id, 0, out.id, 3);
		return g;
	}

	public function clone():R3DMaterialGraph
	{
		var g = new R3DMaterialGraph();
		g.fromJson(this.toJson());
		return g;
	}
}
