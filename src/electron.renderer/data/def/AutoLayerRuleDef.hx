package data.def;

class AutoLayerRuleDef {
	#if heaps // Required to avoid doc generator to explore code too deeply

	@:allow(data.def.LayerDef, data.Definitions)
	public var uid(default,null) : Int;

	public var tileRectsIds : Array< Array<Int> > = [];
	public var chance : Float = 1.0;
	public var breakOnMatch = true;
	public var size(default,null): Int;
	var pattern : Array<Int> = []; // first condition of each cell (0 = ignored)
	var patternAlt : Array<Array<Int>> = []; // extra conditions of each cell, same indexing as pattern. Invariant: patternAlt[i].length>0 => pattern[i]!=0
	public var alpha = 1.;
	public var outOfBoundsValue : Null<Int>;
	public var flipX = false;
	public var flipY = false;
	public var tileRandomFlipX = false;
	public var tileRandomFlipY = false;
	public var active = true;
	public var tileMode : ldtk.Json.AutoLayerRuleTileMode = Single;
	public var pivotX = 0.;
	public var pivotY = 0.;
	public var xModulo = 1;
	public var yModulo = 1;
	public var xOffset = 0;
	public var yOffset = 0;
	public var tileXOffset = 0;
	public var tileYOffset = 0;
	public var tileRandomXMin = 0;
	public var tileRandomXMax = 0;
	public var tileRandomYMin = 0;
	public var tileRandomYMax = 0;
	public var checker : ldtk.Json.AutoLayerRuleCheckerMode = None;

	public var invalidated = false;

	var perlinActive = false;
	public var perlinSeed : Int;
	public var perlinScale : Float = 0.2;
	public var perlinOctaves = 2;
	var _perlin(get,null) : Null<hxd.Perlin>;

	var explicitlyRequiredValues : Array<Int> = [];

	public var radius(get,never) : Int; inline function get_radius() return size<=1 ? 1 : Std.int(size*0.5);

	public function new(uid, size=3) {
		if( !isValidSize(size) )
			throw 'Invalid rule size ${size}x$size';

		this.uid = uid;
		this.size = size;
		perlinSeed = Std.random(9999999);
		initPattern();
	}

	public function updateUsedValues() {
		// NOTE: only single-condition cells are hard requirements: a cell like "X or Y" requires neither X nor Y specifically.
		explicitlyRequiredValues = [];
		for(i in 0...pattern.length) {
			if( patternAlt[i]!=null && patternAlt[i].length>0 )
				continue;
			var v = pattern[i];
			if( v>0 && v!=Const.AUTO_LAYER_ANYTHING && !explicitlyRequiredValues.contains(v) )
				explicitlyRequiredValues.push(v);
		}
	}

	public inline function hasAnyPositionOffset() {
		return tileRandomXMin!=0 || tileRandomXMax!=0 || tileRandomYMin!=0 || tileRandomYMax!=0 || tileXOffset!=0 || tileYOffset!=0;
	}

	public inline function hasRandomTileFlip() {
		return tileRandomFlipX || tileRandomFlipY;
	}

	/** Any random variation of the rendered tile (position offset or flip). For UI purpose only. **/
	public inline function hasAnyRandomVariation() {
		return hasAnyPositionOffset() || hasRandomTileFlip();
	}

	inline function isValidSize(size:Int) {
		return size>=1 && size<=Const.MAX_AUTO_PATTERN_SIZE && size%2!=0;
	}

	inline function get__perlin() {
		if( perlinSeed!=null && _perlin==null ) {
			_perlin = new hxd.Perlin();
			_perlin.normalize = true;
			_perlin.adjustScale(50, 1);
		}

		if( perlinSeed==null && _perlin!=null )
			_perlin = null;

		return _perlin;
	}

	public inline function hasPerlin() return perlinActive;

	public function setPerlin(active:Bool) {
		if( !active ) {
			perlinActive = false;
			_perlin = null;
		}
		else
			perlinActive = true;
	}

	public function isSymetricX() {
		for( cx in 0...Std.int(size*0.5) )
		for( cy in 0...size )
			if( !cellEquals( coordId(cx,cy), coordId(size-1-cx,cy) ) )
				return false;

		return true;
	}

	public function isSymetricY() {
		for( cx in 0...size )
		for( cy in 0...Std.int(size*0.5) )
			if( !cellEquals( coordId(cx,cy), coordId(cx,size-1-cy) ) )
				return false;

		return true;
	}

