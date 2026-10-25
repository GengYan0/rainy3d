package rainy.render3d.core;

import flixel.FlxG;
import rainy.render3d.core.R3DMaterial;
import rainy.render3d.core.R3DMaterialGraph.MatNode;
import rainy.render3d.core.R3DShell.R3DSection;
import rainy.render3d.core.R3DShell.R3DRow;

class R3DNodeEditor extends R3DShell
{
	static inline var NW:Int = 176;
	static inline var HEAD:Int = 22;
	static inline var ROW:Int = 16;

	public var graph:R3DMaterialGraph;
	public var target:R3DMaterial;
	public var onApply:Void->Bool;
	public var onSave:Void->Void;
	public var onLoad:Void->Void;
	public var onClose:Void->Void;
	public var texList:Void->Array<String>;

	var panX:Float = 60;
	var panY:Float = 40;
	var zoom:Float = 1.0;
	var selId:Int = -1;
	var dragId:Int = -1;
	var dragOffX:Float = 0;
	var dragOffY:Float = 0;
	var linkFrom:Int = -1;
	var linkSlot:Int = 0;
	var paletteOpen:Bool = false;
	var texPickFor:Int = -1;
	var railCat:Int = 0;
	var ports:Array<{id:Int, slot:Int, out:Bool, x:Float, y:Float}> = [];
	var lastMsg:String = "";

	static var RAIL:Array<String> = ["常量 / 颜色", "贴图 / UV", "数学运算", "向量 / 几何", "程序化", "输出"];
	static var CATS:Array<Array<String>> = [
		["color", "float"],
		["uv", "tex", "normalmap"],
		["multiply", "add", "mix", "power", "oneminus"],
		["dot", "split", "fresnel", "gradient"],
		["noise", "time"],
		["output"]
	];

	public function new()
	{
		super();
	}

	public function show(g:R3DMaterialGraph, m:R3DMaterial):Void
	{
		graph = g;
		target = m;
		if (graph != null)
		{
			graph.build();
			selId = graph.nodes.length > 0 ? graph.nodes[0].id : -1;
		}
		visible = true;
		opened = true;
		rebuild();
		railed();
		markDirty();
	}

	public function hide():Void
	{
		visible = false;
		opened = false;
		if (onClose != null) onClose();
	}

	function railed():Void {}

	function rebuild():Void
	{
		ports = [];
		if (graph == null) return;
		for (n in graph.nodes)
		{
			var d = R3DMaterialGraph.def(n.type);
			var y = n.y + HEAD + 4 + ROW * 0.5;
			for (i in 0...d.ins.length)
			{
				ports.push({id: n.id, slot: i, out: false, x: n.x, y: y});
				y += ROW;
			}
			for (i in 0...d.outs.length)
			{
				ports.push({id: n.id, slot: i, out: true, x: n.x + NW, y: y});
				y += ROW;
			}
		}
	}

	function nodeH(n:MatNode):Float
	{
		var d = R3DMaterialGraph.def(n.type);
		return HEAD + 4 + (d.ins.length + d.outs.length) * ROW + 6;
	}

	function cw():Float
	{
		return FlxG.width - railW - inspW;
	}

	function cx0():Float
	{
		return railW;
	}

	function cy0():Float
	{
		return R3DShell.TOOLBAR_H;
	}

	function sx(v:Float):Float
	{
		return cx0() + panX + v * zoom;
	}

	function sy(v:Float):Float
	{
		return cy0() + panY + v * zoom;
	}

	function wx(v:Float):Float
	{
		return (v - cx0() - panX) / zoom;
	}

