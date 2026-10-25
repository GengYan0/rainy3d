# rainy3d

Stage3D renderer for HaxeFlixel: scene graph, deferred-ish lighting, shadow maps, SSAO,
model import, post-processing and a camera rig. Extracted from the Rainy engine so the 3D
layer can be versioned, tested and reused separately from the game that grew it.

## What is in here

| Area | Files |
| --- | --- |
| Core | `R3DScene`, `R3DCamera`, `R3DModel`, `R3DMesh`, `R3DMaterial`, `R3DTexture` |
| Batching | `R3DBatch`, `R3DInst` |
| Lighting | `R3DLight`, `R3DShadow`, `R3DSkybox`, `R3DCubemap` |
| Post | `R3DPost`, `R3DPresent`, `R3DAA`, `R3DSSAO`, `R3DFramebuffer` |
| Geometry | `R3DGeom`, `R3DLines`, `R3DCollider`, `R3DPick`, `R3DGizmo` |
| Editing | `R3DEditorCore`, `R3DNodeEditor`, `R3DMaterialGraph` |
| Scene loading | `scene/AssetLibrary` |
| Host boundary | `host/R3DEnv`, `host/R3DLog` |

`rainy.render3d.host.R3DEnv` is the only place the core asks the surrounding game for
anything (paths, quality overrides, statistics). Its defaults are inert, so the library
builds and runs on its own; an engine fills it in once at boot.

## Requirements

Haxe 4.3, hxcpp or the HTML5 target, `flixel` 6.2.0, `openfl` 9.5.2, `lime` 8.3.2.
Stage3D is required for rendering; `R3DCaps` reports what the context will actually accept
before anything is uploaded.

## Install

```bash
haxelib dev rainy3d /path/to/rainy3d
```

Then `<haxelib name="rainy3d"/>` in `Project.xml`.

## Scope notes

- Textures larger than `GL_MAX_TEXTURE_SIZE` are resampled once on upload. Nothing smaller
  is touched, so an atlas that fits is never re-encoded.
- `IndexBuffer3D` takes 16-bit indices. Meshes past 65535 vertices are split into buckets
  by `R3DBatch.bake()`; `R3DMesh.setArrays()` warns when it has to truncate.
- The depth convention lives in `R3DDepth.setReversed()` and nowhere else.

## Licence

MIT. See `LICENSE.md`.