	/** Compare all the conditions of 2 cells (order insensitive) **/
	function cellEquals(i:Int, j:Int) : Bool {
		if( pattern[i]==0 || pattern[j]==0 )
			return pattern[i]==pattern[j];

		var a = [ pattern[i] ].concat( patternAlt[i] );
		var b = [ pattern[j] ].concat( patternAlt[j] );
		if( a.length!=b.length )
			return false;

		a.sort( (x,y)->x-y );
		b.sort( (x,y)->x-y );
		for(k in 0...a.length)
			if( a[k]!=b[k] )
				return false;

		return true;
	}

	public inline function getPattern(cx,cy) {
		return pattern[ coordId(cx,cy) ];
	}

	/** Set a cell to a single condition (any extra condition of this cell is discarded) **/
	public inline function setPattern(cx,cy,v) {
		if( !isValid(cx,cy) )
			return 0;

		pattern[ coordId(cx,cy) ] = v;
		patternAlt[ coordId(cx,cy) ] = [];
		return v;
	}

	/** Return all the conditions of a cell (the first one from `pattern`, then the extra ones), or an empty array **/
	public function getCellConditions(cx:Int, cy:Int) : Array<Int> {
		if( !isValid(cx,cy) || pattern[coordId(cx,cy)]==0 )
			return [];
		return [ pattern[coordId(cx,cy)] ].concat( patternAlt[coordId(cx,cy)] );
	}

	public inline function hasMultiConditions(cx:Int, cy:Int) {
		return isValid(cx,cy) && patternAlt[coordId(cx,cy)].length>0;
	}

	public function hasAnyMultiConditionCell() {
		for(alt in patternAlt)
			if( alt.length>0 )
				return true;
		return false;
	}

	/**
		Replace all the conditions of a cell.
		Conditions are normalized: zeros are removed, duplicates are removed, and if both +v and -v are present, only the last one is kept.
		A cell matches if (it has no required value, or the cell value is one of the required values) AND (the cell value is none of the forbidden values).
	**/
	public function setCellConditions(cx:Int, cy:Int, conds:Array<Int>) {
		if( !isValid(cx,cy) )
			return;

		var normalized : Array<Int> = [];
		for(v in conds) {
			if( v==0 )
				continue;
			normalized.remove(v);
			normalized.remove(-v);
			normalized.push(v);
		}

		var i = coordId(cx,cy);
		pattern[i] = normalized.length==0 ? 0 : normalized[0];
		patternAlt[i] = normalized.length<=1 ? [] : normalized.slice(1);
		updateUsedValues();
	}

	public inline function fill(v:Int) {
		for(cx in 0...size)
		for(cy in 0...size)
			setPattern(cx,cy,v);
		updateUsedValues();
	}

	function initPattern() {
		pattern = [];
		patternAlt = [];
		for(i in 0...size*size) {
			pattern[i] = 0;
			patternAlt[i] = [];
		}
		updateUsedValues();
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
		// Update JSON for tileRectsIds
		if( json.tileIds!=null ) {
			json.tileRectsIds = [];
			var mode = JsonTools.readEnum(ldtk.Json.AutoLayerRuleTileMode, json.tileMode, false, Single);
			switch mode {
				case Single:
					json.tileRectsIds = json.tileIds.map( tid->[tid] );

				case Stamp:
					json.tileRectsIds = [ json.tileIds ];
			}
		}

		var r = new AutoLayerRuleDef( json.uid, json.size );
		r.active = JsonTools.readBool(json.active, true);
		r.tileRectsIds = json.tileRectsIds.copy();
		r.breakOnMatch = JsonTools.readBool(json.breakOnMatch, false); // default to FALSE to avoid breaking old maps
		r.chance = JsonTools.readFloat(json.chance);
		r.pattern = json.pattern;

		// Extra conditions per cell (optional, tolerant reading)
		r.patternAlt = [];
		var jsonAlt : Array<Dynamic> = cast json.patternAlt;
		var validAlt = jsonAlt!=null && jsonAlt.length==r.size*r.size;
		for(i in 0...r.size*r.size) {
			var extra : Array<Int> = [];
			if( validAlt && Std.isOfType(jsonAlt[i], Array) )
				for( v in (cast jsonAlt[i] : Array<Dynamic>) )
					if( Std.isOfType(v, Int) && v!=0 )
						extra.push(v);
			if( r.pattern[i]==0 && extra.length>0 )
				r.pattern[i] = extra.shift(); // enforce invariant: the first condition always lives in `pattern`
			r.patternAlt[i] = extra;
		}

		r.alpha = JsonTools.readFloat(json.alpha, 1);
		r.outOfBoundsValue = JsonTools.readNullableInt(json.outOfBoundsValue);
		r.flipX = JsonTools.readBool(json.flipX, false);
		r.flipY = JsonTools.readBool(json.flipY, false);
		r.tileRandomFlipX = JsonTools.readBool(json.tileRandomFlipX, false);
		r.tileRandomFlipY = JsonTools.readBool(json.tileRandomFlipY, false);
		r.checker = JsonTools.readEnum(ldtk.Json.AutoLayerRuleCheckerMode, json.checker, false, None);
		r.tileMode = JsonTools.readEnum(ldtk.Json.AutoLayerRuleTileMode, json.tileMode, false, Single);
		r.pivotX = JsonTools.readFloat(json.pivotX, 0);
		r.pivotY = JsonTools.readFloat(json.pivotY, 0);
		r.xModulo = JsonTools.readInt(json.xModulo, 1);
		r.yModulo = JsonTools.readInt(json.yModulo, 1);
		r.xOffset = JsonTools.readInt(json.xOffset, 0);
		r.yOffset = JsonTools.readInt(json.yOffset, 0);
		r.tileXOffset = JsonTools.readInt(json.tileXOffset, 0);
		r.tileYOffset = JsonTools.readInt(json.tileYOffset, 0);
		r.tileRandomXMin = JsonTools.readInt(json.tileRandomXMin, 0);
		r.tileRandomXMax = JsonTools.readInt(json.tileRandomXMax, 0);
		r.tileRandomYMin = JsonTools.readInt(json.tileRandomYMin, 0);
		r.tileRandomYMax = JsonTools.readInt(json.tileRandomYMax, 0);

		r.invalidated = JsonTools.readBool(json.invalidated, false);

		r.perlinActive = JsonTools.readBool(json.perlinActive, false);
		r.perlinScale = JsonTools.readFloat(json.perlinScale, 0.2);
		r.perlinOctaves = JsonTools.readInt(json.perlinOctaves, 2);
		r.perlinSeed = JsonTools.readInt(json.perlinSeed, Std.random(9999999));

		r.updateUsedValues();

		return r;
	}



