package data.inst;

import data.DataTypes;

class LayerInstance implements ldtk.rules.RuleSource implements ldtk.rules.RuleTarget {
	var _project : Project;

	public var def(get,never) : data.def.LayerDef;
		inline function get_def() return _project.defs.getLayerDef(layerDefUid);

	public var level(get,never) : Level;
		inline function get_level() return _project.getLevelAnywhere(levelId);

	var camera(get,never) : display.Camera;
		inline function get_camera() return Editor.ME.camera;

	public var iid : String;
	public var levelId : Int;
	public var layerDefUid : Int;
	public var visible = true;

	@:allow(importer)
	var pxOffsetX : Int = 0;

	@:allow(importer)
	var pxOffsetY : Int = 0;

	public var pxTotalOffsetX(get,never) : Int;
		inline function get_pxTotalOffsetX() return pxOffsetX + def.pxOffsetX;

	public var pxTotalOffsetY(get,never) : Int;
		inline function get_pxTotalOffsetY() return pxOffsetY + def.pxOffsetY;

	public var pxParallaxX(get,never) : Int;
		inline function get_pxParallaxX() return M.round( pxTotalOffsetX + camera.getParallaxOffsetX(this) );

	public var pxParallaxY(get,never) : Int;
		inline function get_pxParallaxY() return M.round( pxTotalOffsetY + camera.getParallaxOffsetY(this) );

	public var seed : Int;
	public var optionalRules : Map<Int,Bool> = new Map();

	// Layer content
	var intGrid : Map<Int,Int> = new Map(); // <coordId, value>
	public var entityInstances : Array<EntityInstance> = [];
	public var gridTiles : Map<Int, Array<GridTileInfos>> = []; // <coordId, tileinfos>
	var overrideTilesetUid : Null<Int>;

	/** < RuleUid, < coordId, { tiles } > >. Tile x/y are relative to the layer (layerDef.pxOffsetX/Y are NOT included, they are exported separately as __pxTotalOffsetX/Y). **/
	public var autoTilesCache : Null<ldtk.rules.AutoTile.AutoTileCache> = null;

	var ruleEngine : Null<ldtk.rules.RuleEngine>;
	var ruleTileset : Null<EditorRuleTileset>;

	var areaIntGridUseCount : Map<Int, Map<Int,Int>> = new Map();
	var layerIntGridUseCount : Map<Int,Int> = new Map();
	var intGridAreaSize = 10;

	public var pxWid(get,never) : Int; inline function get_pxWid() return level.pxWid - pxOffsetX;
	public var pxHei(get,never) : Int; inline function get_pxHei() return level.pxHei - pxOffsetY;
	public var cWid(get,never) : Int; inline function get_cWid() return dn.M.ceil( pxWid / def.gridSize );
	public var cHei(get,never) : Int; inline function get_cHei() return dn.M.ceil( pxHei / def.gridSize );


	@:allow(data.Level)
	private function new(p:Project, levelUid:Int, layerDefUid:Int, layerInstIid:String) {
		_project = p;
		iid = layerInstIid;
		this.levelId = levelUid;
		this.layerDefUid = layerDefUid;
		seed = Std.random(9999999);
	}

	inline function areaCoordId(cx:Int,cy:Int) {
		return Std.int(cx/intGridAreaSize) + Std.int(cy/intGridAreaSize) * 10000;
	}

	public function hasIntGridValueInArea(iv:Int, cx:Int, cy:Int) {
		return areaIntGridUseCount.exists(iv) && areaIntGridUseCount.get(iv).get(areaCoordId(cx,cy)) > 0;
	}

	public function recountAllIntGridValues() {
		if( def.type!=IntGrid )
			return;

		areaIntGridUseCount = new Map();
		layerIntGridUseCount = new Map();

		for(cy in 0...cHei)
		for(cx in 0...cWid) {
			if( hasIntGrid(cx,cy) )
				increaseAreaIntGridValueCount(getIntGrid(cx,cy), cx, cy);
		}
	}

	inline function increaseAreaIntGridValueCount(iv:Int, cx:Int, cy:Int) {
		if( iv==0 || iv==null )
			return;

		if( !areaIntGridUseCount.exists(iv) )
			areaIntGridUseCount.set(iv, new Map());

		var areaCountMap = areaIntGridUseCount.get(iv);
		final cid = areaCoordId(cx,cy);
		if( !areaCountMap.exists(cid) )
			areaCountMap.set(cid,1);
		else
			areaCountMap.set(cid, areaCountMap.get(cid)+1);

		// Layer counts
		if( !layerIntGridUseCount.exists(iv) )
			layerIntGridUseCount.set(iv, 1);
		else
			layerIntGridUseCount.set(iv, layerIntGridUseCount.get(iv)+1);

		// Also update group
		if( iv<1000 ) {
			var groupUid = def.getIntGridGroupUidFromValue(iv);
			if( groupUid>=0 )
				increaseAreaIntGridValueCount(def.getRuleValueFromGroupUid(groupUid), cx,cy);
		}
	}


