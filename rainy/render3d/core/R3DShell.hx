package rainy.render3d.core;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup;
import flixel.text.FlxText;
import openfl.display.BitmapData;
import openfl.geom.Rectangle;

typedef R3DRow = {
	var id:String;
	var label:String;
	var kind:String;
	var min:Float;
	var max:Float;
	var step:Float;
	var dec:Int;
	var get:Void->Float;
	var set:Float->Void;
	var ?act:Void->Void;
	var ?choices:Array<String>;
	var ?getStr:Void->String;
	var ?rgb:Void->Array<Float>;
	var ?setRgb:Array<Float>->Void;
}

typedef R3DSection = {
	var id:String;
	var title:String;
	var rows:Array<R3DRow>;
	var ?open:Bool;
	var ?hint:String;
}

class R3DShell extends FlxGroup
{
	public static inline var ROW_H:Int = 30;
	public static inline var TOOLBAR_H:Int = 40;
	public static inline var STATUS_H:Int = 24;
	public static inline var MENU_H:Int = 26;
	public static inline var TOOL_H:Int = 34;

	public var ui:R3DUI;
	public var overlay:FlxSprite;
	public var canvas:FlxSprite;
	public var bmd:BitmapData;
	public var labels:Array<FlxText> = [];

	public var railW:Float = 148;
	public var inspW:Float = 372;
	public var selRail:Int = 0;
	public var opened:Bool = false;
	public var mouseOverUi:Bool = false;

	public var leftW:Float = 308;
	public var rightW:Float = 266;
	public var consoleH:Float = 156;
	public var consoleOpen:Bool = true;
	public var consoleScroll:Float = 0;
	public var toolTips:Array<String> = [];
	var consoleVer:Int = -1;
	public var leftSplit:Float = 0.44;
	public var leftDivider:Float = 5;

	public var menuTitles:Array<String> = [];
	public var menuItems:Array<Array<String>> = [];
	public var hierScroll:Float = 0;
	public var projScroll:Float = 0;
	public var inspScroll:Float = 0;
	public var inspContentH:Float = 0;
	public var inspViewH:Float = 1;

	public var menuOpen:Int = -1;
	public var menuHover:Int = -1;
	public var popupX:Float = 0;
	public var popupY:Float = 0;
	public var popupOpen:Bool = false;

	var inspScroll2:Float = 0;
	var lastFrame:Int = 0;
	var frameNo:Int = 0;
	var tick:Int = 0;
	var clearN:Int = 0;
	var lastMx:Float = -1e9;
	var lastMy:Float = -1e9;
	var lastSx:Float = -1e9;
	var lastSy:Float = -1e9;
	var rcTmp:Rectangle = new Rectangle();

	public var liveRefresh:Float = 0.25;
	var liveT:Float = 0;
	public var poolSize:Int = 560;

	public static var drawLabels:Bool = true;

	public static var editorOpen:Int = 0;
	public static var statCalls:Int = 0;
	public static var statDraws:Int = 0;
	/** Frames where needsFrame() said "nothing changed". */
	public static var statSkips:Int = 0;
	/** Last branch that asked for a rebuild. */
	public static var lastReason:String = "-";

	public static var rDirty:Int = 0;
	public static var rStatus:Int = 0;
	public static var rPopup:Int = 0;
	public static var rCtx:Int = 0;
	public static var rMouse:Int = 0;
	public static var rWheel:Int = 0;
	public static var rMove:Int = 0;
	public static var rLive:Int = 0;
	public static var rNone:Int = 0;

	public static function reasonReset():Void
	{
		rDirty = rStatus = rPopup = rCtx = rMouse = rWheel = rMove = rLive = rNone = 0;
	}