	public function resize(newSize:Int) {
		if( !isValidSize(newSize) )
			throw 'Invalid rule size ${size}x$size';

		var oldSize = size;
		var oldPatt = pattern.copy();
		var oldAlt = patternAlt.copy();
		var pad = Std.int( dn.M.iabs(newSize-oldSize) / 2 );

		size = newSize;
		initPattern();
		if( newSize<oldSize ) {
			// Decrease
			for( cx in 0...newSize )
			for( cy in 0...newSize ) {
				pattern[cx + cy*newSize] = oldPatt[cx+pad + (cy+pad)*oldSize];
				patternAlt[cx + cy*newSize] = oldAlt[cx+pad + (cy+pad)*oldSize];
			}
		}
		else {
			// Increase
			for( cx in 0...oldSize )
			for( cy in 0...oldSize ) {
				pattern[cx+pad + (cy+pad)*newSize] = oldPatt[cx + cy*oldSize];
				patternAlt[cx+pad + (cy+pad)*newSize] = oldAlt[cx + cy*oldSize];
			}
		}
		updateUsedValues();
	}

	inline function coordId(cx,cy) return cx+cy*size;
	inline function isValid(cx,cy) {
		return cx>=0 && cx<size && cy>=0 && cy<size;
	}

	public function trim() {
		while( size>1 ) {
			var emptyBorder = true;
			// Horizontal borders
			for( cx in 0...size )
				if( pattern[coordId(cx,0)]!=0 || pattern[coordId(cx,size-1)]!=0 ) {
					emptyBorder = false;
					break;
				}

			// Vertical borders
			if( emptyBorder )
				for( cy in 0...size )
					if( pattern[coordId(0,cy)]!=0 || pattern[coordId(size-1,cy)]!=0 ) {
						emptyBorder = false;
						break;
					}

			if( emptyBorder )
				resize(size-2);
			else
				break;
		}
	}