	inline function decreaseAreaIntGridValueCount(iv:Int, cx:Int, cy:Int) {
		if( iv!=0 && iv!=null && areaIntGridUseCount.exists(iv) ) {
			var areaCountMap = areaIntGridUseCount.get(iv);
			final cid = areaCoordId(cx,cy);
			if( areaCountMap.exists(cid) ) {
				areaCountMap.set(cid, areaCountMap.get(cid)-1);

				// Last one in area
				if( areaCountMap.get(cid)<=0 )
					areaCountMap.remove(cid);

				// Layer counts
				if( layerIntGridUseCount.exists(iv) ) {
					layerIntGridUseCount.set(iv, layerIntGridUseCount.get(iv)-1);
					// Last one in layer
					if( layerIntGridUseCount.get(iv)<=0 )
						layerIntGridUseCount.remove(iv);
				}
			}
		}

		// Also update group
		if( iv<1000 ) {
			var groupUid = def.getIntGridGroupUidFromValue(iv);
			if( groupUid>=0 )
				decreaseAreaIntGridValueCount(def.getRuleValueFromGroupUid(groupUid), cx,cy);
		}
	}


	public function containsIntGridValueOrGroup(iv:Int) {
		return layerIntGridUseCount.exists(iv);
	}


	@:keep public function toString() {
		return 'LayerInst#$layerDefUid "${def.identifier}" [${def.type}]';
	}


	public function setOverrideTileset(?tilesetUid:Int) {
		overrideTilesetUid = tilesetUid==null ? null : tilesetUid;
	}

	public function getDefaultTilesetUid() : Null<Int> {
		return
			def.tilesetDefUid!=null ? def.tilesetDefUid
			: null;
	}

	public function getTilesetUid() : Null<Int> {
		return
			overrideTilesetUid!=null ? overrideTilesetUid
			: def.tilesetDefUid!=null ? def.tilesetDefUid
			: null;
	}


	public function isUsingTileset(td:data.def.TilesetDef) {
		if( getTilesetUid()==td.uid )
			return true;

		if( def.type==Entities )
			for( li in entityInstances )
				if( li.isUsingTileset(td) )
					return true;

		return false;
	}


	public function getTilesetDef() : Null<data.def.TilesetDef> {
		var tdUid = getTilesetUid();
		return tdUid==null ? null : _project.defs.getTilesetDef(tdUid);
	}

	public function toJson() : ldtk.Json.LayerInstanceJson {
		var td = getTilesetDef();

		var json : ldtk.Json.LayerInstanceJson = {
			// Fields preceded by "__" are only exported to facilitate parsing
			__identifier: def.identifier,
			__type: Std.string(def.type),
			__cWid: cWid,
			__cHei: cHei,
			__gridSize: def.gridSize,
			__opacity: def.displayOpacity,
			__pxTotalOffsetX: pxOffsetX + def.pxOffsetX,
			__pxTotalOffsetY: pxOffsetY + def.pxOffsetY,
			__tilesetDefUid: td!=null ? td.uid : null,
			__tilesetRelPath: td!=null ? td.relPath : null,

			iid: iid,
			levelId: levelId,
			layerDefUid: layerDefUid,
			pxOffsetX: pxOffsetX,
			pxOffsetY: pxOffsetY,
			visible: visible,
			optionalRules: {
				var arr = [];
				for(k in optionalRules.keys())
					arr.push(k);
				arr;
			},

			intGridCsv: {
				var csv : Array<Int> = [];
				if( def.type==IntGrid )
					for(cy in 0...cHei)
					for(cx in 0...cWid)
						csv.push( getIntGrid(cx,cy) );
				csv;
			},

			autoLayerTiles: autoTilesCache==null
				? []
				: ldtk.rules.RuleEngine.toJsonTiles( ldtk.rules.RuleEngine.flatten(autoTilesCache, getRulesInDisplayOrder()) ),

			seed: seed,

			overrideTilesetUid: overrideTilesetUid,
			gridTiles: {
				var arr : Array<ldtk.Json.Tile> = [];
				for( e in gridTiles.keyValueIterator() )
					for( tileInf in e.value ) {
						arr.push({
							px: [
								getCx(e.key) * def.gridSize,
								getCy(e.key) * def.gridSize,
							],
							src: [
								td==null ? -1 : td.getTileSourceX(tileInf.tileId),
								td==null ? -1 : td.getTileSourceY(tileInf.tileId),
							],
							f: tileInf.flips,
							t: tileInf.tileId,
							d: [ e.key ],
							a: 1,
						});
					}
				arr;
			},

			entityInstances: entityInstances.map( function(ei) return ei.toJson(this) ),
		}

		if( _project.hasFlag(ExportPreCsvIntGridFormat) )
			json.intGrid = {
				var arr = [];
				for(e in intGrid.keyValueIterator())
					arr.push({
						coordId: e.key,
						v: e.value-1,
					});
				arr;
			}

		return json;
	}

	public function isEmpty() {
		switch def.type {
			case IntGrid:
				for(e in intGrid)
					return false;
				return true;

			case AutoLayer:
				for(rg in def.autoRuleGroups)
				for(r in rg.rules)
					return false;
				return false;

			case Entities:
				return entityInstances.length==0;

			case Tiles:
				for(e in gridTiles)
					return false;
				return true;
		}
	}