	public static function reasonStr():String
	{
		return "原因 dirty=" + rDirty + " status=" + rStatus + " popup=" + rPopup + " ctx=" + rCtx + " mouse=" + rMouse + " wheel=" + rWheel
			+ " move=" + rMove + " live=" + rLive + " none=" + rNone;
	}
	var status:String = "";
	var statusT:Float = 0;
	var dirty:Bool = true;
	var hoverKey:String = "";
	var collapsed:Map<String, Bool> = new Map();
	var railItems:Array<String> = [];
	var railHit:Int = -1;
	var toolHit:Int = -1;
	var toolBarHit:Int = -1;
	var menuCmd:String = "";
	var popupHit:Int = -1;
	var ctxCmd:String = "";
	var popupOwner:String = "";
	var clearRects:Array<Float> = [];
	var prevRects:Array<Float> = [];
	var wheelTaken:Bool = false;
	var openMap:Map<String, Bool> = new Map();

	public function new()
	{
		super();
		ui = new R3DUI(null, labels);
		ui.grow = function() return growPool(32);
		visible = false;
	}

	public function ensureAlloc():Void
	{
		if (bmd != null) return;
		canvas = new FlxSprite(0, 0);
		bmd = new BitmapData(FlxG.width, FlxG.height, true, 0x00000000);
		// This bitmap is repainted in full on every rebuild, and its painter issues
		// hundreds of small fills. Each of those would otherwise cost two render-target
		// switches, so the fills go to the CPU buffer and the whole thing is uploaded
		// once, when the texture is next bound.
		bmd.__cpuFill = true;
		canvas.pixels = bmd;
		canvas.scrollFactor.set(0, 0);
		insert(0, canvas);
		ui.bmd = bmd;
		growPool(poolSize);
	}

	public function growPool(n:Int):Bool
	{
		if (bmd == null || n <= 0) return false;
		var fnt = R3DUI.fontName();
		for (i in 0...n)
		{
			var t = new FlxText(0, 0, 200, "");
			t.setFormat(fnt, 12, R3DUI.text, "left");
			t.wordWrap = false;
			t.scrollFactor.set(0, 0);
			t.visible = false;
			var at = labels.length + 1;
			if (at > length) at = length;
			labels.push(t);
			insert(at, t);
		}
		return true;
	}

	public function needsFrame():Bool
	{
		tick++;
		statCalls++;
		if (dirty) { rDirty++; lastReason = "dirty"; return true; }
		// A toast is static text: say() flags the frame that shows it and beginFrame()
		// flags the frame that drops it, so nothing here needs to force a rebuild in
		// between. Keeping the branch made a 3.6 s toast cost 3.6 s of full redraws.
		if (popupOpen || menuOpen >= 0) { rPopup++; lastReason = "popup"; return true; }
		if (ui.hasContext) { rCtx++; lastReason = "ctx"; return true; }
		if (FlxG.mouse.justPressed || FlxG.mouse.justPressedRight || FlxG.mouse.pressed || FlxG.mouse.pressedRight) { rMouse++; lastReason = "mouse"; return true; }
		if (FlxG.mouse.justReleased || FlxG.mouse.justReleasedRight) { rMouse++; lastReason = "release"; return true; }
		if (consoleOpen && R3DConsole.ver != consoleVer) { consoleVer = R3DConsole.ver; rLive++; lastReason = "console"; return true; }
		if (FlxG.mouse.wheel != 0) { rWheel++; lastReason = "wheel"; return true; }
		if (FlxG.mouse.screenX != lastSx || FlxG.mouse.screenY != lastSy) { rMove++; lastReason = "move"; return true; }
		if (liveRefresh > 0)
		{
			liveT += FlxG.elapsed;
			if (liveT >= liveRefresh) { liveT -= liveRefresh; rLive++; lastReason = "live"; return true; }
		}
		rNone++;
		statSkips++;
		lastReason = "-";
		return false;
	}

	public function say(msg:String):Void
	{
		status = msg;
		statusT = 3.6;
		dirty = true;
	}

	public function markDirty():Void
	{
		dirty = true;
	}

