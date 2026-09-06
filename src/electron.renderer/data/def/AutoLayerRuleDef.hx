package data.def;

class AutoLayerRuleDef extends ldtk.rules.RuleDef {
	#if heaps // Required to avoid doc generator to explore code too deeply

	/** Editor only: TRUE if the rule tiles must be recomputed **/
	public var invalidated = false;

	public function new(uid:Int, size=3) {
		super(uid, size);
		perlinSeed = Std.random(9999999);
	}

	@:keep public function toString() {
		return 'Rule#$uid(${size}x$size)';
	}

	public function toJson(ld:LayerDef) : ldtk.Json.AutoRuleDef {
		tidy(ld);

		return {
			uid: uid,
			active: active,
			size: size,
			tileRectsIds: tileRectsIds.map( arr->arr.copy() ),
			alpha: alpha,
			chance: JsonTools.writeFloat(chance),
			breakOnMatch: breakOnMatch,
			pattern: pattern.copy(), // WARNING: could leak to undo/redo leaks if (one day) pattern contained objects
			patternAlt: hasAnyMultiConditionCell() ? patternAlt.map( a->a.copy() ) : null, // deep copy, same reason as above
			flipX: flipX,
			flipY: flipY,
			tileRandomFlipX: tileRandomFlipX,
			tileRandomFlipY: tileRandomFlipY,
			xModulo: xModulo,
			yModulo: yModulo,
			xOffset: xOffset,
			yOffset: yOffset,
			tileXOffset: tileXOffset,
			tileYOffset: tileYOffset,
			tileRandomXMin: tileRandomXMin,
			tileRandomXMax: tileRandomXMax,
			tileRandomYMin: tileRandomYMin,
			tileRandomYMax: tileRandomYMax,
			checker: JsonTools.writeEnum(checker, false),
			tileMode: JsonTools.writeEnum(tileMode, false),
			pivotX: JsonTools.writeFloat(pivotX),
			pivotY: JsonTools.writeFloat(pivotY),
			outOfBoundsValue: outOfBoundsValue,

			invalidated: invalidated,

			perlinActive: perlinActive,
			perlinSeed: perlinSeed,
			perlinScale: JsonTools.writeFloat(perlinScale),
			perlinOctaves: perlinOctaves,
		}
	}

	public static function fromJson(jsonVersion:String, json:ldtk.Json.AutoRuleDef) {
		var r = new AutoLayerRuleDef( json.uid, json.size );
		ldtk.rules.RuleDef.readJsonInto(r, json);
		r.invalidated = JsonTools.readBool(json.invalidated, false);
		if( json.perlinSeed==null )
			r.perlinSeed = Std.random(9999999);
		return r;
	}

	public function isUsingUnknownIntGridValues(ld:LayerDef) {
		if( ld.type!=IntGrid )
			throw "Invalid layer type";

		inline function _isUnknown(v:Int) {
			v = M.iabs(v);
			return v!=0 && (
				v<=999 && !ld.hasIntGridValue(v)
				|| v>999 && v!=Const.AUTO_LAYER_ANYTHING && !ld.hasIntGridGroup( ld.resolveIntGridGroupUidFromRuleValue(v) )
			);
		}

		for(i in 0...pattern.length) {
			if( _isUnknown(pattern[i]) )
				return true;

			for(v in patternAlt[i])
				if( _isUnknown(v) )
					return true;
		}

		return false;
	}

	/** Compatibility shim: see `RuleDef.isRelevantIn` **/
	public inline function isRelevantInLayer(sourceLi:data.inst.LayerInstance) {
		return isRelevantIn(sourceLi);
	}

	public function tidy(ld:LayerDef) {
		var anyFix = false;

		trim();

		if( flipX && isSymetricX() ) {
			App.LOG.add("tidy", 'Fixed X symetry of Rule#$uid');
			flipX = false;
			anyFix = true;
		}

		if( flipY && isSymetricY() ) {
			App.LOG.add("tidy", 'Fixed Y symetry of Rule#$uid');
			flipY = false;
			anyFix = true;
		}

		// NOTE: tileRandomFlipX/Y are intentionally NOT cleared on symetric patterns: they affect the rendered tile, not the pattern matching.

		if( xModulo==1 && yModulo==1 && checker!=None ) {
			App.LOG.add("tidy", 'Fixed checker mode of Rule#$uid');
			checker = None;
			anyFix = true;
		}

		if( xModulo==1 && checker==Horizontal ) {
			App.LOG.add("tidy", 'Fixed checker mode of Rule#$uid');
			checker = yModulo>1 ? Vertical : None;
			anyFix = true;
		}

		if( yModulo==1 && checker==Vertical ) {
			App.LOG.add("tidy", 'Fixed checker mode of Rule#$uid');
			checker = xModulo>1 ? Horizontal : None;
			anyFix = true;
		}

		var sourceLd = ld.autoSourceLd!=null ? ld.autoSourceLd : ld;
		if( outOfBoundsValue!=null && outOfBoundsValue!=0 && !sourceLd.hasIntGridValue(outOfBoundsValue) ) {
			App.LOG.add("tidy", 'Fixed lost outOfBoundsValue: $outOfBoundsValue');
			outOfBoundsValue = null;
		}

		return anyFix;
	}

	#end
}
