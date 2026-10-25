package rainy.render3d.core;

import rainy.render3d.host.R3DLog;
import rainy.render3d.host.R3DEnv;
import rainy.render3d.core.R3DCaps.R3DVendor;
import rainy.render3d.stage3d.Stage3DAtlasCache;

enum abstract R3DSortStrategy(Int) from Int to Int
{

	var DISTANCE = 0;
	/** Material priority, then distance. */
	var MATERIAL = 1;

	var PROGRAM = 2;

	public function label():String
	{
		return switch (cast this : R3DSortStrategy)
		{
			case DISTANCE: 'distance';
			case MATERIAL: 'material';
			case PROGRAM: 'program';
		}
	}
}

class R3DVendorPath
{

	public static var vramShare:Float = 0.55;

	public static var vramBudgetCeilingMB:Int = 4096;

	public static var sortStrategy(default, null):R3DSortStrategy = R3DSortStrategy.MATERIAL;

	public static var adaptiveBudgetMB(default, null):Int = 0;

	public static var debugGroups(default, null):Bool = false;

	public static var applied(default, null):Bool = false;

	public static function apply():Void
	{
		// Compared with `==` rather than switched on: `R3DVendor` is a String backed
		// abstract, and its members are not compile time constants, so they cannot be
		// used as switch patterns.
		if (R3DCaps.vendor == R3DVendor.NVIDIA)
		{
			sortStrategy = R3DSortStrategy.PROGRAM;
			// Anisotropy is nearly free on this hardware and does more for texture clarity
			// at grazing angles than any post filter.
			R3DCaps.setAniso(16);
		}
		else if (R3DCaps.vendor == R3DVendor.AMD)
		{
			sortStrategy = R3DSortStrategy.MATERIAL;
			R3DCaps.setAniso(8);
		}
		else
		{
			// Integrated parts share memory bandwidth with the CPU; fewer programs and
			// less anisotropy keeps the frame from starving the compositor.
			sortStrategy = R3DSortStrategy.MATERIAL;
			R3DCaps.setAniso(4);
		}

		debugGroups = R3DCaps.hasExtension('KHR_debug') || R3DCaps.hasExtension('EXT_debug_marker');

		adaptiveBudgetMB = computeAdaptiveBudget();
		if (adaptiveBudgetMB > 0)
		{
			if (Stage3DAtlasCache.budgetMB > adaptiveBudgetMB)
				Stage3DAtlasCache.budgetMB = adaptiveBudgetMB;
			if (R3DEnv.textureBudgetMB > adaptiveBudgetMB)
				R3DEnv.textureBudgetMB = adaptiveBudgetMB;
		}

		applied = true;
	}

	static function computeAdaptiveBudget():Int
	{
		if (!R3DCaps.vramSupported) return 0;
		R3DCaps.pollVram();
		var free:Float = R3DCaps.vramFreeMB;
		if (free <= 0) return 0;
		var want:Int = Std.int(free * vramShare);
		if (want > vramBudgetCeilingMB) want = vramBudgetCeilingMB;
		// Below this a cache would evict more than it serves; better to keep whatever the
		// preset asked for and let the LRU do its job than to thrash at 32MB.
		if (want < 64) want = 64;
		return want;
	}

	public static function describe():String
	{
		return 'vendor path ${R3DCaps.vendor} sort ${sortStrategy.label()} aniso ${R3DCaps.presetAniso}'
			+ (adaptiveBudgetMB > 0 ? ' vram-budget ${adaptiveBudgetMB}MB' : '')
			+ (debugGroups ? ' khr-debug' : '');
	}
}