	public function railHeight():Float
	{
		var rail = railItems.length * 38;
		var top = TOOLBAR_H + 12;
		var max = Std.int((FlxG.height - top - STATUS_H - 12) / 38);
		if (railItems.length > max) rail = max * 38;
		return rail;
	}

	public function toolbarHeight():Float
	{
		return TOOLBAR_H;
	}

	function record(x:Float, y:Float, w:Float, h:Float):Void
	{
		clearRects[clearN] = x;
		clearRects[clearN + 1] = y;
		clearRects[clearN + 2] = w;
		clearRects[clearN + 3] = h;
		clearN += 4;
	}

	public function beginFrame():Void
	{
		ensureAlloc();
		frameNo++;
		statDraws++;
		if (bmd != null && clearN > 0)
		{
			// One unscissored clear: `fillRect` on a GPU-backed bitmap switches the render target
			// twice per call, and the layout is repainted right below anyway.
			rcTmp.setTo(0, 0, FlxG.width, FlxG.height);
			bmd.fillRect(rcTmp, 0x00000000);
		}
		clearN = 0;

		var mx = FlxG.mouse.viewX;
		var my = FlxG.mouse.viewY;
		lastMx = mx;
		lastMy = my;
		lastSx = FlxG.mouse.screenX;
		lastSy = FlxG.mouse.screenY;
		dirty = false;
		ui.begin(mx, my);
		wheelTaken = false;
		toolBarHit = -1;
		railHit = -1;
		toolHit = -1;
		popupHit = -1;
		menuCmd = "";
		ctxCmd = "";
		menuHover = -1;
		if (FlxG.mouse.wheel != 0) dirty = true;
		if (statusT > 0)
		{
			statusT -= FlxG.elapsed;
			// needsFrame() already forces a rebuild while a toast is showing, so setting
			// dirty here on top of that kept the whole UI in a permanent rebuild loop:
			// every frame ended flagged, and the next frame could never be skipped.
			// Only the transition back to the default status text needs a rebuild.
			if (statusT <= 0) dirty = true;
		}
	}

	public function endFrame():Void
	{
		if (!FlxG.mouse.pressed)
		{
			ui.active = "";
			if (popupOpen && !ui.overUi && FlxG.mouse.justPressed) popupOpen = false;
		}
		if (!FlxG.mouse.pressed && !FlxG.mouse.pressedRight && popupOpen) ui.active = "";
		ui.drawTip();
		ui.end();
		// Labels are rasterisers only in bitmap mode: their pixels are already in the
		// canvas, and leaving them visible would draw every string a second time and
		// bring back one draw call per label.
		if (!drawLabels || R3DUI.textAsBitmap)
		{
			var n = shownLabels();
			for (i in 0...n)
				labels[i].visible = false;
		}
	}

	inline function shownLabels():Int
	{
		return R3DUI.lastUsed < labels.length ? R3DUI.lastUsed : labels.length;
	}

	public function consoleHeight():Float
	{
		if (!consoleOpen) return 0;
		var max = (FlxG.height - MENU_H - TOOL_H - STATUS_H) * 0.7;
		var h = consoleH;
		if (h < 64) h = 64;
		if (h > max) h = max;
		return h;
	}

	public function viewportRect(out:Array<Float>):Array<Float>
	{
		var top = MENU_H + TOOL_H;
		var h = FlxG.height - top - STATUS_H - consoleHeight();
		out[0] = leftW;
		out[1] = top;
		out[2] = FlxG.width - leftW - rightW;
		out[3] = h;
		return out;
	}