	public static function fromJson(p:Project, json:ldtk.Json.LayerInstanceJson) {
		if( (cast json).layerDefId!=null ) json.layerDefUid = (cast json).layerDefId;
		if( (cast json).iid==null )
			json.iid = p.generateUniqueId_UUID();

		var li = new data.inst.LayerInstance( p, JsonTools.readInt(json.levelId), JsonTools.readInt(json.layerDefUid), json.iid );
		li.seed = JsonTools.readInt(json.seed, Std.random(9999999));
		li.pxOffsetX = JsonTools.readInt(json.pxOffsetX, 0);
		li.pxOffsetY = JsonTools.readInt(json.pxOffsetY, 0);
		li.visible = JsonTools.readBool(json.visible, true);

		if( json.intGridCsv==null ) {
			// Read old pre-CSV format
			for( intGridJson in json.intGrid )
				li.intGrid.set( intGridJson.coordId, intGridJson.v+1 );
		}
		else {
			// Read CSV format
			for(coordId in 0...json.intGridCsv.length)
				if( json.intGridCsv[coordId]>=0 )
					li.intGrid.set(coordId, json.intGridCsv[coordId]);
		}
		li.recountAllIntGridValues();

		for( gridTilesJson in json.gridTiles ) {
			if( dn.Version.lower(p.jsonVersion, "0.4", true) || gridTilesJson.d==null )
				gridTilesJson.d = [ (cast gridTilesJson).coordId, (cast gridTilesJson).tileId ];

			if( dn.Version.lower(p.jsonVersion, "0.6", true) )
				gridTilesJson.t = gridTilesJson.d[1];

			var coordId = gridTilesJson.d[0];
			if( !li.gridTiles.exists(coordId) )
				li.gridTiles.set(coordId, []);

			li.gridTiles.get(coordId).push({
				tileId: gridTilesJson.t,
				flips: gridTilesJson.f,
			});
		}
		li.overrideTilesetUid = JsonTools.readNullableInt(json.overrideTilesetUid);

		// Optional rules
		if( json.optionalRules!=null )
			for(uid in json.optionalRules)
				li.optionalRules.set(uid, true);

		// Entities
		for( entityJson in json.entityInstances )
			li.entityInstances.push( EntityInstance.fromJson(p, li, entityJson) );

		// Auto-layer tiles
		if( json.autoLayerTiles!=null ) {
			try {
				var jsonAutoLayerTiles : Array<ldtk.Json.Tile> = JsonTools.readArray(json.autoLayerTiles);
				li.clearAllAutoTilesCache();

				for(at in jsonAutoLayerTiles) {
					var ruleId = at.d[0];
					var coordId = at.d[1];

					if( dn.Version.lower(p.jsonVersion, "0.6", true) )
						at.t = at.d[2];

					if( !li.autoTilesCache.exists(ruleId) )
						li.autoTilesCache.set(ruleId, new Map());

					if( !li.autoTilesCache.get(ruleId).exists(coordId) )
						li.autoTilesCache.get(ruleId).set(coordId, []);

					if( dn.Version.lower(p.jsonVersion, "0.5", true) && ( li.pxOffsetX!=0 || li.pxOffsetY!=0 ) ) {
						// Fix old coords that included offsets
						at.px[0]-=li.pxOffsetX;
						at.px[1]-=li.pxOffsetY;
					}

					li.autoTilesCache.get(ruleId).get(coordId).push({
						x: at.px[0],
						y: at.px[1],
						srcX: at.src[0],
						srcY: at.src[1],
						flips: at.f,
						tid: at.t,
						a: at.a==null ? 1 : at.a,
					});
				}
			}
			catch(e:Dynamic) {
				App.LOG.error('Failed to parse autoTilesCache in $li (err=$e)');
				li.autoTilesCache = null;
			}
		}

		return li;
	}

	inline function requireType(t:ldtk.Json.LayerType) {
		if( def.type!=t )
			throw 'Only works on $t layer!';
	}

	public inline function isValid(cx:Int,cy:Int) {
		return cx>=0 && cx<cWid && cy>=0 && cy<cHei;
	}

	public inline function coordId(cx:Int, cy:Int) {
		return cx + cy*cWid;
	}

	public inline function getCx(coordId:Int) {
		return coordId - Std.int(coordId/cWid)*cWid;
	}

	public inline function getCy(coordId:Int) {
		return Std.int(coordId/cWid);
	}

	public inline function levelToLayerCx(levelX:Float) {
		return Std.int( ( levelX - pxTotalOffsetX ) / def.gridSize ); // TODO not tested: check if this works with the new layerDef offsets
	}

	public inline function levelToLayerCy(levelY:Float) {
		return Std.int( ( levelY - pxTotalOffsetY ) / def.gridSize );
	}

