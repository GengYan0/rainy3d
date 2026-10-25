
package rainy.render3d.core;

import haxe.ds.StringMap;
import rainy.render3d.core.R3DModel;
import rainy.render3d.core.R3DMaterial;

enum abstract R3DCurveMode(Int) from Int to Int
{
	var CLAMP = 0;
	var LOOP = 1;
	var MIRROR = 2;
}

class R3DEase
{
	public static var table:StringMap<Float->Float> = build();

	static function build():StringMap<Float->Float>
	{
		var m = new StringMap<Float->Float>();
		m.set("linear", function(t:Float) return t);
		m.set("in", function(t:Float) return t * t);
		m.set("out", function(t:Float) return 1 - (1 - t) * (1 - t));
		m.set("inout", function(t:Float) return t < 0.5 ? 2 * t * t : 1 - 2 * (1 - t) * (1 - t));
		m.set("in3", function(t:Float) return t * t * t);
		m.set("out3", function(t:Float) return 1 - (1 - t) * (1 - t) * (1 - t));
		m.set("inout3", function(t:Float) return t < 0.5 ? 4 * t * t * t : 1 - 4 * (1 - t) * (1 - t) * (1 - t));
		m.set("smooth", function(t:Float) return t * t * (3 - 2 * t));
		m.set("smoother", function(t:Float) return t * t * t * (t * (t * 6 - 15) + 10));
		m.set("sine", function(t:Float) return 0.5 - 0.5 * Math.cos(Math.PI * t));
		m.set("back", function(t:Float)
		{
			var s = 1.70158;
			var u = t - 1;
			return u * u * ((s + 1) * u + s) + 1;
		});
		m.set("backin", function(t:Float)
		{
			var s = 1.70158;
			return t * t * ((s + 1) * t - s);
		});
		m.set("elastic", function(t:Float)
		{
			if (t <= 0) return 0;
			if (t >= 1) return 1;
			return Math.pow(2, -10 * t) * Math.sin((t * 10 - 0.75) * 2.0943951) + 1;
		});
		m.set("bounce", function(t:Float)
		{
			var n = 7.5625;
			var d = 2.75;
			var x = t;
			if (x < 1 / d) return n * x * x;
			if (x < 2 / d)
			{
				x -= 1.5 / d;
				return n * x * x + 0.75;
			}
			if (x < 2.5 / d)
			{
				x -= 2.25 / d;
				return n * x * x + 0.9375;
			}
			x -= 2.625 / d;
			return n * x * x + 0.984375;
		});
		return m;
	}

	public static function get(name:String):Float->Float
	{
		if (name == null) return null;
		var f = table.get(name);
		if (f != null) return f;
		return table.get("linear");
	}

	public static function apply(name:String, t:Float):Float
	{
		var f = get(name);
		return f == null ? t : f(t < 0 ? 0 : (t > 1 ? 1 : t));
	}

	public static var names:Array<String> = [
		"linear", "in", "out", "inout", "in3", "out3", "inout3",
		"smooth", "smoother", "sine", "back", "backin", "elastic", "bounce"
	];
}

class R3DKey
{
	public var t:Float;
	public var v:Float;
	public var ease:String = "smooth";

	public function new(t:Float, v:Float, ease:String = "smooth")
	{
		this.t = t;
		this.v = v;
		this.ease = ease;
	}
}

class R3DCurve
{
	public var keys:Array<R3DKey> = [];
	public var mode:R3DCurveMode = R3DCurveMode.CLAMP;
	public var label:String = "";

	public function new(?l:String)
	{
		if (l != null) label = l;
	}

	public function at(t:Float, v:Float, ease:String = "smooth"):R3DCurve
	{
		keys.push(new R3DKey(t, v, ease));
		keys.sort(function(a, b) return a.t < b.t ? -1 : (a.t > b.t ? 1 : 0));
		return this;
	}

	public function duration():Float
	{
		return keys.length == 0 ? 0 : keys[keys.length - 1].t;
	}