	public function drawMenuBar(statusText:String):Void
	{
		record(0, 0, FlxG.width, MENU_H);
		rect(0, 0, FlxG.width, MENU_H, R3DUI.panel);
		ui.hline(0, MENU_H - 1, FlxG.width, R3DUI.line);
		rect(0, 0, 4, MENU_H, R3DUI.accent);
		var bx = 14.0;
		for (i in 0...(menuTitles.length))
		{
			var w = 16 + menuTitles[i].length * 14;
			var hot = ui.ghostButton("mn" + i, bx, 3, w, 20, menuTitles[i], 13, i == menuOpen ? R3DUI.accent2 : -1);
			if (hot)
			{
				if (menuOpen == i) menuOpen = -1;
				else
				{
					menuOpen = i;
					popupOpen = false;
					popupX = bx;
					popupY = MENU_H;
					ui.active = "";
				}
				dirty = true;
			}
			bx += w + 6;
		}
		if (statusT > 0)
			ui.txt(FlxG.width * 0.5, 6, status, R3DUI.ok, 12, "center", 520);
		else
			ui.txt(bx + 12, 6, statusText, R3DUI.dim, 12, "left", FlxG.width - bx - 24);
	}

	public function drawToolbar(names:Array<String>, on:Array<Bool>, size:Int = 13, dis:Array<Bool> = null):Int
	{
		record(0, MENU_H, FlxG.width, TOOL_H);
		rect(0, MENU_H, FlxG.width, TOOL_H, R3DUI.panel2);
		ui.hline(0, MENU_H + TOOL_H - 1, FlxG.width, R3DUI.line);
		var bx = 12.0;
		toolBarHit = -1;
		for (i in 0...(names.length))
		{
			if (names[i] == "|")
			{
				ui.vline(bx + 4, MENU_H + 6, TOOL_H - 13, R3DUI.line2);
				bx += 14;
				continue;
			}
			var w = 14 + names[i].length * (size - 1);
			var off = dis != null && i < dis.length && dis[i];
			var t = i < toolTips.length ? toolTips[i] : null;
			var hot = ui.ghostButton("tb" + i, bx, MENU_H + 5, w, TOOL_H - 11, names[i], size, -1, off, t);
			var col = off ? R3DUI.line : ((i < on.length && on[i]) ? R3DUI.accent : R3DUI.line2);
			ui.roundFrame(bx, MENU_H + 5, w, TOOL_H - 11, hot ? R3DUI.accent : col, 4);
			if (hot) toolBarHit = i;
			bx += w + 7;
		}
		return toolBarHit;
	}

	public function takeToolClick():Int
	{
		var h = toolBarHit;
		toolBarHit = -1;
		return h;
	}

	public function takeMenuCmd():String
	{
		var c = menuCmd;
		menuCmd = "";
		return c;
	}

	public function takeContextCmd():String
	{
		var c = ctxCmd;
		ctxCmd = "";
		return c;
	}

	public function panelBg(x:Float, y:Float, w:Float, h:Float, title:String, ?hint:String):Float
	{
		record(x, y, w, h);
		rect(x, y, w, h, R3DUI.panel);
		ui.rect(x, y, w, 24, R3DUI.panel2);
		ui.rect(x, y, 3, 24, R3DUI.accent);
		ui.txt(x + 12, y + 5, title, R3DUI.text, 13, "left", w - 20);
		ui.hline(x, y + 24, w, R3DUI.line);
		if (hint != null && hint.length > 0)
		{
			ui.txt(x + 12, y + h - 18, hint, R3DUI.dim, 11, "left", w - 20);
			return y + 30;
		}
		return y + 30;
	}

	public function scrollPanel(x:Float, y:Float, w:Float, h:Float, scroll:Float, contentH:Float):Float
	{
		var s = scroll;
		if (!wheelTaken && ui.wheelOver(x, y, w, h) && FlxG.mouse.wheel != 0)
		{
			s -= FlxG.mouse.wheel * 48;
			wheelTaken = true;
			dirty = true;
		}
		if (s < 0) s = 0;
		var max = Math.max(0, contentH - h);
		if (s > max) s = max;
		ui.setClip(x, y, w - 8, h);
		ui.scrollbar(x + w - 7, y, h, contentH, h, s);
		return s;
	}