	public function tidy(p:Project) : Bool {
		_project = p;
		_project.markIidAsUsed(iid);
		var anyChange = false;

		// Remove lost optional rule group UIDs
		var keep = false;
		for(optGroupUid in optionalRules.keys()) {
			var rg = def.getRuleGroup(optGroupUid);
			if( rg==null || !rg.isOptional ) {
				App.LOG.add("tidy", 'Removed lost optional rule group #$optGroupUid in $this');
				optionalRules.remove(optGroupUid);
				anyChange = true;
			}
		}


		switch def.type {
			case IntGrid, AutoLayer:
				// Remove lost intGrid values
				if( def.type==IntGrid )
					for(cy in 0...cHei)
					for(cx in 0...cWid)
						if( hasIntGrid(cx,cy) && !def.hasIntGridValue( getIntGrid(cx,cy) ) ) {
							removeIntGrid(cx,cy,false);
							if( def.isAutoLayer() )
								autoTilesCache = null;
							anyChange = true;
							// no logging as this could be a LOT of entries
						}

				if( def.isAutoLayer() && autoTilesCache!=null ) {
					// Discard lost rules autoTiles
					for( rUid in autoTilesCache.keys() )
						if( !def.hasRule(rUid) ) {
							App.LOG.add("tidy", 'Removed lost rule cache in $this');
							autoTilesCache.remove(rUid);
							anyChange = true;
						}

					if( !def.autoLayerRulesCanBeUsed() ) {
						App.LOG.add("tidy", 'Removed all autoTilesCache in $this (rules can no longer be applied)');
						clearAllAutoTilesCache();
						anyChange = true;
					}
				}


			case Entities:
				var i = 0;
				var ei = null;
				var level = this.level;
				while( i<entityInstances.length ) {
					ei = entityInstances[i];
					if( ei.def==null ) {
						// Remove lost entities (def removed)
						App.LOG.add("tidy", 'Removed lost entity in $this');
						entityInstances.splice(i,1);
						anyChange = true;
					}
					else
						i++;
				}

				// Cleanup field instances
				for(ei in entityInstances)
					if( ei.tidy(_project, this) )
						anyChange = true;

			case Tiles:
		}

		return anyChange;
	}


	@:allow(data.Level)
	private function applyNewBounds(newPxLeft:Int, newPxTop:Int, newPxWid:Int, newPxHei:Int) {
		var totalOffsetX = pxOffsetX - newPxLeft;
		var totalOffsetY = pxOffsetY - newPxTop;
		var newPxOffsetX = totalOffsetX % def.gridSize;
		var newPxOffsetY = totalOffsetY % def.gridSize;
		var newCWid = dn.M.ceil( (newPxWid-newPxOffsetX) / def.gridSize );
		var newCHei = dn.M.ceil( (newPxHei-newPxOffsetY) / def.gridSize );

		// Move data
		var cDeltaX = Std.int( totalOffsetX / def.gridSize);
		var cDeltaY = Std.int( totalOffsetY / def.gridSize);
		switch def.type {
			case IntGrid:
				// Remap coords
				var old = intGrid;
				intGrid = new Map();
				for(cx in 0...cWid)
				for(cy in 0...cHei) {
					var newCx = cx + cDeltaX;
					var newCy = cy + cDeltaY;
					var newCoordId = newCx + newCy * newCWid;
					if( old.exists(coordId(cx,cy)) && newCx>=0 && newCx<newCWid && newCy>=0 && newCy<newCHei )
						intGrid.set( newCoordId, old.get(coordId(cx,cy)) );
				}

			case AutoLayer:

			case Entities:
				var i = 0;
				while( i<entityInstances.length ) {
					var ei = entityInstances[i];
					ei.x += cDeltaX*def.gridSize;
					ei.y += cDeltaY*def.gridSize;

					// Move points
					for(fi in ei.fieldInstances)
						if( fi.def.type==F_Point )
							for(i in 0...fi.getArrayLength())  {
								var pt = fi.getPointGrid(i);
								if( pt==null )
									continue;

								pt.cx+=cDeltaX;
								pt.cy+=cDeltaY;
								fi.parseValue( i, pt.cx + Const.POINT_SEPARATOR + pt.cy );
							}

					i++;
				}

			case Tiles:
				// Remap coords
				var old = gridTiles;
				gridTiles = new Map();
				for(cx in 0...cWid)
				for(cy in 0...cHei) {
					var newCx = cx + cDeltaX;
					var newCy = cy + cDeltaY;
					var newCoordId = newCx + newCy * newCWid;
					if( old.exists(coordId(cx,cy)) && newCx>=0 && newCx<newCWid && newCy>=0 && newCy<newCHei )
						gridTiles.set( newCoordId, old.get(coordId(cx,cy)) );
				}

		}

		// The remaining pixels are stored in offsets
		pxOffsetX = newPxOffsetX;
		pxOffsetY = newPxOffsetY;
	}

	public inline function hasAnyGridValue(cx:Int, cy:Int) {
		return switch def.type {
			case IntGrid: hasIntGrid(cx,cy);
			case Tiles: hasAnyGridTile(cx,cy);
			case Entities: false;
			case AutoLayer: false;
		}
	}


	/** INT GRID *******************/

	public function getIntGrid(cx:Int, cy:Int) : Int {
		requireType(IntGrid);
		return !isValid(cx,cy) || !intGrid.exists( coordId(cx,cy) ) ? 0 : intGrid.get( coordId(cx,cy) );
	}

	public inline function getIntGridColorAt(cx:Int, cy:Int) : Null<UInt> {
		var v = def.getIntGridValueDef( getIntGrid(cx,cy) );
		return v==null ? null : v.color;
	}