	public function first():Float
	{
		return keys.length == 0 ? 0 : keys[0].v;
	}

	public function last():Float
	{
		return keys.length == 0 ? 0 : keys[keys.length - 1].v;
	}

	public function sample(time:Float):Float
	{
		var n = keys.length;
		if (n == 0) return 0;
		if (n == 1) return keys[0].v;
		var d = duration();
		if (d <= 0) return keys[0].v;
		var t = wrap(time, d);
		if (t <= keys[0].t) return keys[0].v;
		if (t >= d) return keys[n - 1].v;
		var i = 1;
		while (i < n && keys[i].t < t) i++;
		var a = keys[i - 1];
		var b = keys[i];
		var span = b.t - a.t;
		var u = span <= 1e-6 ? 1.0 : (t - a.t) / span;
		u = R3DEase.apply(b.ease, u);
		return a.v + (b.v - a.v) * u;
	}

	function wrap(time:Float, d:Float):Float
	{
		if (time >= 0 && time <= d) return time;
		switch (mode)
		{
			case R3DCurveMode.LOOP:
				var t = time % d;
				return t < 0 ? t + d : t;
			case R3DCurveMode.MIRROR:
				var t = time % (d * 2);
				if (t < 0) t += d * 2;
				return t <= d ? t : d * 2 - t;
			default:
				return time < 0 ? 0 : d;
		}
	}
}

class R3DTrack
{
	public var target:Dynamic;
	public var path:String;
	public var curve:R3DCurve;
	public var weight:Float = 1;
	public var additive:Bool = false;
	public var onWrite:R3DModel->Void;

	var parts:Array<String> = null;
	var base:Float = 0;
	var bound:Bool = false;

	public function new(?c:R3DCurve)
	{
		curve = c == null ? new R3DCurve() : c;
	}

	public function bind(target:Dynamic, path:String):R3DTrack
	{
		this.target = target;
		this.path = path;
		parts = path == null ? null : path.split(".");
		bound = false;
		return this;
	}

	public function duration():Float
	{
		return curve == null ? 0 : curve.duration();
	}

	function hold():Dynamic
	{
		if (target == null || parts == null) return null;
		var o:Dynamic = target;
		var i = 0;
		while (i < parts.length - 1)
		{
			o = Reflect.field(o, parts[i]);
			if (o == null) return null;
			i++;
		}
		return o;
	}

	public function captureBase():Void
	{
		var o = hold();
		if (o == null) return;
		var v:Dynamic = Reflect.field(o, parts[parts.length - 1]);
		base = Std.isOfType(v, Float) ? (cast v : Float) : (Std.isOfType(v, Int) ? (cast v : Int) : 0);
		bound = true;
	}

	public function sample(time:Float):Void
	{
		if (target == null || parts == null || curve == null) return;
		var o = hold();
		if (o == null) return;
		if (!bound) captureBase();
		var v = curve.sample(time);
		var out = additive ? base + v * weight : (weight >= 1 ? v : base + (v - base) * weight);
		Reflect.setField(o, parts[parts.length - 1], out);
	}

	public function apply(time:Float):Void
	{
		sample(time);
		// `Reflect.setField` bypasses R3DModel's setters, so `worldDirty` has to be marked by
		// hand; `invalidate()` would also walk children that already pull their parent.
		if (Std.isOfType(target, R3DModel))
			(cast target : R3DModel).worldDirty = true;
		if (onWrite != null && Std.isOfType(target, R3DModel)) onWrite(cast target);
	}
}

class R3DAnimEvent
{
	public var t:Float;
	public var fn:Void->Void;
	public var once:Bool = false;
	public var fired:Bool = false;

	public function new(t:Float, fn:Void->Void, once:Bool = false)
	{
		this.t = t;
		this.fn = fn;
		this.once = once;
	}
}

class R3DClip
{
	public var name:String = "";
	public var tracks:Array<R3DTrack> = [];
	public var events:Array<R3DAnimEvent> = [];
	public var duration:Float = 0;
	public var loop:Bool = false;
	public var pingpong:Bool = false;

