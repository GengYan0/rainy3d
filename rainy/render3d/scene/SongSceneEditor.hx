package rainy.render3d.scene;

import flixel.FlxG;
import openfl.geom.Vector3D;
import rainy.render3d.core.R3DCamera;
import rainy.render3d.core.R3DEditorCore;
import rainy.render3d.core.R3DScene;
import rainy.render3d.core.R3DShell;
import rainy.render3d.core.R3DShell.R3DSection;

class SongSceneEditor extends R3DShell
{
	public var onClose:Void->Void;
	public var core:R3DEditorCore = new R3DEditorCore();

	var page:Int = 0;
	var pages:Array<String> = ['场景', '相机', '灯光', '物体', '贴图'];
	var err:String = '';
	var pickIdx:Int = -1;
	var shownOnce:Bool = false;

	public function new()
	{
		super();
		menuTitles = ['文件', '视图', '帮助'];
		menuItems = [
			['保存配置', '重新加载', '关闭编辑器'],
			['相机归位', '框选全部', '重置缩放'],
			['JSON 路径', '快捷键', '关于']
		];
		toolTips = ['保存', '重载', '归位', '框选', '添加灯', '添加盒', '添加贴图', '页面'];
	}

	public function show():Void
	{
		visible = true;
		opened = true;
		if (!shownOnce)
		{
			shownOnce = true;
			syncCameraFromConfig();
		}
		refreshScene();
	}

	public function hide():Void
	{
		visible = false;
		opened = false;
		if (onClose != null) onClose();
	}

	public function toggle():Void
	{
		if (visible) hide() else show();
	}

	public function refreshScene():Void
	{
		var s = R3DSceneHost.scene();
		if (s == null)
		{
			err = R3DSceneHost.error();
			return;
		}
		err = '';
	}

	public function syncCameraFromConfig():Void
	{
		var x = num(R3DSceneHost.getPath('camera.x', 0));
		var y = num(R3DSceneHost.getPath('camera.y', 2));
		var z = num(R3DSceneHost.getPath('camera.z', 10));
		core.target.setTo(x, 1, z);
		var dx = x - 0;
		var dz = z - 0;
		core.dist = Math.max(1.2, Math.sqrt(dx * dx + dz * dz));
		if (z > 0) core.yaw = 0;
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);
		if (!visible) return;

		var s = R3DSceneHost.scene();
		var cam:R3DCamera = null;
		if (s != null)
		{
			try
				cam = s.views.length > 0 ? s.views[0] : null
			catch (e:Dynamic)
				cam = null;
		}

		handleTools();
		handleMenu();

		var vp:Array<Float> = [];
		viewportRect(vp);

		var title:String = '3D 场景 · ' + (R3DSceneHost.configPath() == null ? '(未挂载)' : R3DSceneHost.configPath());
		chrome(['保存', '重载', '归位', '框选', '加灯', '加盒', '加贴图'], pages, title);

		var secs = buildSections();
		var changed:Bool = inspector(secs, pages[page]);
		if (changed) dirty = true;

		statusBar([
			'页 ' + pages[page] + ' (' + (page + 1) + '/' + pages.length + ')',
			'相机 ' + r1(core.yaw) + '/' + r1(core.pitch) + ' 距 ' + r1(core.dist),
			'撤销 ' + core.undoSize() + ' 重做 ' + core.redoSize()
		], err);

		core.setView(vp[0], vp[1], vp[2], vp[3]);
		var overUi:Bool = mouseOverUi || !core.inView(FlxG.mouse.viewX, FlxG.mouse.viewY);
		core.enabled = !overUi;
		core.update(elapsed);

		if (cam != null)
		{
			core.apply(cam);
			if (!overUi && FlxG.mouse.justPressed)
			{
				pickIdx = pickAt(cam, FlxG.mouse.viewX, FlxG.mouse.viewY, vp);
				if (pickIdx >= 0 && pages[page] != '物体' && pages[page] != '贴图')
				{
					page = 3;
					refreshScene();
				}
			}
		}