	public inline function getIntGridIdentifierAt(cx:Int, cy:Int) : Null<String> {
		var v = def.getIntGridValueDef( getIntGrid(cx,cy) );
		return v==null ? null : v.identifier;
	}

	public function setIntGrid(cx:Int, cy:Int, v:Int, useAsyncRender:Bool) {
		requireType(IntGrid);
		if( isValid(cx,cy) ) {
			if( v>=0 ) {
				var old = intGrid.get(coordId(cx,cy));
				if( old!=v ) {
					decreaseAreaIntGridValueCount(old, cx,cy);
					increaseAreaIntGridValueCount(v, cx, cy);
					intGrid.set( coordId(cx,cy), v );
					// Update dependent IntGrid layers
					updateDependentIntGrids(cx, cy, v, useAsyncRender);
				}
				if( useAsyncRender )
					asyncPaint(cx,cy, def.getIntGridValueColor(v));
			}
			else {
				removeIntGrid(cx,cy, useAsyncRender);
				// Update dependent IntGrid layers to remove value
				updateDependentIntGrids(cx, cy, 0, useAsyncRender);
			}
		}
	}

	public inline function hasIntGrid(cx:Int, cy:Int) {
		requireType(IntGrid);
		return getIntGrid(cx,cy)!=0;
	}

	public function removeIntGrid(cx:Int, cy:Int, useAsyncRender:Bool) {
		requireType(IntGrid);
		if( isValid(cx,cy) && hasIntGrid(cx,cy) ) {
			decreaseAreaIntGridValueCount( intGrid.get(coordId(cx,cy)), cx, cy );
			intGrid.remove( coordId(cx,cy) );
			// Update dependent IntGrid layers to remove value
			updateDependentIntGrids(cx, cy, 0, useAsyncRender);
		}
		if( useAsyncRender )
			asyncErase(cx,cy);
	}

	/** Update dependent IntGrid layers that use this layer as source **/
	function updateDependentIntGrids(cx:Int, cy:Int, value:Int, useAsyncRender:Bool) {
		// Safety checks
		if( _project==null || _project.defs==null || level==null )
			return;
			
		// Find all layers that depend on this one
		for(ld in _project.defs.layers) {
			if( ld.type==IntGrid && ld.intGridSourceLayerDefUid==def.uid ) {
				// Get the dependent layer instance
				var dependentLi = level.getLayerInstance(ld);
				if( dependentLi!=null ) {
					// Calculate subdivision ratio
					var ratio = Std.int(def.gridSize / ld.gridSize);
					if( def.gridSize % ld.gridSize == 0 && ratio > 0 ) {
						// Track if any changes were made
						var anyChange = false;
						
						// Update all subdivided cells
						var startCx = cx * ratio;
						var startCy = cy * ratio;
						for(subX in 0...ratio) {
							for(subY in 0...ratio) {
								var depCx = startCx + subX;
								var depCy = startCy + subY;
								if( dependentLi.isValid(depCx, depCy) ) {
									// Set the value directly without triggering further updates
									if( value > 0 ) {
										var old = dependentLi.intGrid.get(dependentLi.coordId(depCx, depCy));
										if( old != value ) {
											dependentLi.decreaseAreaIntGridValueCount(old, depCx, depCy);
											dependentLi.increaseAreaIntGridValueCount(value, depCx, depCy);
											dependentLi.intGrid.set(dependentLi.coordId(depCx, depCy), value);
											anyChange = true;
										}
										if( useAsyncRender )
											dependentLi.asyncPaint(depCx, depCy, ld.getIntGridValueColor(value));
									} else {
										// Remove value
										if( dependentLi.hasIntGrid(depCx, depCy) ) {
											dependentLi.decreaseAreaIntGridValueCount(dependentLi.intGrid.get(dependentLi.coordId(depCx, depCy)), depCx, depCy);
											dependentLi.intGrid.remove(dependentLi.coordId(depCx, depCy));
											anyChange = true;
										}
										if( useAsyncRender )
											dependentLi.asyncErase(depCx, depCy);
									}
								}
							}
						}
						
						// If this dependent IntGrid changed, update any further dependencies
						if( anyChange ) {
							// Update each changed cell in the dependent layer
							for(subX in 0...ratio) {
								for(subY in 0...ratio) {
									var depCx = startCx + subX;
									var depCy = startCy + subY;
									if( dependentLi.isValid(depCx, depCy) ) {
										// Recursively update any IntGrid layers that depend on this one
										var depValue = dependentLi.getIntGrid(depCx, depCy);
										dependentLi.updateDependentIntGrids(depCx, depCy, depValue, useAsyncRender);
									}
								}
							}
							
							// Clear auto-tiles cache for any AutoLayers that use this IntGrid as source
							for(autoLd in _project.defs.layers) {
								if( autoLd.type==AutoLayer && autoLd.autoSourceLayerDefUid==ld.uid ) {
									var autoLi = level.getLayerInstance(autoLd);
									if( autoLi!=null ) {
										autoLi.autoTilesCache = null;
										// Trigger re-render of the AutoLayer
										if( Editor.exists() )
											Editor.ME.levelRender.invalidateLayer(autoLi);
									}
								}
							}
						}
					}
				}
			}
		}
	}