	public function new(?n:String)
	{
		if (n != null) name = n;
	}

	public function track(target:Dynamic, path:String, curve:R3DCurve):R3DTrack
	{
		var t = new R3DTrack(curve);
		t.bind(target, path);
		addTrack(t);
		return t;
	}

	public function addTrack(t:R3DTrack):R3DTrack
	{
		if (t == null) return null;
		tracks.push(t);
		refresh();
		return t;
	}

	public function at(t:Float, fn:Void->Void, once:Bool = true):R3DClip
	{
		events.push(new R3DAnimEvent(t, fn, once));
		refresh();
		return this;
	}

	public function refresh():Void
	{
		var d = 0.0;
		for (t in tracks)
			if (t.duration() > d) d = t.duration();
		for (e in events)
			if (e.t > d) d = e.t;
		duration = d;
	}

	public function reset():Void
	{
		for (e in events) e.fired = false;
	}

	public function apply(time:Float):Void
	{
		for (t in tracks) t.apply(time);
	}

	public function fire(time:Float, prev:Float, forward:Bool):Void
	{
		for (e in events)
		{
			if (e.fn == null) continue;
			var hit = forward ? (prev < e.t && time >= e.t) : (prev > e.t && time <= e.t);
			if (!hit) continue;
			if (e.once && e.fired) continue;
			e.fired = true;
			e.fn();
		}
	}
}

class R3DAnimPlayer
{
	public var clip:R3DClip;
	public var time:Float = 0;
	public var speed:Float = 1;
	public var playing:Bool = false;
	public var dir:Int = 1;
	public var onComplete:Void->Void;

	public function new(?c:R3DClip)
	{
		clip = c;
	}

	public function play(c:R3DClip = null, from:Float = 0):R3DAnimPlayer
	{
		if (c != null) clip = c;
		if (clip == null) return this;
		clip.reset();
		time = from;
		dir = 1;
		playing = true;
		clip.apply(time);
		return this;
	}

	public function stop():Void
	{
		playing = false;
	}

	public function seek(t:Float):Void
	{
		if (clip == null) return;
		time = t;
		clip.apply(time);
	}

	public function update(elapsed:Float):Void
	{
		if (!playing || clip == null) return;
		var d = clip.duration;
		if (d <= 0) return;
		var prev = time;
		time += elapsed * speed * dir;
		if (clip.pingpong && !clip.loop)
		{
			if (time > d)
			{
				time = d - (time - d);
				dir = -1;
			}
			else if (time < 0)
			{
				time = -time;
				dir = 1;
			}
			clip.fire(time, prev, dir > 0);
			clip.apply(time);
			return;
		}
		if (time >= d)
		{
			if (clip.loop)
			{
				time = d <= 0 ? 0 : time % d;
				clip.reset();
				clip.fire(time, prev, true);
				clip.apply(time);
				return;
			}
			time = d;
			clip.fire(time, prev, true);
			clip.apply(time);
			playing = false;
			if (onComplete != null) onComplete();
			return;
		}
		clip.fire(time, prev, true);
		clip.apply(time);
	}
}

class R3DAnim
{
	public static var players:Array<R3DAnimPlayer> = [];

	public static function player(?c:R3DClip):R3DAnimPlayer
	{
		var p = new R3DAnimPlayer(c);
		players.push(p);
		return p;
	}

	public static function update(elapsed:Float):Void
	{
		var i = 0;
		while (i < players.length)
		{
			var p = players[i];
			if (p == null)
			{
				players.splice(i, 1);
				continue;
			}
			p.update(elapsed);
			i++;
		}
		R3DFlipbook.updateAll(elapsed);
	}

	public static function clear():Void
	{
		players = [];
	}

	public static function curve():R3DCurve
	{
		return new R3DCurve();
	}