		if (FlxG.keys.justPressed.ESCAPE) hide();
		if (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.Z) doUndo();
		if (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.Y) doRedo();
		if (FlxG.keys.justPressed.TAB)
		{
			page = (page + 1) % pages.length;
			dirty = true;
		}
	}

	function handleTools():Void
	{
		var hit:Int = takeToolClick();
		if (hit < 0) return;
		switch (hit)
		{
			case 0: doSave();
			case 1: doReload();
			case 2: syncCameraFromConfig();
			case 3: frameAll();
			case 4: addEntry('lights', '{"type":"POINT","x":2,"y":3,"z":2,"r":1,"g":1,"b":1,"energy":1.2,"range":9,"enabled":true}');
			case 5: addEntry('boxes', '{"x":0,"y":0.5,"z":0,"w":1,"h":1,"d":1,"solid":"0xB0B0B8"}');
			case 6: addEntry('sprites', '{"texture":"","w":1,"h":1,"x":0,"y":1,"z":0}');
			default:
		}
	}

	function handleMenu():Void
	{
		var cmd:String = takeMenuCmd();
		if (cmd == null || cmd.length < 1) return;
		switch (cmd)
		{
			case '保存配置': doSave();
			case '重新加载': doReload();
			case '关闭编辑器': hide();
			case '相机归位': syncCameraFromConfig();
			case '框选全部': frameAll();
			case '重置缩放': core.dist = 12;
			case 'JSON 路径': err = '路径: ' + R3DSceneHost.configPath();
			case '快捷键': err = '左键轨道 右键/Shift平移 滚轮缩放 WASD+QE 飞行 Tab 换页 Ctrl+Z/Y';
			case '关于': err = '按歌曲 3D 场景编辑器 · 存 songs/<song>/3dscene.json';
			default:
		}
	}

	public function doSave():Void
	{
		var ok:Bool = R3DSceneHost.save();
		err = ok ? ('已保存 ' + R3DSceneHost.configPath()) : ('保存失败: ' + R3DSceneHost.error());
		statusT = 2.0;
	}

	public function doReload():Void
	{
		var s = R3DSceneHost.reload();
		err = s == null ? ('重载失败: ' + R3DSceneHost.error()) : '已重载';
		statusT = 2.0;
		if (s != null) frameAll();
	}

	public function doUndo():Void
	{
		var cur:String = R3DSceneHost.snapshot();
		var prev:String = core.undo(cur);
		if (prev == null)
		{
			err = '没有可撤销的修改';
			return;
		}
		R3DSceneHost.restore(prev);
		R3DSceneHost.reload();
		err = '已撤销';
	}

	public function doRedo():Void
	{
		var cur:String = R3DSceneHost.snapshot();
		var next:String = core.redo(cur);
		if (next == null)
		{
			err = '没有可重做的修改';
			return;
		}
		R3DSceneHost.restore(next);
		R3DSceneHost.reload();
		err = '已重做';
	}

	function frameAll():Void
	{
		var cfg = R3DSceneHost.config();
		if (cfg == null) return;
		var c:Vector3D = new Vector3D(0, 1, 0);
		var radius:Float = 6;
		var boxes:Dynamic = R3DSceneHost.getPath('boxes');
		if (boxes != null && Std.isOfType(boxes, Array))
		{
			var arr:Array<Dynamic> = cast boxes;
			var mnx:Float = 1e9, mny:Float = 1e9, mnz:Float = 1e9;
			var mxx:Float = -1e9, mxy:Float = -1e9, mxz:Float = -1e9;
			for (b in arr)
			{
				var bx:Float = num(b == null ? null : Reflect.field(b, 'x'));
				var by:Float = num(b == null ? null : Reflect.field(b, 'y'));
				var bz:Float = num(b == null ? null : Reflect.field(b, 'z'));
				if (bx < mnx) mnx = bx;
				if (by < mny) mny = by;
				if (bz < mnz) mnz = bz;
				if (bx > mxx) mxx = bx;
				if (by > mxy) mxy = by;
				if (bz > mxz) mxz = bz;
			}
			if (mxx > -1e9)
			{
				c.setTo((mnx + mxx) * 0.5, (mny + mxy) * 0.5, (mnz + mxz) * 0.5);
				var dx:Float = mxx - mnx;
				var dy:Float = mxy - mny;
				var dz:Float = mxz - mnz;
				radius = Math.max(1.5, Math.sqrt(dx * dx + dy * dy + dz * dz) * 0.5);
			}
		}
		core.frameAll(radius, c);
	}

	function addEntry(key:String, json:String):Void
	{
		core.pushUndo(R3DSceneHost.snapshot());
		if (R3DSceneHost.appendEntry(key, json))
		{
			R3DSceneHost.reload();
			err = '已添加 ' + key;
			statusT = 2.0;
		}
		else
		{
			err = '添加失败: ' + R3DSceneHost.error();
		}
	}

	function pickAt(cam:R3DCamera, mx:Float, my:Float, vp:Array<Float>):Int
	{
		var cfg = R3DSceneHost.config();
		if (cfg == null || vp[2] < 1 || vp[3] < 1) return -1;
		var boxes:Dynamic = R3DSceneHost.getPath('boxes');
		if (boxes == null || !Std.isOfType(boxes, Array)) return -1;
		var arr:Array<Dynamic> = cast boxes;
		var nx:Float = (mx - vp[0]) / vp[2] * 2 - 1;
		var ny:Float = 1 - (my - vp[1]) / vp[3] * 2;
		var o:Array<Float> = unproject(cam, nx, ny, -1);
		var t:Array<Float> = unproject(cam, nx, ny, 1);
		if (o == null || t == null) return -1;
		var dx:Float = t[0] - o[0];
		var dy:Float = t[1] - o[1];
		var dz:Float = t[2] - o[2];
		var len:Float = Math.sqrt(dx * dx + dy * dy + dz * dz);
		if (len < 1e-6) return -1;
		dx /= len;
		dy /= len;
		dz /= len;

		var best:Int = -1;
		var bestT:Float = 1e9;
		var i:Int = 0;
		for (b in arr)
		{
			if (b == null)
			{
				i++;
				continue;
			}
			var bx:Float = num(Reflect.field(b, 'x'));
			var by:Float = num(Reflect.field(b, 'y'));
			var bz:Float = num(Reflect.field(b, 'z'));
			var hw:Float = num(Reflect.field(b, 'w'), 1) * 0.5;
			var hh:Float = num(Reflect.field(b, 'h'), 1) * 0.5;
			var hd:Float = num(Reflect.field(b, 'd'), 1) * 0.5;
			var tt:Float = rayBox(o[0], o[1], o[2], dx, dy, dz,
				bx - hw, by - hh, bz - hd, bx + hw, by + hh, bz + hd);
			if (tt >= 0 && tt < bestT)
			{
				bestT = tt;
				best = i;
			}
			i++;
		}
		return best;
	}

	static function unproject(cam:R3DCamera, nx:Float, ny:Float, nz:Float):Array<Float>
	{
		var m:Array<Float> = cam.invViewProj;
		if (m == null || m.length < 16) return null;
		var x:Float = m[0] * nx + m[4] * ny + m[8] * nz + m[12];
		var y:Float = m[1] * nx + m[5] * ny + m[9] * nz + m[13];
		var z:Float = m[2] * nx + m[6] * ny + m[10] * nz + m[14];
		var w:Float = m[3] * nx + m[7] * ny + m[11] * nz + m[15];
		if (w == 0) return null;
		return [x / w, y / w, z / w];
	}

	static function rayBox(ox:Float, oy:Float, oz:Float, dx:Float, dy:Float, dz:Float,
		x0:Float, y0:Float, z0:Float, x1:Float, y1:Float, z1:Float):Float
	{
		var tmin:Float = -1e9;
		var tmax:Float = 1e9;
		var lo:Array<Float> = [x0, y0, z0];
		var hi:Array<Float> = [x1, y1, z1];
		var o:Array<Float> = [ox, oy, oz];
		var d:Array<Float> = [dx, dy, dz];
		for (k in 0...3)
		{
			if (Math.abs(d[k]) < 1e-8)
			{
				if (o[k] < lo[k] || o[k] > hi[k]) return -1;
			}
			else
			{
				var ta:Float = (lo[k] - o[k]) / d[k];
				var tb:Float = (hi[k] - o[k]) / d[k];
				if (ta > tb)
				{
					var tmp:Float = ta;
					ta = tb;
					tb = tmp;
				}
				if (ta > tmin) tmin = ta;
				if (tb < tmax) tmax = tb;
				if (tmin > tmax) return -1;
			}
		}
		return tmin < 0 ? (tmax < 0 ? -1 : 0) : tmin;
	}

	function buildSections():Array<R3DSection>
	{
		var out:Array<R3DSection> = [];
		var pg:String = pages[page];

		if (pg == '场景')
		{
			out.push({
				id: 'env',
				title: '环境',
				open: true,
				rows: [
					R3DShell.rowColor('clear', '背景色', function() return rgbOf('clear', 0x101014),
						function(v) edit('clear', colorToInt(v))),
					R3DShell.rowSlider('ambR', '环境光 R', 0, 2, 0.01, 2, function() return g('ambient.r', 0.35),
						function(v) edit('ambient.r', v)),
					R3DShell.rowSlider('ambG', '环境光 G', 0, 2, 0.01, 2, function() return g('ambient.g', 0.35),
						function(v) edit('ambient.g', v)),
					R3DShell.rowSlider('ambB', '环境光 B', 0, 2, 0.01, 2, function() return g('ambient.b', 0.42),
						function(v) edit('ambient.b', v)),
					R3DShell.rowSlider('specP', '高光指数', 1, 64, 1, 0, function() return g('ambient.specPow', 16),
						function(v) edit('ambient.specPow', v))
				]
			});
			out.push({
				id: 'fog',
				title: '雾',
				open: true,
				rows: [
					R3DShell.rowSlider('fogS', '起点', 0, 200, 0.5, 1, function() return g('fog.start', 18),
						function(v) edit('fog.start', v)),
					R3DShell.rowSlider('fogE', '终点', 0, 400, 1, 1, function() return g('fog.end', 60),
						function(v) edit('fog.end', v)),
					R3DShell.rowColor('fogC', '雾色', function() return rgbOf('fog', 0x0A0A12),
						function(v) editFogColor(v))
				]
			});
			out.push({
				id: 'sky',
				title: '天空盒',
				open: false,
				rows: [
					R3DShell.rowToggle('skyOn', '启用', function() return g('skybox.enabled', 0),
						function(v) edit('skybox.enabled', v > 0.5)),
					R3DShell.rowSlider('skyI', '强度', 0, 3, 0.05, 2, function() return g('skybox.intensity', 1),
						function(v) edit('skybox.intensity', v)),
					R3DShell.rowButton('skyLoad', '从 folder 加载', function()
					{
						var f = R3DSceneHost.getPath('skybox.folder', '');
						err = f == null || Std.string(f).length < 1 ? '先设置 folder' : ('folder=' + Std.string(f));
					})
				]
			});
		}
		else if (pg == '相机')
		{
			out.push({
				id: 'cam',
				title: '轨道相机',
				open: true,
				rows: [
					R3DShell.rowStepper('cYaw', '偏航', -180, 180, 1, 1, function() return core.yaw,
						function(v) { core.yaw = v; }),
					R3DShell.rowStepper('cPit', '俯仰', -88, 88, 1, 1, function() return core.pitch,
						function(v) { core.pitch = v; }),
					R3DShell.rowSlider('cDst', '距离', core.distMin, core.distMax, 0.1, 2,
						function() return core.dist, function(v) { core.dist = v; }),
					R3DShell.rowStepper('cTX', '焦点 X', -200, 200, 0.1, 2, function() return core.target.x,
						function(v) { core.target.x = v; }),
					R3DShell.rowStepper('cTY', '焦点 Y', -200, 200, 0.1, 2, function() return core.target.y,
						function(v) { core.target.y = v; }),
					R3DShell.rowStepper('cTZ', '焦点 Z', -200, 200, 0.1, 2, function() return core.target.z,
						function(v) { core.target.z = v; })
				]
			});
			out.push({
				id: 'camCfg',
				title: '配置相机',
				open: true,
				rows: [
					R3DShell.rowSlider('fov', 'FOV', 20, 120, 1, 0, function() return g('camera.fov', 55),
						function(v) edit('camera.fov', v)),
					R3DShell.rowSlider('near', '近裁剪', 0.01, 5, 0.01, 2, function() return g('camera.near', 0.05),
						function(v) edit('camera.near', v)),
					R3DShell.rowSlider('far', '远裁剪', 10, 500, 5, 0, function() return g('camera.far', 80),
						function(v) edit('camera.far', v)),
					R3DShell.rowButton('camSync', '把当前相机写入配置', function()
					{
						var s = R3DSceneHost.scene();
						if (s == null) return;
						var c:R3DCamera = null;
						try
							c = s.views.length > 0 ? s.views[0] : null
						catch (e:Dynamic)
							c = null;
						if (c == null) return;
						core.pushUndo(R3DSceneHost.snapshot());
						edit('camera.x', c.x);
						edit('camera.y', c.y);
						edit('camera.z', c.z);
						err = '相机已写入配置';
					})
				]
			});
		}
		else if (pg == '灯光')
		{
			var arr:Array<Dynamic> = cast R3DSceneHost.getPath('lights', []);
			if (arr == null || arr.length < 1)
				out.push({id: 'noL', title: '灯光', open: true, rows: [
					R3DShell.rowButton('addL', '添加一个点光', function()
						addEntry('lights', '{"type":"POINT","x":2,"y":3,"z":2,"r":1,"g":1,"b":1,"energy":1.2,"range":9,"enabled":true}')
					)
				]});
			else
			{
				var i:Int = 0;
				for (L in arr)
				{
					var idx:Int = i;
					var nm:String = L == null ? ('灯 ' + i) : Std.string(Reflect.field(L, 'name'));
					if (nm == 'null' || nm.length < 1) nm = '灯 ' + i;
					out.push({
						id: 'l' + i,
						title: nm + ' #' + i,
						open: i == 0,
						rows: [
							R3DShell.rowSlider('lE' + i, '能量', 0, 8, 0.05, 2, function() return g('lights.' + idx + '.energy', 1),
								function(v) lightEdit(idx, 'energy', v)),
							R3DShell.rowSlider('lR' + i, '范围', 0.5, 80, 0.5, 1, function() return g('lights.' + idx + '.range', 8),
								function(v) lightEdit(idx, 'range', v)),
							R3DShell.rowSlider('lX' + i, 'X', -100, 100, 0.1, 2, function() return g('lights.' + idx + '.x', 0),
								function(v) lightEdit(idx, 'x', v)),
							R3DShell.rowSlider('lY' + i, 'Y', -100, 100, 0.1, 2, function() return g('lights.' + idx + '.y', 0),
								function(v) lightEdit(idx, 'y', v)),
							R3DShell.rowSlider('lZ' + i, 'Z', -100, 100, 0.1, 2, function() return g('lights.' + idx + '.z', 0),
								function(v) lightEdit(idx, 'z', v)),
							R3DShell.rowToggle('lOn' + i, '启用', function() return g('lights.' + idx + '.enabled', 1),
								function(v) lightEdit(idx, 'enabled', v > 0.5)),
							R3DShell.rowButton('lDel' + i, '删除这盏灯', function() removeEntry('lights', idx))
						]
					});
					i++;
				}
			}
		}
		else if (pg == '物体')
		{
			var arr:Array<Dynamic> = cast R3DSceneHost.getPath('boxes', []);
			if (arr == null || arr.length < 1)
				out.push({id: 'noB', title: '盒子', open: true, rows: [
					R3DShell.rowButton('addB', '添加一个盒子', function()
						addEntry('boxes', '{"x":0,"y":0.5,"z":0,"w":1,"h":1,"d":1,"solid":"0xB0B0B8"}')
					)
				]});
			else
			{
				var i:Int = 0;
				for (B in arr)
				{
					var idx:Int = i;
					out.push({
						id: 'b' + i,
						title: '盒子 #' + i + (pickIdx == i ? '  ← 选中' : ''),
						open: i == 0 || pickIdx == i,
						rows: [
							R3DShell.rowSlider('bX' + i, 'X', -100, 100, 0.05, 2, function() return g('boxes.' + idx + '.x', 0),
								function(v) edit('boxes.' + idx + '.x', v)),
							R3DShell.rowSlider('bY' + i, 'Y', -100, 100, 0.05, 2, function() return g('boxes.' + idx + '.y', 0),
								function(v) edit('boxes.' + idx + '.y', v)),
							R3DShell.rowSlider('bZ' + i, 'Z', -100, 100, 0.05, 2, function() return g('boxes.' + idx + '.z', 0),
								function(v) edit('boxes.' + idx + '.z', v)),
							R3DShell.rowSlider('bW' + i, '宽', 0.05, 60, 0.05, 2, function() return g('boxes.' + idx + '.w', 1),
								function(v) edit('boxes.' + idx + '.w', v)),
							R3DShell.rowSlider('bH' + i, '高', 0.05, 60, 0.05, 2, function() return g('boxes.' + idx + '.h', 1),
								function(v) edit('boxes.' + idx + '.h', v)),
							R3DShell.rowSlider('bD' + i, '深', 0.05, 60, 0.05, 2, function() return g('boxes.' + idx + '.d', 1),
								function(v) edit('boxes.' + idx + '.d', v)),
							R3DShell.rowColor('bC' + i, '颜色', function() return rgbOf('boxes.' + idx + '.solid', 0xB0B0B8),
								function(v) edit('boxes.' + idx + '.solid', colorToInt(v))),
							R3DShell.rowButton('bDel' + i, '删除这个盒子', function() removeEntry('boxes', idx))
						]
					});
					i++;
				}
			}
		}
		else
		{
			var arr:Array<Dynamic> = cast R3DSceneHost.getPath('sprites', []);
			if (arr == null || arr.length < 1)
				out.push({id: 'noS', title: '贴图', open: true, rows: [
					R3DShell.rowButton('addS', '添加一张贴图', function()
						addEntry('sprites', '{"texture":"","w":1,"h":1,"x":0,"y":1,"z":0}')
					)
				]});
			else
			{
				var i:Int = 0;
				for (S in arr)
				{
					var idx:Int = i;
					out.push({
						id: 's' + i,
						title: '贴图 #' + i,
						open: i == 0,
						rows: [
							R3DShell.rowInfo('sK' + i, '贴图', function() return Std.string(R3DSceneHost.getPath('sprites.' + idx + '.texture', ''))),
							R3DShell.rowSlider('sX' + i, 'X', -100, 100, 0.05, 2, function() return g('sprites.' + idx + '.x', 0),
								function(v) edit('sprites.' + idx + '.x', v)),
							R3DShell.rowSlider('sY' + i, 'Y', -100, 100, 0.05, 2, function() return g('sprites.' + idx + '.y', 0),
								function(v) edit('sprites.' + idx + '.y', v)),
							R3DShell.rowSlider('sZ' + i, 'Z', -100, 100, 0.05, 2, function() return g('sprites.' + idx + '.z', 0),
								function(v) edit('sprites.' + idx + '.z', v)),
							R3DShell.rowSlider('sW' + i, '宽', 0.05, 60, 0.05, 2, function() return g('sprites.' + idx + '.w', 1),
								function(v) edit('sprites.' + idx + '.w', v)),
							R3DShell.rowSlider('sH' + i, '高', 0.05, 60, 0.05, 2, function() return g('sprites.' + idx + '.h', 1),
								function(v) edit('sprites.' + idx + '.h', v)),
							R3DShell.rowSlider('sR' + i, '朝向', -180, 180, 1, 0, function() return g('sprites.' + idx + '.rotY', 0),
								function(v) edit('sprites.' + idx + '.rotY', v)),
							R3DShell.rowButton('sDel' + i, '删除这张贴图', function() removeEntry('sprites', idx))
						]
					});
					i++;
				}
			}
		}

		out.push({
			id: 'act',
			title: '操作',
			open: true,
			rows: [
				R3DShell.rowButton('saveNow', '保存到磁盘', doSave),
				R3DShell.rowButton('reloadNow', '重新加载', doReload)
			]
		});
		return out;
	}

	function edit(path:String, v:Dynamic):Void
	{
		R3DSceneHost.setPath(path, v);
		R3DSceneHost.refreshLive();
		dirty = true;
	}

	function lightEdit(idx:Int, key:String, v:Dynamic):Void
	{
		edit('lights.' + idx + '.' + key, v);
	}

	function editFogColor(v:Array<Float>):Void
	{
		var c:Int = colorToInt(v);
		edit('fog.r', ((c >> 16) & 0xFF) / 255.0);
		edit('fog.g', ((c >> 8) & 0xFF) / 255.0);
		edit('fog.b', (c & 0xFF) / 255.0);
	}

	function removeEntry(key:String, idx:Int):Void
	{
		core.pushUndo(R3DSceneHost.snapshot());
		if (R3DSceneHost.removeEntry(key, idx))
		{
			R3DSceneHost.reload();
			pickIdx = -1;
			err = '已删除 ' + key + '[' + idx + ']';
		}
		else
			err = '删除失败: ' + R3DSceneHost.error();
	}

	function g(path:String, def:Float):Float
	{
		return num(R3DSceneHost.getPath(path, def), def);
	}

	static function num(v:Dynamic, def:Float = 0):Float
	{
		if (v == null) return def;
		if (Std.isOfType(v, Float)) return cast v;
		if (Std.isOfType(v, Int)) return cast v;
		var f:Null<Float> = Std.parseFloat(Std.string(v));
		return f == null ? def : f;
	}

	static function r1(v:Float):Float
	{
		return Math.round(v * 10) / 10;
	}

	static function colorToInt(rgb:Array<Float>):Int
	{
		if (rgb == null || rgb.length < 3) return 0xFFFFFF;
		var r:Int = Std.int(Math.max(0, Math.min(1, rgb[0])) * 255);
		var g:Int = Std.int(Math.max(0, Math.min(1, rgb[1])) * 255);
		var b:Int = Std.int(Math.max(0, Math.min(1, rgb[2])) * 255);
		return (r << 16) | (g << 8) | b;
	}

	static function rgbOf(path:String, def:Int):Array<Float>
	{
		var v:Dynamic = R3DSceneHost.getPath(path);
		var c:Int = def;
		if (v != null)
		{
			if (Std.isOfType(v, Int)) c = cast v;
			else if (Std.isOfType(v, String))
			{
				var s:String = cast v;
				if (StringTools.startsWith(s, '0x') || StringTools.startsWith(s, '0X')) s = s.substr(2);
				if (StringTools.startsWith(s, '#')) s = s.substr(1);
				var p:Null<Int> = Std.parseInt('0x' + s);
				if (p != null) c = p;
			}
		}
		return [((c >> 16) & 0xFF) / 255.0, ((c >> 8) & 0xFF) / 255.0, (c & 0xFF) / 255.0];
	}
}