	public function isEmpty() {
		for(v in pattern)
			if( v!=0 )
				return false;

		return tileRectsIds.length==0;
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

	public function isRelevantInLayer(sourceLi:data.inst.LayerInstance) {
		for(v in explicitlyRequiredValues)
			if( !sourceLi.containsIntGridValueOrGroup(v) )
				return false;
		return true;
	}

	public function isRelevantInLayerAt(sourceLi:data.inst.LayerInstance, cx:Int, cy:Int) {
		for(v in explicitlyRequiredValues) {
			if( !sourceLi.containsIntGridValueOrGroup(v) )
				return false;
			else if( size==1 && !sourceLi.hasIntGridValueInArea(v,cx,cy) )
				return false;
			else if( size>1
				&& !sourceLi.hasIntGridValueInArea(v,cx-radius,cy-radius)
				&& !sourceLi.hasIntGridValueInArea(v,cx+radius,cy-radius)
				&& !sourceLi.hasIntGridValueInArea(v,cx+radius,cy+radius)
				&& !sourceLi.hasIntGridValueInArea(v,cx-radius,cy+radius) )
					return false;
		}
		return true;
	}

	public function matches(li:data.inst.LayerInstance, source:data.inst.LayerInstance, cx:Int, cy:Int, dirX=1, dirY=1) {
		if( tileRectsIds.length==0 )
			return false;

		if( chance<=0 || chance<1 && dn.M.randSeedCoords(li.seed+uid, cx,cy, 100) >= chance*100 )
			return false;

		if( hasPerlin() && _perlin.perlin(li.seed+perlinSeed, cx*perlinScale, cy*perlinScale, perlinOctaves) < 0 )
			return false;

		// Rule check
		var value : Null<Int> = 0;
		var radius = Std.int( size/2 );
		for(px in 0...size)
		for(py in 0...size) {
			var coordId = px + py*size;
			if( pattern[coordId]==0 )
				continue;

			value = source.isValid( cx+dirX*(px-radius), cy+dirY*(py-radius) )
				? source.getIntGrid( cx+dirX*(px-radius), cy+dirY*(py-radius) )
				: outOfBoundsValue;

			if( value==null )
				return false;

			var alt = patternAlt[coordId];
			if( alt.length==0 ) {
				// Single condition (fast path)
				if( !termMatches(pattern[coordId], value, source) )
					return false;
			}
			else {
				// Multiple conditions: (no required value, or any required value matches) AND (no forbidden value matches)
				var hasPositive = false;
				var anyPositiveOk = false;
				for(k in -1...alt.length) {
					var t = k<0 ? pattern[coordId] : alt[k];
					if( t>0 ) {
						hasPositive = true;
						if( !anyPositiveOk && termMatches(t, value, source) )
							anyPositiveOk = true;
					}
					else if( !termMatches(t, value, source) )
						return false;
				}
				if( hasPositive && !anyPositiveOk )
					return false;
			}
		}
		return true;
	}

	/** Check a single condition against an IntGrid value: +v = value required, -v = value forbidden, with the "anything" and group special values **/
	inline function termMatches(term:Int, value:Int, source:data.inst.LayerInstance) : Bool {
		var abs = dn.M.iabs(term);
		if( abs==Const.AUTO_LAYER_ANYTHING )
			return term>0 ? value!=0 : value==0;
		else if( abs>999 ) {
			var valueInf = source.def.getIntGridValueDef(value);
			var inGroup = valueInf!=null && valueInf.groupUid == Std.int(abs/1000)-1;
			return term>0 ? inGroup : !inGroup;
		}
		else
			return term>0 ? value==abs : value!=abs;
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

	public function getRandomTileRectIdsForCoord(seed:Int, cx:Int,cy:Int, flips:Int) : Array<Int> {
		if( tileRectsIds.length==0 )
			return [];
		else
			return tileRectsIds[ dn.M.randSeedCoords( uid+seed+flips, cx,cy, tileRectsIds.length ) ];
	}

	/**
		Return random tile flip bits (bit0=X, bit1=Y) for given coord, based on tileRandomFlipX/Y settings.
		NOTE: `dn.M.randSeedCoords` may return negative values, hence the `iabs`.
	**/
	public function getRandomTileFlipsForCoord(seed:Int, cx:Int,cy:Int, flips:Int) : Int {
		var out = 0;
		if( tileRandomFlipX && M.iabs( dn.M.randSeedCoords( uid+seed+flips+7919, cx,cy, 100 ) ) < 50 )
			out = M.setBit(out, 0);
		if( tileRandomFlipY && M.iabs( dn.M.randSeedCoords( uid+seed+flips+104729, cx,cy, 100 ) ) < 50 )
			out = M.setBit(out, 1);
		return out;
	}

	public function getXOffsetForCoord(seed:Int, cx:Int,cy:Int, flips:Int) : Int {
		return ( M.hasBit(flips,0)?-1:1 ) * ( tileXOffset + (
			tileRandomXMin==0 && tileRandomXMax==0
				? 0
				: dn.M.randSeedCoords( uid+seed+flips, cx,cy, (tileRandomXMax-tileRandomXMin+1) ) + tileRandomXMin
		));
	}

	public function getYOffsetForCoord(seed:Int, cx:Int,cy:Int, flips:Int) : Int {
		return ( M.hasBit(flips,1)?-1:1 ) * ( tileYOffset + (
			tileRandomYMin==0 && tileRandomYMax==0
				? 0
				: dn.M.randSeedCoords( uid+seed+1, cx,cy, (tileRandomYMax-tileRandomYMin+1) ) + tileRandomYMin
		));
	}

	#end
}