	/** Update this IntGrid layer from its source layer **/
	public function updateFromSourceIntGrid() {
		if( def==null || def.type!=IntGrid || def.intGridSourceLayerDefUid==null )
			return;
			
		if( level==null || _project==null || _project.defs==null )
			return;
			
		var sourceLd = def.intGridSourceLd;
		if( sourceLd==null )
			return;
			
		var sourceLi = level.getLayerInstance(sourceLd);
		if( sourceLi==null )
			return;
			
		// Calculate subdivision ratio
		var ratio = Std.int(sourceLd.gridSize / def.gridSize);
		if( sourceLd.gridSize % def.gridSize != 0 || ratio <= 0 )
			return;
			
		// Clear current values
		intGrid = new Map();
		areaIntGridUseCount = new Map();
		layerIntGridUseCount = new Map();
		
		// Copy subdivided values from source
		for(srcCy in 0...sourceLi.cHei) {
			for(srcCx in 0...sourceLi.cWid) {
				if( sourceLi.hasIntGrid(srcCx, srcCy) ) {
					var value = sourceLi.getIntGrid(srcCx, srcCy);
					// Set all subdivided cells
					var startCx = srcCx * ratio;
					var startCy = srcCy * ratio;
					for(subX in 0...ratio) {
						for(subY in 0...ratio) {
							var cx = startCx + subX;
							var cy = startCy + subY;
							if( isValid(cx, cy) && value > 0 ) {
								intGrid.set(coordId(cx, cy), value);
								increaseAreaIntGridValueCount(value, cx, cy);
							}
						}
					}
				}
			}
		}
	}


	/** ENTITY INSTANCE *******************/

	public function createEntityInstance(ed:data.def.EntityDef) : Null<EntityInstance> {
		requireType(Entities);

		var ei = new EntityInstance(_project, this, ed.uid, _project.generateUniqueId_UUID());
		entityInstances.push(ei);
		_project.registerEntityInstance(ei);
		return ei;
	}

	public function containsEntity(ei:EntityInstance) {
		for(e in entityInstances)
			if( e==ei )
				return true;
		return false;
	}

	public function duplicateEntityInstance(ei:EntityInstance) : EntityInstance {
		var copy = EntityInstance.fromJson( _project, this, ei.toJson(this) );
		copy.iid = _project.generateUniqueId_UUID();
		entityInstances.push(copy);
		_project.registerEntityInstance(copy);

		return copy;
	}

	public function removeEntityInstance(ei:EntityInstance) {
		requireType(Entities);
		if( !entityInstances.remove(ei) )
			throw "Unknown instance "+ei;

		_project.removeAnyFieldRefsTo(ei);
		_project.unregisterEntityIid(ei.iid);
		_project.unregisterAllReverseIidRefsFor(ei);
	}


	inline function asyncPaint(cx:Int, cy:Int, col:Col) {
		if( isValid(cx,cy) && Editor.exists() )
			Editor.ME.levelRender.asyncPaint(this, cx,cy, col);
	}

	inline function asyncErase(cx:Int, cy:Int) {
		if( isValid(cx,cy) && Editor.exists() )
			Editor.ME.levelRender.asyncErase(this, cx,cy);
	}


	/** TILES *******************/
	inline function getGridTileColor(tileId:Int) : dn.Col {
		var td = _project.defs.getTilesetDef( getTilesetUid() );
		return td!=null ? td.getAverageTileColor(tileId) : White;
	}

	public function addGridTile(cx:Int, cy:Int, tileId:Null<Int>, flips=0, stack:Bool, useAsyncRender=true) {
		if( !isValid(cx,cy) )
			return;

		if( tileId==null ) {
			removeAllGridTiles(cx,cy, useAsyncRender);
			return;
		}

		if( !gridTiles.exists(coordId(cx,cy)) || !stack )
			gridTiles.set( coordId(cx,cy), [{ tileId:tileId, flips:flips }]);
		else {
			removeSpecificGridTile(cx, cy, tileId, flips);
			gridTiles.get( coordId(cx,cy) ).push({ tileId:tileId, flips:flips });
		}

		if( useAsyncRender )
			asyncPaint(cx,cy, getGridTileColor(tileId));
	}


	public function removeAllGridTiles(cx:Int, cy:Int, useAsyncRender:Bool) {
		if( useAsyncRender )
			asyncErase(cx,cy);

		if( isValid(cx,cy) && hasAnyGridTile(cx,cy) ) {
			gridTiles.remove( coordId(cx,cy) );
			return true;
		}
		else
			return false;
	}


	public inline function removeSpecificGridTile(cx:Int, cy:Int, tileId:Int, flips:Int) {
		if( hasAnyGridTile(cx,cy) ) {
			var stack = gridTiles.get(coordId(cx,cy));
			for( i in 0...stack.length )
				if( stack[i].tileId==tileId && stack[i].flips==flips ) {
					stack.splice(i,1);
					break;
				}
		}
	}

	public inline function removeTopMostGridTile(cx:Int, cy:Int, useAsyncRender:Bool) {
		if( useAsyncRender )
			asyncErase(cx,cy);

		if( hasAnyGridTile(cx,cy) ) {
			gridTiles.get( coordId(cx,cy) ).pop();

			if( gridTiles.get( coordId(cx,cy) ).length==0 )
				gridTiles.remove( coordId(cx,cy) );

			return true;
		}
		else
			return false;
	}