	public function treeRow(id:String, x:Float, y:Float, w:Float, h:Float, label:String, sub:String, sel:Bool, indent:Float,
			hasKids:Bool, expanded:Bool, enabled:Bool):Int
	{
		var hot = ui.hoverTest(id, x, y, w, h);
		if (sel) rect(x, y, w, h, R3DUI.mix(R3DUI.panel2, R3DUI.accent, 0.32));
		else if (hot) rect(x, y, w, h, R3DUI.panel2);
		if (sel) rect(x, y, 3, h, R3DUI.accent);
		var ax = x + 8 + indent;
		var hit = 0;
		if (hasKids)
		{
			if (ui.ghostButton(id + "^", ax, y + (h - 16) * 0.5, 16, 16, expanded ? "-" : "+", 13)) hit = 2;
		}
		var bx = ax + (hasKids ? 20 : 6);
		var nameCol = enabled ? (sel ? 0xFFFFFFFF : R3DUI.text) : R3DUI.dim;
		if (sub != null && sub.length > 0)
		{
			ui.txt(bx, y + 3, label, nameCol, 13, "left", w - (bx - x) - 58);
			ui.txt(bx, y + h - 15, sub, R3DUI.dim, 11, "left", w - (bx - x) - 58);
		}
		else
			ui.txt(bx, y + (h - 13) * 0.5 - 1, label, nameCol, 13, "left", w - (bx - x) - 58);
		if (ui.ghostButton(id + "e", x + w - 52, y + (h - 16) * 0.5, 46, 16, enabled ? "on" : "off", 11)) hit = 3;
		if (hot && FlxG.mouse.justPressed && hit == 0) hit = 1;
		if (hot && FlxG.mouse.justPressedRight)
		{
			hit = 4;
			ctxCmd = "";
			ui.setContext(id, FlxG.mouse.viewX, FlxG.mouse.viewY);
		}
		return hit;
	}

	public function inspectorAt(x:Float, y:Float, w:Float, h:Float, sections:Array<R3DSection>, title:String):Bool
	{
		var changed = false;
		ui.txt(x + 12, y + 6, title, R3DUI.text, 14, "left", w - 24);
		ui.hline(x + 10, y + 26, w - 20, R3DUI.line);
		var viewY = y + 30;
		inspViewH = h - 36;
		var contentH = inspContentH;
		var sv = scrollPanel(x, viewY, w, inspViewH, inspScroll2, contentH);
		inspScroll2 = sv;
		var yy = viewY - sv;
		var rw = w - 34;
		for (s in sections)
		{
			var open = openMap.exists(s.id) ? openMap.get(s.id) : true;
			ui.setClip(x, viewY, w - 8, inspViewH);
			if (ui.sectionHeader("sec" + s.id, x + 10, yy, rw, s.title, open))
			{
				openMap.set(s.id, !open);
				open = !open;
				changed = true;
			}
			if (!open)
			{
				yy += 30;
				continue;
			}
			if (s.hint != null && s.hint.length > 0)
			{
				ui.txt(x + 20, yy + 4, s.hint, R3DUI.dim, 11, "left", rw - 20);
				yy += 22;
			}
			yy += 6;
			for (r in s.rows)
			{
				var ry = yy;
				ui.setClip(x, viewY, w - 8, inspViewH);
				switch (r.kind)
				{
					case "slider":
						var nv = ui.slider(r.id, x + 20, ry + 4, rw - 20, 24, r.label, r.get(), r.min, r.max, r.step, r.dec);
						if (nv != null)
						{
							r.set(nv);
							changed = true;
							if (r.act != null) runAct(r.act);
						}
						yy += ROW_H;
					case "toggle":
						var nv = ui.toggle(r.id, x + 20, ry + 2, rw - 20, 24, r.label, r.get() >= 0.5);
						if (nv != null)
						{
							r.set(nv ? 1 : 0);
							changed = true;
							if (r.act != null) runAct(r.act);
						}
						yy += ROW_H;
					case "color":
						var cur = r.rgb != null ? r.rgb() : [1.0, 1.0, 1.0];
						var nv = ui.colorRow(r.id, x + 20, ry + 4, rw - 20, r.label, cur[0], cur[1], cur[2], r.dec);
						if (nv != null && r.setRgb != null)
						{
							r.setRgb(nv);
							changed = true;
							if (r.act != null) runAct(r.act);
						}
						yy += ROW_H;
					case "button":
						if (ui.button(r.id, x + 20, ry + 2, rw - 20, 26, r.label, R3DUI.panel3))
						{
							changed = true;
							if (r.act != null) runAct(r.act);
						}
						yy += ROW_H + 2;
					case "info":
						ui.txt(x + 20, ry + 2, r.label, R3DUI.dim, 11, "left", rw - 20);
						var s2 = r.getStr != null ? r.getStr() : "";
						var lines = s2.split("\n");
						var li = 0;
						for (txtLine in lines)
						{
							ui.txt(x + 20, ry + 16 + li * 14, txtLine, R3DUI.text, 11, "left", rw - 20);
							li++;
						}
						yy += 18 + li * 14;
					case "stepper":
						var nv = ui.stepper(r.id, x + 20, ry + 3, rw - 20, 24, r.label, r.get(), r.step, r.dec, r.min, r.max);
						if (nv != null)
						{
							r.set(nv);
							changed = true;
							if (r.act != null) runAct(r.act);
						}
						yy += ROW_H;
					default:
						yy += ROW_H;
				}
			}
			yy += 10;
		}
		ui.clearClip();
		inspContentH = (yy + sv) - viewY + 16;
		return changed;
	}