	function wy(v:Float):Float
	{
		return (v - cy0() - panY) / zoom;
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);
		if (!visible || graph == null) return;
		lastMsg = "";
		handleKeys();
		if (!needsFrame()) return;
		drawBuiltinToolbar();
		chrome(TOOLS, RAIL, stats());
		handleTools();
		handleRail();
		drawCanvas();
		drawPalette();
		drawTexPicker();
		if (inspector(nodeSections(), target == null ? "节点" : ("节点 · " + (target.name == null ? "" : target.name))))
			apply();
	}

	static var TOOLS:Array<String> = ["+ 添加节点", "删除节点", "适应视图", "缩小", "放大", "应用并编译", "保存图", "读取图", "关闭"];

	function drawBuiltinToolbar():Void {}

	function stats():String
	{
		if (graph == null) return "";
		return "节点 " + graph.nodes.length + "   连线 " + graph.links.length
			+ "   缩放 " + R3DUI.fmt(zoom, 2) + "   " + lastMsg;
	}

	function handleTools():Void
	{
		var t = takeToolHit();
		if (t < 0) return;
		switch (t)
		{
			case 0:
				paletteOpen = !paletteOpen;
				texPickFor = -1;
			case 1:
				if (selId >= 0)
				{
					graph.removeNode(selId);
					selId = graph.nodes.length > 0 ? graph.nodes[0].id : -1;
					rebuild();
					apply();
				}
			case 2:
				fit();
			case 3:
				zoom = Math.max(0.35, zoom - 0.12);
			case 4:
				zoom = Math.min(2.4, zoom + 0.12);
			case 5:
				apply();
			case 6:
				if (onSave != null) onSave();
				lastMsg = "已保存";
			case 7:
				if (onLoad != null) onLoad();
				rebuild();
				lastMsg = "已读取";
			case 8:
				hide();
			default:
		}
	}

	function handleRail():Void
	{
		var r = takeRailHit();
		if (r < 0) return;
		railCat = r;
		paletteOpen = true;
	}

	function fit():Void
	{
		if (graph.nodes.length == 0) return;
		var minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
		for (n in graph.nodes)
		{
			minX = Math.min(minX, n.x);
			minY = Math.min(minY, n.y);
			maxX = Math.max(maxX, n.x + NW);
			maxY = Math.max(maxY, n.y + nodeH(n));
		}
		var availW = cw() - 60;
		var availH = FlxG.height - R3DShell.TOOLBAR_H - R3DShell.STATUS_H - 60;
		zoom = Math.max(0.35, Math.min(1.6, Math.min(availW / Math.max(maxX - minX, 1), availH / Math.max(maxY - minY, 1))));
		panX = 30 - minX * zoom + (availW - (maxX - minX) * zoom) * 0.5;
		panY = 30 - minY * zoom + (availH - (maxY - minY) * zoom) * 0.5;
	}

	function apply():Bool
	{
		if (onApply == null) return false;
		var ok = onApply();
		lastMsg = ok ? "已编译" : "编译失败（详情见日志）";
		return ok;
	}

	function handleKeys():Void
	{
		if (FlxG.keys.justPressed.ESCAPE)
		{
			if (paletteOpen)
			{
				paletteOpen = false;
				return;
			}
			if (texPickFor >= 0)
			{
				texPickFor = -1;
				return;
			}
			if (onSave != null) onSave();
			hide();
			return;
		}
		if (FlxG.keys.justPressed.DELETE && selId >= 0)
		{
			graph.removeNode(selId);
			selId = graph.nodes.length > 0 ? graph.nodes[0].id : -1;
			rebuild();
			apply();
			markDirty();
		}
		if (FlxG.keys.justPressed.F5 && onSave != null) onSave();
		if (FlxG.keys.justPressed.F9 && onLoad != null)
		{
			onLoad();
			rebuild();
			markDirty();
		}
		if (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.S && onSave != null) onSave();
		var n = graph.node(selId);
		if (n == null) return;
		var step = (FlxG.keys.pressed.SHIFT ? 12.0 : 3.0) / zoom;
		if (FlxG.keys.pressed.UP || FlxG.keys.pressed.DOWN || FlxG.keys.pressed.LEFT || FlxG.keys.pressed.RIGHT)
		{
			if (FlxG.keys.pressed.UP) n.y -= step;
			if (FlxG.keys.pressed.DOWN) n.y += step;
			if (FlxG.keys.pressed.LEFT) n.x -= step;
			if (FlxG.keys.pressed.RIGHT) n.x += step;
			markDirty();
		}
	}

	function pickPort(mxp:Float, myp:Float):Int
	{
		var best = -1;
		var bd = 13.0;
		for (i in 0...ports.length)
		{
			var p = ports[i];
			var dx = sx(p.x) - mxp;
			var dy = sy(p.y) - myp;
			var d = Math.sqrt(dx * dx + dy * dy);
			if (d < bd)
			{
				bd = d;
				best = i;
			}
		}
		return best;
	}

	function pickNode(mxp:Float, myp:Float):MatNode
	{
		var r = graph.nodes.copy();
		r.reverse();
		for (n in r)
		{
			var x0 = sx(n.x), y0 = sy(n.y);
			if (mxp >= x0 && mxp <= x0 + NW * zoom && myp >= y0 && myp <= y0 + nodeH(n) * zoom) return n;
		}
		return null;
	}

	function overCanvas(mxp:Float, myp:Float):Bool
	{
		return mxp > railW && mxp < FlxG.width - inspW && myp > R3DShell.TOOLBAR_H && myp < FlxG.height - R3DShell.STATUS_H;
	}

	function drawCanvas():Void
	{
		var x0 = cx0();
		var y0 = cy0();
		var w = cw();
		var h = FlxG.height - R3DShell.TOOLBAR_H - R3DShell.STATUS_H;
		ui.rect(x0, y0, w, h, 0xFF0C1016);
		ui.setClip(x0, y0, w, h);

		var mxp = FlxG.mouse.viewX;
		var myp = FlxG.mouse.viewY;
		var inCanvas = overCanvas(mxp, myp);

		if (inCanvas && FlxG.mouse.wheel != 0 && !paletteOpen && texPickFor < 0)
		{
			var old = zoom;
			zoom = Math.max(0.35, Math.min(2.4, zoom + FlxG.mouse.wheel * 0.09));
			panX = (mxp - x0) - ((mxp - x0) - panX) * (zoom / old);
			panY = (myp - y0) - ((myp - y0) - panY) * (zoom / old);
		}
		if (inCanvas && FlxG.mouse.pressed && (FlxG.mouse.pressedMiddle || FlxG.mouse.pressedRight))
		{
			panX += FlxG.mouse.deltaViewX;
			panY += FlxG.mouse.deltaViewY;
			ui.overUi = true;
		}

		var gi = 64.0 * zoom;
		if (gi > 8)
		{
			var gx = panX % gi;
			var gy = panY % gi;
			var i = 0;
			while (i * gi < w)
			{
				ui.rect(x0 + gx + i * gi, y0, 1, h, 0xFF131A22);
				i++;
			}
			i = 0;
			while (i * gi < h)
			{
				ui.rect(x0, y0 + gy + i * gi, w, 1, 0xFF131A22);
				i++;
			}
		}

		for (l in graph.links)
		{
			var pf = portAt(l.from, l.fromSlot, true);
			var pt = portAt(l.to, l.toSlot, false);
			if (pf == null || pt == null) continue;
			var ax = sx(pf.x), ay = sy(pf.y), bx = sx(pt.x), by = sy(pt.y);
			var mid = (ax + bx) * 0.5;
			wire(ax, ay, mid, ay);
			wire(mid, ay, mid, by);
			wire(mid, by, bx, by);
			ui.roundRect(mid - 3, by - 3, 6, 6, R3DUI.ok, 3);
		}
		if (linkFrom >= 0)
		{
			var pf = portAt(linkFrom, linkSlot, true);
			if (pf != null) wire(sx(pf.x), sy(pf.y), mxp, myp);
		}

		for (n in graph.nodes)
		{
			var d = R3DMaterialGraph.def(n.type);
			var x = sx(n.x), y = sy(n.y);
			var ww = NW * zoom, hh = nodeH(n) * zoom;
			if (x > x0 + w || y > y0 + h || x + ww < x0 || y + hh < y0) continue;
			var sel = n.id == selId;
			ui.roundRect(x, y, ww, hh, n.type == "output" ? 0xFF23202C : R3DUI.panel2, 5);
			ui.roundRect(x, y, ww, HEAD * zoom, sel ? mix2(R3DUI.panel3, R3DUI.accent2, 0.4) : R3DUI.panel3, 5);
			if (sel) ui.roundFrame(x, y, ww, hh, R3DUI.accent2, 5);
			ui.txt(x + 7, y + 4, n.title + "   #" + n.id, sel ? 0xFFFFE6A0 : R3DUI.text, Std.int(12 * zoom), "left", ww - 12);
			var yy = y + (HEAD + 4) * zoom;
			for (i in 0...d.ins.length)
			{
				var lk = graph.linkAt(n.id, i);
				ui.txt(x + 10, yy - 1, d.ins[i], lk != null ? R3DUI.ok : R3DUI.dim, Std.int(11 * zoom), "left", ww - 16);
				ui.roundRect(x - 4, yy + ROW * zoom * 0.5 - 4, 8, 8, lk != null ? R3DUI.ok : R3DUI.line2, 4);
				yy += ROW * zoom;
			}
			for (i in 0...d.outs.length)
			{
				ui.txt(x + ww - 62, yy - 1, d.outs[i], 0xFFCFE8FF, Std.int(11 * zoom), "left", 58);
				ui.roundRect(x + ww - 4, yy + ROW * zoom * 0.5 - 4, 8, 8, R3DUI.accent, 4);
				yy += ROW * zoom;
			}
			if (n.type == "tex")
				ui.txt(x + 10, y + hh - 16, shortName(n.tex), R3DUI.accent2, Std.int(10 * zoom), "left", ww - 16);
		}
		ui.clearClip();

		if (!paletteOpen && texPickFor < 0 && inCanvas)
		{
			var hi = pickPort(mxp, myp);
			if (hi >= 0)
			{
				var p = ports[hi];
				ui.roundFrame(sx(p.x) - 7, sy(p.y) - 7, 14, 14, R3DUI.accent2, 7);
				ui.txt(x0 + 10, y0 + 8, (p.out ? "输出端口 " : "输入端口 ") + p.slot, R3DUI.accent2, 12, "left", 200);
			}
			if (FlxG.mouse.justPressed)
			{
				if (hi >= 0)
				{
					var p = ports[hi];
					if (linkFrom < 0)
					{
						if (p.out)
						{
							linkFrom = p.id;
							linkSlot = p.slot;
							selId = p.id;
						}
						else if (graph.linkAt(p.id, p.slot) != null)
						{
							graph.disconnectTo(p.id, p.slot);
							apply();
						}
					}
					else if (!p.out && p.id != linkFrom)
					{
						if (graph.connect(linkFrom, linkSlot, p.id, p.slot)) lastMsg = "已连线";
						else lastMsg = "已拒绝（会成环）";
						linkFrom = -1;
						apply();
					}
					else if (p.out)
					{
						linkFrom = p.id;
						linkSlot = p.slot;
					}
				}
				else
				{
					linkFrom = -1;
					var n = pickNode(mxp, myp);
					selId = n == null ? -1 : n.id;
					if (n != null)
					{
						dragId = n.id;
						dragOffX = wx(mxp) - n.x;
						dragOffY = wy(myp) - n.y;
					}
				}
			}
			if (dragId >= 0 && FlxG.mouse.pressed)
			{
				var n = graph.node(dragId);
				if (n != null)
				{
					n.x = wx(mxp) - dragOffX;
					n.y = wy(myp) - dragOffY;
					rebuild();
				}
			}
			if (!FlxG.mouse.pressed) dragId = -1;
			ui.overUi = true;
		}
	}

	function shortName(p:String):String
	{
		if (p == null || p.length == 0) return "(未指定贴图  ·  点右侧选择)";
		var i = p.lastIndexOf("/");
		return i < 0 ? p : p.substr(i + 1);
	}

	function portAt(id:Int, slot:Int, out:Bool):{id:Int, slot:Int, out:Bool, x:Float, y:Float}
	{
		for (p in ports)
			if (p.id == id && p.slot == slot && p.out == out) return p;
		return null;
	}

	function wire(ax:Float, ay:Float, bx:Float, by:Float):Void
	{
		ui.rect(Math.min(ax, bx), ay, Math.abs(bx - ax) + 1, 2, R3DUI.ok);
		ui.rect(ax, Math.min(ay, by), 2, Math.abs(by - ay) + 1, R3DUI.ok);
	}

	function drawPalette():Void
	{
		if (!paletteOpen) return;
		var x = railW + 16;
		var y = R3DShell.TOOLBAR_H + 16;
		var w = 300.0;
		var list = CATS[Std.int(Math.max(0, Math.min(CATS.length - 1, railCat)))];
		var h = 44 + list.length * 30;
		ui.roundRect(x, y, w, h, R3DUI.panel, 6);
		ui.roundFrame(x, y, w, h, R3DUI.accent, 6);
		ui.txt(x + 14, y + 12, "添加节点 · " + RAIL[railCat] + "     (点空白关闭)", R3DUI.text, 13, "left", w - 28);
		for (i in 0...list.length)
		{
			var ry = y + 40 + i * 30;
			var d = R3DMaterialGraph.def(list[i]);
			if (ui.listRow("pal" + i, x + 8, ry, w - 16, 28, d.label, d.type + "   输入 " + d.ins.length + " / 输出 " + d.outs.length,
					false))
			{
				var n = graph.addNode(d.type, wx(x + w + 40), wy(R3DShell.TOOLBAR_H + 80) + i * 8);
				selId = n.id;
				paletteOpen = false;
				rebuild();
				apply();
				return;
			}
		}
	}

	function drawTexPicker():Void
	{
		if (texPickFor < 0) return;
		var n = graph.node(texPickFor);
		if (n == null)
		{
			texPickFor = -1;
			return;
		}
		var list = texList == null ? [] : texList();
		var x = FlxG.width - inspW - 344;
		var y = R3DShell.TOOLBAR_H + 16;
		var w = 336.0;
		var h = Math.min(FlxG.height - R3DShell.TOOLBAR_H - R3DShell.STATUS_H - 40, 60 + Math.max(1, list.length) * 26);
		ui.roundRect(x, y, w, h, R3DUI.panel, 6);
		ui.roundFrame(x, y, w, h, R3DUI.accent2, 6);
		ui.txt(x + 14, y + 12, "选择贴图（" + list.length + " 个）    点空白关闭", R3DUI.text, 13, "left", w - 28);
		ui.setClip(x + 6, y + 38, w - 12, h - 44);
		for (i in 0...list.length)
		{
			var ry = y + 38 + i * 26;
			if (ry > y + h - 20) break;
			if (ui.listRow("tx" + i, x + 8, ry, w - 16, 24, shortName(list[i]), null, n.tex == list[i]))
			{
				n.tex = list[i];
				texPickFor = -1;
				ui.clearClip();
				apply();
				return;
			}
		}
		ui.clearClip();
		ui.overUi = true;
	}

	function nodeSections():Array<R3DSection>
	{
		var secs:Array<R3DSection> = [];
		if (graph == null) return secs;
		var n = graph.node(selId);
		if (n == null)
		{
			secs.push({id: "none", title: "未选中节点", rows: [
				R3DShell.rowInfo("hint", "在画布里点一个节点方块即可编辑它的参数；点右侧圆点拉线到另一个节点的左侧圆点完成连线。", function() return ""),
				R3DShell.rowInfo("stat", "当前图统计", function()
				{
					return "节点 " + graph.nodes.length + "   连线 " + graph.links.length + "   采样器 " + graph.samplers().length;
				}),
				R3DShell.rowButton("fit2", "适应视图", fit),
				R3DShell.rowButton("pal2", "添加节点", function() { paletteOpen = true; })
			]});
			return secs;
		}
		var d = R3DMaterialGraph.def(n.type);
		var rows:Array<R3DRow> = [];
		rows.push(R3DShell.rowInfo("nid", "节点 #" + n.id + " · " + d.label, function() return "类型 " + n.type + "   输入 " + d.ins.length + "   输出 " + d.outs.length));
		rows.push(R3DShell.rowSlider("nx", "位置 X", -4000, 4000, 4, 0, function() return n.x, function(v:Float) n.x = v, rebuild));
		rows.push(R3DShell.rowSlider("ny", "位置 Y", -4000, 4000, 4, 0, function() return n.y, function(v:Float) n.y = v, rebuild));
		for (p in d.params)
		{
			var idx = d.params.indexOf(p);
			var pi = idx;
			if (n.type == "tex" && pi == 1)
				continue;
			rows.push(R3DShell.rowSlider("p" + pi, p, -8, 16, 0.01, 2, function()
			{
				return (n.v != null && pi < n.v.length) ? n.v[pi] : 0.0;
			}, function(v:Float)
			{
				while (n.v.length <= pi) n.v.push(0.0);
				n.v[pi] = v;
			}, apply));
		}
		if (n.type == "tex")
		{
			rows.push(R3DShell.rowInfo("texname", "当前贴图", function() return shortName(n.tex)));
			rows.push(R3DShell.rowButton("texopen", "选择贴图…", function() texPickFor = n.id));
			rows.push(R3DShell.rowButton("texclear", "清空贴图", function()
			{
				n.tex = "";
				apply();
			}));
		}
		rows.push(R3DShell.rowButton("ncopy", "复制节点", function()
		{
			var c = graph.addNode(n.type, n.x + 30, n.y + 30);
			c.v = n.v.copy();
			c.tex = n.tex;
			selId = c.id;
			rebuild();
		}));
		if (n.type != "output")
			rows.push(R3DShell.rowButton("ndel", "删除节点", function()
			{
				graph.removeNode(n.id);
				selId = graph.nodes.length > 0 ? graph.nodes[0].id : -1;
				rebuild();
				apply();
			}));
		secs.push({id: "node", title: "节点参数", rows: rows});

		var ls:Array<R3DRow> = [];
		var ins = [];
		for (i in 0...d.ins.length)
		{
			var ii = i;
			var lk = graph.linkAt(n.id, ii);
			ins.push("输入 " + ii + " · " + d.ins[ii] + " ← " + (lk == null ? "(空)" : ("#" + lk.from + "." + lk.fromSlot)));
		}
		ls.push(R3DShell.rowInfo("links", "连线状态", function() return ins.join("\n")));
		ls.push(R3DShell.rowButton("brk", "断开全部输入", function()
		{
			for (i in 0...d.ins.length) graph.disconnectTo(n.id, i);
			apply();
		}));
		secs.push({id: "links", title: "连线", rows: ls});
		return secs;
	}

	inline function mix2(a:Int, b:Int, t:Float):Int
	{
		return R3DUI.mix(a, b, t);
	}
}