	public inline function removeGridTileAtStackIndex(cx:Int, cy:Int, stackIdx:Int) {
		if( hasAnyGridTile(cx,cy) && getGridTileStack(cx,cy).length>stackIdx )
			gridTiles.get( coordId(cx,cy) ).splice( stackIdx, 1 );
	}

	public function getHighestGridTileStack(left:Int, top:Int, right:Int, bottom:Int) {
		var highest = 0;
		for(cx in left...right+1)
		for(cy in top...bottom+1)
			if( hasAnyGridTile(cx,cy) )
				highest = dn.M.imax( highest, getGridTileStack(cx,cy).length );
		return highest;
	}

	public inline function getGridTileStack(cx:Int, cy:Int) : Array<GridTileInfos> {
		return isValid(cx,cy) && gridTiles.exists( coordId(cx,cy) ) ? gridTiles.get( coordId(cx,cy) ) : [];
	}

	public inline function getTopMostGridTile(cx:Int, cy:Int) : Null<GridTileInfos> {
		return hasAnyGridTile(cx,cy) ? gridTiles.get(coordId(cx,cy))[ gridTiles.get(coordId(cx,cy)).length-1 ] : null;
	}


	public function remapToGridSize(oldGrid:Int, newGrid:Int) {
		var newCWid = M.ceil( pxWid/newGrid );
		var newCHei = M.ceil( pxHei/newGrid );
		inline function _newCoordId(cx,cy) {
			return cx+cy*newCWid;
		}

		switch def.type {
			case IntGrid:
				var newIntGrid = new Map();
				for(cy in 0...cHei)
				for(cx in 0...cWid)
					if( hasIntGrid(cx,cy) && cx<newCWid && cy<newCHei )
						newIntGrid.set( _newCoordId(cx,cy), getIntGrid(cx,cy));
				intGrid = newIntGrid;
				if( def.isAutoLayer() )
					autoTilesCache = null;

			case Entities:
				var ratio = newGrid/oldGrid;
				for(ei in entityInstances) {
					ei.x = M.floor( ratio * ei.x );
					ei.y = M.floor( ratio * ei.y );
					if( ei.customWidth!=null )
						ei.customWidth = M.floor( ratio * ei.customWidth );
					if( ei.customHeight!=null )
						ei.customHeight = M.floor( ratio * ei.customHeight );
				}

			case Tiles:
				var newGridTiles = new Map();
				for(cy in 0...cHei)
				for(cx in 0...cWid)
					if( hasAnyGridTile(cx,cy) && cx<newCWid && cy<newCHei ) {
						var stack = getGridTileStack(cx,cy).copy();
						newGridTiles.set( _newCoordId(cx,cy), stack );
					}
				gridTiles = newGridTiles;

			case AutoLayer:
				autoTilesCache = null;
		}
	}


	public function hasSpecificGridTile(cx:Int, cy:Int, tileId:Int, ?flips:Null<Int>) {
		if( !hasAnyGridTile(cx,cy) )
			return false;

		for( t in getGridTileStack(cx,cy) )
			if( t.tileId==tileId && ( flips==null || t.flips==flips ) )
				return true;

		return false;
	}

	public inline function hasAnyGridTile(cx:Int, cy:Int) : Bool {
		return isValid(cx,cy) && gridTiles.exists( coordId(cx,cy) ) && gridTiles.get(coordId(cx,cy)).length>0;
	}

	inline function isAutoTileCellAllowed(cx:Int, cy:Int) {
		if( def.autoTilesKilledByOtherLayerUid==null )
			return true;
		else
			return !level.getLayerInstance(def.autoTilesKilledByOtherLayerUid).hasAnyGridTile(cx,cy);
	}


	/* RULE ENGINE PLUMBING (ldtk.rules) *****************************************************************/

	// RuleSource & RuleTarget implementation
	public function getWidth() return cWid;
	public function getHeight() return cHei;
	public function getGroupUidOfValue(v:Int) return def.getIntGridGroupUidFromValue(v);
	public function getSeed() return seed;
	public function getGridSize() return def.gridSize;
	public function getTilePivotX() return def.tilePivotX;
	public function getTilePivotY() return def.tilePivotY;
	public function isCellKilled(cx:Int, cy:Int) return !isAutoTileCellAllowed(cx,cy);

	/** The IntGrid layer instance read by the rules of this layer, or null if none **/
	public function getRuleSourceLayer() : Null<LayerInstance> {
		return def.type==IntGrid ? this : def.autoSourceLayerDefUid!=null ? level.getLayerInstance(def.autoSourceLayerDefUid) : null;
	}

	/** The shared rule engine for this layer (reused, re-pointed to the current source and tileset) **/
	function getRuleEngine(source:LayerInstance) : ldtk.rules.RuleEngine {
		if( ruleTileset==null )
			ruleTileset = new EditorRuleTileset();
		ruleTileset.td = getTilesetDef();

		if( ruleEngine==null )
			ruleEngine = new ldtk.rules.RuleEngine(source, this, ruleTileset);
		else {
			ruleEngine.source = source;
			ruleEngine.target = this;
			ruleEngine.tileset = ruleTileset;
		}
		return ruleEngine;
	}