	public function chrome(toolItems:Array<String>, rail:Array<String>, statusText:String = ""):Void
	{
		railItems = rail;
		if (statusT > 0) statusText = status + "        " + statusText;
		beginFrame();
		var mx = FlxG.mouse.viewX;
		var my = FlxG.mouse.viewY;
		var hovering = (mx >= FlxG.width - inspW) || (mx <= railW) || (my <= TOOLBAR_H) || (my >= FlxG.height - STATUS_H);

		record(0, 0, FlxG.width, TOOLBAR_H + STATUS_H + 2);
		record(0, TOOLBAR_H, railW, FlxG.height - TOOLBAR_H - STATUS_H);
		record(FlxG.width - inspW, TOOLBAR_H, inspW, FlxG.height - TOOLBAR_H - STATUS_H);

		rect(0, 0, FlxG.width, TOOLBAR_H, R3DUI.panel);
		ui.hline(0, TOOLBAR_H - 1, FlxG.width, R3DUI.line);
		ui.rect(0, 0, 4, TOOLBAR_H, R3DUI.accent);

		var bx = 14.0;
		for (i in 0...(toolItems.length))
		{
			var w = 14 + toolItems[i].length * 13;
			if (ui.ghostButton("tb" + i, bx, 8, w, 24, toolItems[i])) toolHit = i;
			bx += w + 8;
		}
		ui.txt(bx + 10, 12, statusT > 0 ? "" : statusText, R3DUI.dim, 12, "left", FlxG.width - inspW - bx - 20);

		rect(0, TOOLBAR_H, railW, FlxG.height - TOOLBAR_H - STATUS_H, R3DUI.panel);
		ui.vline(railW - 1, TOOLBAR_H, FlxG.height - TOOLBAR_H - STATUS_H, R3DUI.line);
		ui.txt(14, TOOLBAR_H + 12, "分类", R3DUI.dim, 12, "left", railW - 24);
		for (i in 0...(rail.length))
		{
			var y = TOOLBAR_H + 32 + i * 38;
			if (y + 34 > FlxG.height - STATUS_H) break;
			if (ui.railItem("rail" + i, 8, y, railW - 20, 34, rail[i], i == selRail)) railHit = i;
		}

		rect(FlxG.width - inspW, TOOLBAR_H, inspW, FlxG.height - TOOLBAR_H - STATUS_H, R3DUI.panel);
		ui.vline(FlxG.width - inspW, TOOLBAR_H, FlxG.height - TOOLBAR_H - STATUS_H, R3DUI.line);

		rect(0, FlxG.height - STATUS_H, FlxG.width, STATUS_H, R3DUI.panel);
		ui.hline(0, FlxG.height - STATUS_H, FlxG.width, R3DUI.line);
		ui.txt(12, FlxG.height - STATUS_H + 5, statusT > 0 ? status : statusText, statusT > 0 ? R3DUI.ok : R3DUI.dim, 12,
			"left", FlxG.width - 24);

		mouseOverUi = hovering || ui.overUi;
		if (railHit >= 0)
		{
			selRail = railHit;
			inspScroll = 0;
			inspScroll2 = 0;
			dirty = true;
		}
		endFrame();
	}

