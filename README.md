# rainy3d

基于 Stage3D 的 3D 渲染器，作为 flixel 的一个 `FlxSprite` 挂在场景里。含场景图、光照、
阴影、SSAO、模型导入、后处理链与相机机位。

## 能力

| 区域 | 内容 |
|---|---|
| 场景 | `R3DScene`、`R3DSceneGraph` 父子层级、`R3DStage` |
| 相机 | `R3DCamera` 透视/正交、yaw/pitch、视锥平面、多机位 |
| 几何 | `R3DMesh`、`R3DGeom`（box / quad / ring / 旋转盒）、16 位索引分桶 |
| 材质 | `R3DMaterial` 颜色、混合、剔除、深度、粗糙度/金属度、贴图槽 |
| 光照 | `R3DLight` 点光/平行光/聚光、`R3DLightRig`、`R3DShadow` |
| 环境 | `R3DSkybox`、`R3DCubemap` |
| 后处理 | `R3DPost` 链、`R3DPresent`（含 Lanczos 缩放）、`R3DAA`、`R3DSSAO` |
| 导入 | `ObjLoader`、`GlbLoader`、`AssetLibrary` 资产扫描 |
| 编辑 | `R3DPick` 射线拾取、`R3DGizmo` 三轴拖拽、`R3DEditorCore` |
| 合批 | `R3DBatch.bake()` 静态合批、`R3DInst` 实例化 |
| 动画 | `R3DAnim` 剪辑、`R3DSkeleton` 蒙皮、`R3DFlipbook` 序列帧 |

## 安装

```xml
<haxelib name="rainy3d"/>
```

```bash
haxelib git rainy3d https://github.com/GengYan0/rainy3d
```

依赖 `flixel` 6.2.0、`openfl` 9.5.2、`lime` 8.3.2。渲染需要 Stage3D 上下文，
`R3DCaps` 在上传任何东西之前就能报告上下文实际支持什么。

## 最小场景

```haxe
import rainy.render3d.core.R3D;
import rainy.render3d.core.R3DScene;
import rainy.render3d.core.R3DCamera;
import rainy.render3d.core.R3DTexture;

class ShopScene extends FlxState
{
	var scene:R3DScene;
	var cam:R3DCamera;

	override function create()
	{
		super.create();

		R3D.init();

		scene = R3D.scene(1920, 1080);
		add(scene);

		cam = R3D.camera(0, 1.6, 4, scene);   // x, y, z，自动挂到场景上
		cam.fov = 50;

		var mat = R3D.material(R3DTexture.fromFile('assets/images/wall.png'));
		var mesh = R3D.box(2, 2, 2, mat);
		var crate = R3D.model(mesh, 'crate');

		crate.setPosition(0, 1, 0);
		scene.add(crate);
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		// 绕场一周
		cam.x = Math.cos(haxe.Timer.stamp() * 0.3) * 5;
		cam.z = Math.sin(haxe.Timer.stamp() * 0.3) * 5;
		cam.yaw = Math.atan2(-cam.x, -cam.z) * 180 / Math.PI;
	}
}
```

`R3DScene` 继承 `FlxSprite`，`add(scene)` 之后由 flixel 的绘制流程驱动，不需要手动调渲染。

## 手动搭建几何

`R3D` 的门面适合快速起场景；要精确控制时直接拼 `R3DGeom`：

```haxe
var geom = new R3DGeom('counter');
geom.box(0, 0, 0, 3.0, 1.1, 0.9);              // 台面
geom.box(0, -0.6, 0, 2.6, 1.0, 0.7);           // 柜体
geom.boxRot(0, 1.3, -0.2, 1.2, 0.05, 0.5, 12, 0, 0);  // 倾斜的隔板

var mesh = new R3DMesh();
mesh.setArrays(geom.positions, geom.uvs, geom.indices, mat, geom.normals);

var model = new R3DModel(0, 0, 0);
model.addMesh(mesh);
scene.add(model);
```

`setArrays` 的 `indices` 是 `Array<Int>`，进 GPU 时压成 16 位。单网格顶点超过 65535 时
`R3DBatch.bake()` 会按 65000 分桶，`setArrays()` 遇到必须截断的情况会打警告。

## 层级

```haxe
var cabinet = R3D.model(R3D.box(1.2, 2.0, 0.6, mat), 'cabinet');
var drawer = R3D.model(R3D.box(1.0, 0.4, 0.5, mat), 'drawer');

drawer.parent = cabinet;         // 父级移动，子级跟随
cabinet.setPosition(0, 1, -3);
drawer.setPosition(0, -0.4, 0.05);
```

父级变换在子级之前更新，`worldDirty` 会沿链传播。

## 光照

```haxe
var rig = R3D.rig();

var sun = new R3DLight('sun');
sun.type = R3DLightType.DIRECTIONAL;
sun.setDir(-0.4, -1, -0.3).setColor(1, 0.97, 0.92);
sun.energy = 0.9;
rig.lights.push(sun);

var fill = new R3DLight('fill');
fill.type = R3DLightType.POINT;
fill.setPos(0, 2.5, 0).setColor(1.0, 0.86, 0.7);
fill.range = 6;
rig.lights.push(fill);

rig.ambientR = rig.ambientG = rig.ambientB = 0.04;
rig.fogStart = 8;
rig.fogEnd = 24;
```

单独加一盏投影灯：

```haxe
var spot = new R3DLight('counterSpot');
spot.type = R3DLightType.SPOT;
spot.setPos(0, 2.2, -2.5).aimAt(0, 1.0, -3).energy = 1.4;
spot.castShadow = true;
spot.range = 7;
rig.lights.push(spot);
```

`R3DLight` 可以序列化：

```haxe
var json = spot.toJson();
var back = R3DLight.fromJson(json);
```