	/** Enum value ids of the level biome field, or null if the layer has no biome field **/
	function getBiomeValues() : Null<Array<String>> {
		if( def.biomeFieldUid==null )
			return null;
		var fi = level.getFieldInstanceByUid(def.biomeFieldUid, false);
		if( fi==null )
			return null;
		return [ for(i in 0...fi.getArrayLength()) fi.getEnumValue(i) ];
	}

	public function getRulesInEvalOrder() : Array<ldtk.rules.RuleDef> {
		var arr : Array<ldtk.rules.RuleDef> = [];
		def.iterateActiveRulesInEvalOrder( this, r->arr.push(r) );
		return arr;
	}

	public function getRulesInDisplayOrder() : Array<ldtk.rules.RuleDef> {
		var arr : Array<ldtk.rules.RuleDef> = [];
		def.iterateActiveRulesInDisplayOrder( this, r->arr.push(r) );
		return arr;
	}

	function clearAutoTilesCacheByRule(r:data.def.AutoLayerRuleDef) {
		autoTilesCache.set( r.uid, [] );
	}

	function clearAllAutoTilesCache() {
		autoTilesCache = new Map();
	}



	public function isRuleGroupAppliedHere(rg:data.def.AutoLayerRuleGroupDef) {
		return ldtk.rules.RuleGroups.isGroupApplied(rg, getBiomeValues(), optionalRules);
	}

	public inline function isRuleGroupEnabled(rg:data.def.AutoLayerRuleGroupDef) {
		return ldtk.rules.RuleGroups.isGroupEnabled(rg, optionalRules);
	}

	public function enableRuleGroupHere(rg:data.def.AutoLayerRuleGroupDef) {
		optionalRules.set(rg.uid, true);
	}
	public function disableRuleGroupHere(rg:data.def.AutoLayerRuleGroupDef) {
		optionalRules.remove(rg.uid);
	}
	public function toggleRuleGroupHere(rg:data.def.AutoLayerRuleGroupDef) {
		if( optionalRules.exists(rg.uid) )
			disableRuleGroupHere(rg);
		else
			enableRuleGroupHere(rg);
	}


	public inline function applyBreakOnMatchesEverywhere() {
		applyBreakOnMatchesArea(0,0,cWid,cHei);
	}

	public function applyBreakOnMatchesArea(cx:Int, cy:Int, wid:Int, hei:Int) {
		if( autoTilesCache==null )
			return;
		var source = getRuleSourceLayer();
		if( source==null )
			return;
		getRuleEngine(source).applyBreakOnMatchesArea(autoTilesCache, getRulesInEvalOrder(), cx, cy, wid, hei);
	}


	/** Apply all rules to specific cell **/
	public function applyAllRulesAt(cx:Int, cy:Int, wid:Int, hei:Int) {
		if( !def.autoLayerRulesCanBeUsed() ) {
			clearAllAutoTilesCache();
			return;
		}

		var source = getRuleSourceLayer();
		if( source==null ) {
			clearAllAutoTilesCache();
			return;
		}

		if( autoTilesCache==null ) {
			applyAllRules();
			return;
		}

		// Recompute the rect (expanded to nearby cells) and apply break-on-match on it
		getRuleEngine(source).applyRulesInRect(autoTilesCache, getRulesInEvalOrder(), cx, cy, wid, hei);
	}

	/** Apply all rules to all cells **/
	public inline function applyAllRules() {
		if( def.isAutoLayer() ) {
			clearAllAutoTilesCache();
			applyAllRulesAt(0, 0, cWid, cHei);
			App.LOG.warning("All rules applied in "+toString());
		}
	}

	/** Apply the rule to all layer cells **/
	public function applyRuleToFullLayer(r:data.def.AutoLayerRuleDef, applyBreakOnMatch:Bool) {
		if( !def.isAutoLayer() )
			return;

		// Clear tiles if rule is disabled
		if( !r.active || !def.getParentRuleGroup(r).active ) {
			autoTilesCache.remove(r.uid);
			return;
		}

		var source = getRuleSourceLayer();
		if( source==null || !r.isRelevantIn(source) )
			return;

		clearAutoTilesCacheByRule(r);

		if( def.autoLayerRulesCanBeUsed() ) {
			getRuleEngine(source).applyRuleEverywhere(autoTilesCache, r);

			if( applyBreakOnMatch )
				applyBreakOnMatchesEverywhere();
		}
	}

}


/** `ldtk.rules.RuleTileset` over an editor tileset definition **/
private class EditorRuleTileset implements ldtk.rules.RuleTileset {
	public var td : Null<data.def.TilesetDef>;
	public function new() {}
	public function getTileCx(tileId:Int) return td.getTileCx(tileId);
	public function getTileCy(tileId:Int) return td.getTileCy(tileId);
	public function getTileSourceX(tileId:Int) return td.getTileSourceX(tileId);
	public function getTileSourceY(tileId:Int) return td.getTileSourceY(tileId);
	public function isTileOpaque(tileId:Int) return td!=null && td.isTileOpaque(tileId);
}