	public function inspector(sections:Array<R3DSection>, title:String):Bool
	{
		return inspectorAt(FlxG.width - inspW, TOOLBAR_H, inspW, FlxG.height - TOOLBAR_H - STATUS_H, sections, title);
	}

	public function rect(x:Float, y:Float, w:Float, h:Float, col:Int):Void
	{
		ui.rect(x, y, w, h, col);
	}

	public function runAct(a:Void->Void):Void
	{
		try
		{
			a();
		}
		catch (e:Dynamic)
		{
			say("操作异常: " + e);
		}
		dirty = true;
	}

	public function takeRailHit():Int
	{
		var h = railHit;
		railHit = -1;
		return h;
	}

	public function takeToolHit():Int
	{
		var h = toolHit;
		toolHit = -1;
		return h;
	}

	public function menuPopup(w:Float):Int
	{
		if (menuOpen < 0 || menuOpen >= menuItems.length) return -1;
		var items = menuItems[menuOpen];
		var h = items.length * 24 + 8;
		popupX = Math.min(popupX, FlxG.width - w - 6);
		record(popupX, popupY, w, h);
		rect(popupX - 1, popupY - 1, w + 2, h + 2, R3DUI.line2);
		rect(popupX, popupY, w, h, R3DUI.panel3);
		var hit = -1;
		for (i in 0...(items.length))
		{
			var y = popupY + 4 + i * 24;
			var hot = ui.hoverTest("mi" + i, popupX, y, w, 24);
			if (hot) rect(popupX, y, w, 24, R3DUI.accent);
			ui.txt(popupX + 12, y + 5, items[i], hot ? 0xFFFFFFFF : R3DUI.text, 13, "left", w - 20);
			if (hot && FlxG.mouse.justPressed) hit = i;
		}
		if (hit >= 0)
		{
			menuCmd = menuOpen + ":" + hit;
			menuOpen = -1;
			dirty = true;
		}
		else if (FlxG.mouse.justPressed && !ui.overUi) menuOpen = -1;
		return hit;
	}

	public function contextPopup(items:Array<String>, w:Float):Int
	{
		if (!ui.hasContext) return -1;
		var x = ui.ctxX;
		var y = ui.ctxY;
		var h = items.length * 24 + 8;
		if (x + w > FlxG.width) x = FlxG.width - w - 6;
		if (y + h > FlxG.height) y = FlxG.height - h - 6;
		record(x, y, w, h);
		rect(x - 1, y - 1, w + 2, h + 2, R3DUI.line2);
		rect(x, y, w, h, R3DUI.panel3);
		var hit = -1;
		for (i in 0...(items.length))
		{
			var iy = y + 4 + i * 24;
			var hot = ui.hoverTest("cx" + i, x, iy, w, 24);
			if (hot) rect(x, iy, w, 24, R3DUI.accent);
			ui.txt(x + 12, iy + 5, items[i], hot ? 0xFFFFFFFF : R3DUI.text, 13, "left", w - 20);
			if (hot && FlxG.mouse.justPressed) hit = i;
		}
		if (hit >= 0)
		{
			ctxCmd = "" + hit;
			ui.clearContext();
			dirty = true;
		}
		else if (FlxG.mouse.justPressed && !ui.overUi) ui.clearContext();
		return hit;
	}