## 阴影

```haxe
var shadow = new R3DShadow(sun);   // 指定哪盏灯投影
shadow.resize(1024);               // 夹在 128..4096
scene.shadow = shadow;
```

阴影贴图尺寸受 `GL_MAX_TEXTURE_SIZE` 限制，`resize` 会把值夹到上限。

## 后处理

效果按场景开关，不是全局：

```haxe
var n = scene.enablePost({
	bloom: true,
	vignette: true,
	superSample: 1.5
});
trace('$n pass(es)');

scene.disablePost();
```

单独挂一条 pass：

```haxe
var chain = new R3DPostChain('shop');
var pass = new R3DPostPass('scanline', R3DShader.fromSources(VERT, FRAG, null));
pass.set('uStrength', 0.4).setVec2('uResolution', 1920, 1080);
chain.add(pass);
```

## 抗锯齿与缩放

```haxe
var aa = new R3DAA();                 // 单 pass 边缘定向
var out = aa.apply(src, 1920, 1080);
trace(aa.passes);
```

`R3DAAMode` 只有 `OFF` 与 `FXAA` 两个值，字符串 `'fxaa'` / `'on'` 可以直接赋值。

`R3DPresent` 把场景纹理縮放到显示尺寸：

```haxe
R3DPresent.mode = R3DPresentMode.FSR;   // OFF / BILINEAR / BOX / FSR / FSR_SHARP

var present = new R3DPresent();
var display = present.apply(src, 1920, 1080);
trace(present.info());
```

`FSR` 走方向自适应重建：取十六个源像素，用结构张量找主边缘方向，沿该方向拉长的
Lanczos-2 核采样，边缘保持斜率而不是变成台阶。`BOX` 是面积平均，适合超采样后降采样。

## SSAO

```haxe
if (R3DSSAO.available())
{
	R3DSSAO.enabled = true;
	R3DSSAO.radius = 0.6;
	trace(R3DSSAO.status());
}
```

SSAO 需要深度纹理，场景会自动打开 `depthTextureEnabled`。

## 模型导入

OBJ：

```haxe
var data = ObjLoader.load('assets/3d/chair.obj');
var mesh = new R3DMesh();
mesh.setArrays(data.positions, data.uvs, data.indices, mat, data.normals);

var chair = new R3DModel(0, 0, -2);
chair.addMesh(mesh);
scene.add(chair);
```

GLB：

```haxe
var model = GlbLoader.load('assets/3d/chair.glb');
if (model != null)
	scene.add(model);
else
	trace(GlbLoader.lastError);
```

`GlbLoader.load` 返回整个模型（含节点层级与材质），失败时返回 `null` 并写 `lastError`。

## 拾取

射线由相机与屏幕坐标构造，之后是纯几何计算：

```haxe
var ray = new R3DRay(cam.x, cam.y, cam.z, dirX, dirY, dirZ);

var t = R3DPick.aabb(ray, model.bounds);        // 负值表示没相交
var idx = R3DPick.pickBounds(ray, boundsList);  // 返回第一个命中的下标
```

三角形级精度用 `R3DPick.triangle` / `R3DPick.quad`。

## 三轴拖拽

```haxe
var gizmo = new R3DGizmo();
gizmo.mode = R3DGizmoMode.MOVE;

var axis = gizmo.pick(cam, mx, my, 1920, 1080, model.x, model.y, model.z, 1.0);
if (axis >= 0)
{
	gizmo.beginDrag(axis, cam, mx, my, 1920, 1080, model.x, model.y, model.z, 1.0);
	// 拖动中
	gizmo.drag(cam, mx, my, 1920, 1080, model.x, model.y, model.z, 1.0, out);
}
```

`R3DGizmo.planeHit` 给出平面交点，`lineT` 给出轴上的参数位置。

## 合批

`R3DScene.autoBatch` 默认开：每帧比较静态件的 x/y/z，动了就重建批次。场景里全是动画物件
时关掉更划算。

```haxe
scene.autoBatch = false;
R3DBatch.bake(scene.members);      // 手动烘焙一次
scene.invalidateBatches();          // 之后改布局要重新烘焙
```

## 深度约定

反向 Z 与标准 Z 的差别只落在投影矩阵的 `m[10]` / `m[11]` 两个符号和着色器里的线性化公式上。
约定只在 `R3DDepth.setReversed()` 里写。

```haxe
R3DDepth.setReversed(true);    // 近 = 1，远 = 0，比较函数 GREATER_EQUAL
```

## 尺寸的两套含义

`sceneW` / `sceneH` 是光栅化尺寸，`displayW` / `displayH` 是显示尺寸。只有
`superSample == 1` 时两者相等。

```haxe
scene.setupTarget(1920, 1080);   // 按显示尺寸给，内部乘 superSample
```

## 边界

- `IndexBuffer3D` 只有 16 位索引，单批顶点上限 65535。
- 贴图超过 `GL_MAX_TEXTURE_SIZE` 时在上传前重采样一次；装得下的不做任何处理。
- `R3DMesh.setSkin` / `R3DBone` / `R3DSkeleton` 可以调用，但没有渲染路径消费蒙皮结果。
- `R3DModel.setLodLevels` 的梯子要先有各级低模才生效，现役的是 `lodMesh` / `lodDist` 单级。
- `R3DModel.playClip` / `spritesheet` 会创建播放器，但没有调用方时会一直是空表。

## 宿主边界

`rainy.render3d.host.R3DEnv` 是核心唯一向外部要东西的地方（路径、画质覆盖、统计）。
它的默认值可以直接跑，宿主启动时填一次即可。

```haxe
R3DEnv.superSample = 1.25;
R3DEnv.lodBias = 0.2;
R3DEnv.logPath = p -> 'assets/3d/$p';
```
