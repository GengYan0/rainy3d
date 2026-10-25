package rainy.render3d.core;

import flixel.FlxG;
import openfl.geom.Vector3D;

class R3DEditorCore
{
	public var yaw:Float = -35;
	public var pitch:Float = 24;
	public var dist:Float = 12;
	public var distMin:Float = 0.6;
	public var distMax:Float = 400;
	public var target:Vector3D = new Vector3D(0, 1, 0);
	public var orbitSpeed:Float = 0.3;
	public var panSpeed:Float = 1.0;
	public var zoomStep:Float = 1.12;
	public var flySpeed:Float = 9;
	public var enabled:Bool = true;
	public var viewX:Float = 0;
	public var viewY:Float = 0;
	public var viewW:Float = 0;
	public var viewH:Float = 0;
	public var dirty:Bool = true;

	var _btn:Int = -1;
	var _mx:Float = 0;
	var _my:Float = 0;
	var _undo:Array<String> = [];
	var _redo:Array<String> = [];
	var _undoMax:Int = 40;

	public function new() {}

	public function setView(x:Float, y:Float, w:Float, h:Float):Void
	{
		viewX = x;
		viewY = y;
		viewW = w;
		viewH = h;
	}

	public function inView(mx:Float, my:Float):Bool
	{
		return viewW > 0 && viewH > 0 && mx >= viewX && mx <= viewX + viewW && my >= viewY && my <= viewY + viewH;
	}

	public function apply(cam:R3DCamera):Void
	{
		var cp = Math.cos(pitch * Math.PI / 180.0);
		var sp = Math.sin(pitch * Math.PI / 180.0);
		var cy = Math.cos(yaw * Math.PI / 180.0);
		var sy = Math.sin(yaw * Math.PI / 180.0);
		cam.x = target.x + sy * cp * dist;
		cam.y = target.y + sp * dist;
		cam.z = target.z + cy * cp * dist;
		cam.yaw = yaw;
		cam.pitch = pitch;
		cam.update();
	}

	public function frameAll(radius:Float, center:Vector3D):Void
	{
		if (radius < 0.5) radius = 0.5;
		target = center.clone();
		dist = Math.max(distMin, Math.min(distMax, radius * 2.6));
		dirty = true;
	}

	public function update(dt:Float):Void
	{
		if (!enabled) return;
		if (dt <= 0) dt = 1 / 60;
		var mx = FlxG.mouse.viewX;
		var my = FlxG.mouse.viewY;
		var inside = inView(mx, my);

		if (FlxG.mouse.justPressed && inside)
		{
			_btn = FlxG.mouse.pressedMiddle ? 2 : (FlxG.mouse.pressedRight ? 1 : 0);
			_mx = mx;
			_my = my;
		}

		if (FlxG.mouse.pressed && _btn >= 0)
		{
			var dx = mx - _mx;
			var dy = my - _my;
			_mx = mx;
			_my = my;
			if (dx != 0 || dy != 0)
			{
				if (_btn == 0 && !FlxG.keys.pressed.SHIFT)
				{
					yaw -= dx * orbitSpeed;
					pitch = Math.max(-88, Math.min(88, pitch + dy * orbitSpeed));
					dirty = true;
				}
				else
				{
					var k = dist * 0.0018 * panSpeed;
					var cy = Math.cos(yaw * Math.PI / 180.0);
					var sy = Math.sin(yaw * Math.PI / 180.0);
					target.x -= (cy * dx - sy * dy) * k;
					target.z += (sy * dx + cy * dy) * k;
					dirty = true;
				}
			}
		}

		if (!FlxG.mouse.pressed) _btn = -1;

		if (inside && FlxG.mouse.wheel != 0)
		{
			dist = Math.max(distMin, Math.min(distMax, dist * Math.pow(zoomStep, -FlxG.mouse.wheel)));
			dirty = true;
		}

		if (!inside) return;
		var f = 0.0;
		var s = 0.0;
		var u = 0.0;
		if (FlxG.keys.pressed.W) f += 1;
		if (FlxG.keys.pressed.S) f -= 1;
		if (FlxG.keys.pressed.D) s += 1;
		if (FlxG.keys.pressed.A) s -= 1;
		if (FlxG.keys.pressed.E) u += 1;
		if (FlxG.keys.pressed.Q) u -= 1;
		if (f == 0 && s == 0 && u == 0) return;

		var sp = Math.cos(pitch * Math.PI / 180.0);
		var sy = Math.sin(yaw * Math.PI / 180.0);
		var cy = Math.cos(yaw * Math.PI / 180.0);
		var step = flySpeed * dt * (FlxG.keys.pressed.SHIFT ? 3.0 : 1.0);
		target.x += (-sy * sp * f + cy * s) * step;
		target.z += (-cy * sp * f - sy * s) * step;
		target.y += u * step;
		dirty = true;
	}

	public function pushUndo(snapshot:String):Void
	{
		if (snapshot == null) return;
		if (_undo.length > 0 && _undo[_undo.length - 1] == snapshot) return;
		_undo.push(snapshot);
		if (_undo.length > _undoMax) _undo.shift();
		_redo = [];
	}

	public function undoSize():Int return _undo.length;
	public function redoSize():Int return _redo.length;

	public function undo(current:String):String
	{
		if (_undo.length < 1) return null;
		var prev = _undo.pop();
		if (current != null) _redo.push(current);
		return prev;
	}

	public function redo(current:String):String
	{
		if (_redo.length < 1) return null;
		var next = _redo.pop();
		if (current != null) _undo.push(current);
		return next;
	}

	public function clearHistory():Void
	{
		_undo = [];
		_redo = [];
	}

	public function orbit(yawDeg:Float = 0, pitchDeg:Float = 0, zoom:Float = 1):Void
	{
		yaw += yawDeg;
		pitch = Math.max(-88, Math.min(88, pitch + pitchDeg));
		dist = Math.max(distMin, Math.min(distMax, dist * zoom));
		dirty = true;
	}
}