	public function splitterLeft(x:Float):Bool
	{
		return ui.splitterV("spL", x, MENU_H + TOOL_H, FlxG.height - MENU_H - TOOL_H - STATUS_H);
	}

	public function splitterRight(x:Float):Bool
	{
		return ui.splitterV("spR", x, MENU_H + TOOL_H, FlxG.height - MENU_H - TOOL_H - STATUS_H);
	}

	public function splitterConsole(x:Float, y:Float, w:Float):Bool
	{
		return ui.splitterH("spC", x, y, w);
	}

	public function statusBar(parts:Array<String>, err:String):Void
	{
		record(0, FlxG.height - STATUS_H, FlxG.width, STATUS_H);
		rect(0, FlxG.height - STATUS_H, FlxG.width, STATUS_H, R3DUI.panel);
		ui.hline(0, FlxG.height - STATUS_H, FlxG.width, R3DUI.line);
		var total = 0;
		for (p in parts) total += p.length + 3;
		var w = FlxG.width / Math.max(1, parts.length);
		for (i in 0...(parts.length))
		{
			var col = (i == 0) ? R3DUI.text : R3DUI.dim;
			ui.txt(12 + i * w, FlxG.height - STATUS_H + 5, parts[i], col, 12, "left", w - 14);
			if (i > 0) ui.vline(6 + i * w, FlxG.height - STATUS_H + 4, STATUS_H - 8, R3DUI.line);
		}
		if (err != null && err.length > 0)
			ui.txt(12, FlxG.height - STATUS_H - 18, err, R3DUI.bad, 12, "left", FlxG.width - 24);
	}

	public static function rowSlider(id:String, label:String, min:Float, max:Float, step:Float, dec:Int, g:Void->Float,
			s:Float->Void, ?act:Void->Void):R3DRow
	{
		return {id: id, label: label, kind: "slider", min: min, max: max, step: step, dec: dec, get: g, set: s, act: act};
	}

	public static function rowToggle(id:String, label:String, g:Void->Float, s:Float->Void, ?act:Void->Void):R3DRow
	{
		return {id: id, label: label, kind: "toggle", min: 0, max: 1, step: 1, dec: 0, get: g, set: s, act: act};
	}

	public static function rowButton(id:String, label:String, act:Void->Void):R3DRow
	{
		return {id: id, label: label, kind: "button", min: 0, max: 1, step: 1, dec: 0, get: function() return 0,
			set: function(v:Float) {}, act: act};
	}

	public static function rowStepper(id:String, label:String, min:Float, max:Float, step:Float, dec:Int, g:Void->Float,
			s:Float->Void, ?act:Void->Void):R3DRow
	{
		return {id: id, label: label, kind: "stepper", min: min, max: max, step: step, dec: dec, get: g, set: s, act: act};
	}

	public static function rowColor(id:String, label:String, g:Void->Array<Float>, s:Array<Float>->Void,
			?act:Void->Void):R3DRow
	{
		return {id: id, label: label, kind: "color", min: 0, max: 1, step: 0.005, dec: 3, get: function() return 0,
			set: function(v:Float) {}, rgb: g, setRgb: s, act: act};
	}

	public static function rowInfo(id:String, label:String, g:Void->String):R3DRow
	{
		return {id: id, label: label, kind: "info", min: 0, max: 1, step: 1, dec: 0, get: function() return 0,
			set: function(v:Float) {}, getStr: g};
	}
}