	public static function tween(target:Dynamic, path:String, from:Float, to:Float, dur:Float, ease:String = "smooth"):R3DClip
	{
		var c = new R3DCurve();
		c.at(0, from, "linear");
		c.at(dur, to, ease);
		var clip = new R3DClip(path);
		var t = clip.track(target, path, c);
		if (Std.isOfType(target, R3DModel))
		{
			var m:R3DModel = cast target;
			t.onWrite = function(mm:R3DModel) mm.worldDirty = true;
		}
		clip.refresh();
		return clip;
	}

	public static function easeNames():Array<String>
	{
		return R3DEase.names;
	}
}

class R3DFlipbook
{
	public static var flipbooks:Array<R3DFlipbook> = [];

	public var cols:Int = 1;
	public var rows:Int = 1;
	public var frameTime:Float = 0.1;
	public var loop:Bool = true;
	public var pingpong:Bool = false;
	public var vFlip:Bool = true;
	public var startIndex:Int = 0;
	public var endIndex:Int = -1;
	public var playing:Bool = false;
	public var time:Float = 0;
	public var frame:Int = 0;
	public var material:R3DMaterial;
	public var onComplete:Void->Void;

	public function new(?mat:R3DMaterial)
	{
		material = mat;
	}

	public function bind(mat:R3DMaterial):R3DFlipbook
	{
		material = mat;
		return this;
	}

	public static function make(cols:Int, rows:Int, frameTime:Float, ?mat:R3DMaterial):R3DFlipbook
	{
		var f = new R3DFlipbook(mat);
		f.cols = Std.int(Math.max(1, cols));
		f.rows = Std.int(Math.max(1, rows));
		f.frameTime = frameTime;
		flipbooks.push(f);
		return f;
	}

	public function play(from:Int = 0):R3DFlipbook
	{
		frame = from;
		time = 0;
		playing = true;
		apply();
		return this;
	}

	public function stop():R3DFlipbook
	{
		playing = false;
		return this;
	}

	public function seek(fr:Int):R3DFlipbook
	{
		frame = fr;
		apply();
		return this;
	}

	function frameTotal():Int
	{
		return cols * rows;
	}

	public function update(elapsed:Float):Void
	{
		if (!playing) return;
		var total = frameTotal();
		if (total <= 1) { apply(); return; }
		var last = (endIndex < 0 || endIndex >= total) ? total - 1 : endIndex;
		time += elapsed;
		var advanced = Math.floor(time / frameTime);
		if (advanced <= 0) return;
		time -= advanced * frameTime;
		var span = last - startIndex + 1;
		if (span <= 1) { apply(); return; }
		frame += advanced;
		if (frame <= last) { apply(); return; }
		if (!loop)
		{
			frame = last;
			playing = false;
			apply();
			if (onComplete != null) onComplete();
			return;
		}
		if (pingpong)
		{
			var period = 2 * (span - 1);
			var m = (frame - startIndex) % period;
			if (m < 0) m += period;
			frame = (m <= span - 1) ? (startIndex + m) : (last - (m - (span - 1)));
		}
		else
		{
			frame = startIndex + (((frame - startIndex) % span) + span) % span;
		}
		apply();
	}

	public function apply():Void
	{
		if (material == null) return;
		var total = frameTotal();
		var f = frame;
		if (f < 0) f = 0;
		if (f >= total) f = total - 1;
		var col = f % cols;
		var row = Std.int(f / cols);
		material.uvScaleU = 1.0 / cols;
		material.uvScaleV = 1.0 / rows;
		material.uvOffsetU = col / cols;
		material.uvOffsetV = vFlip ? (1.0 - (row + 1) / rows) : (row / rows);
	}

	public static function updateAll(elapsed:Float):Void
	{
		var i = 0;
		while (i < flipbooks.length)
		{
			var f = flipbooks[i];
			if (f == null) { flipbooks.splice(i, 1); continue; }
			f.update(elapsed);
			i++;
		}
	}

	public static function clearAll():Void
	{
		flipbooks = [];
	}
}
