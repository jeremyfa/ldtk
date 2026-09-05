package ui.modal.dialog;

import data.def.AutoLayerRuleDef;
import data.def.AutoLayerRuleGroupDef;

enum RuleRemapMode {
	/** Duplicate a whole group (asks for a new group name) **/
	RemapGroup(rg:AutoLayerRuleGroupDef);

	/** Duplicate a list of rules, and insert the copies in `rg` right after `after` **/
	RemapRules(rg:AutoLayerRuleGroupDef, after:AutoLayerRuleDef);
}

/**
	Duplicate some rules (or a whole group), and optionally remap their IntGrid values, IntGrid groups and tiles.
**/
class RuleRemap extends ui.modal.Dialog {
	var ld : data.def.LayerDef;
	var td : data.def.TilesetDef;
	var srcRules : Array<AutoLayerRuleDef>;
	var mode : RuleRemapMode;
	var onConfirm : (copies:Array<AutoLayerRuleDef>)->Void;

	// IntGrid remaps
	var idRemaps : Map<Int,Int> = new Map(); // IntGrid value => IntGrid value
	var groupRemaps : Map<Int,Int> = new Map(); // Rule group value ( (groupUid+1)*1000 ) => rule group value

	// Tiles remaps
	var tileset : ui.Tileset;
	var allTileIds : Array<Int> = [];
	var individualTileMode = false;
	var tileOffsetX = 0;
	var tileOffsetY = 0;
	var tileRemaps : Map<Int,Int> = new Map(); // tileId => tileId (individual mode only)


	public function new(ld:data.def.LayerDef, rules:Array<AutoLayerRuleDef>, mode:RuleRemapMode, onConfirm:(copies:Array<AutoLayerRuleDef>)->Void) {
		super();

		this.ld = ld;
		this.srcRules = rules.copy();
		this.mode = mode;
		this.onConfirm = onConfirm;

		var title = switch mode {
			case RemapGroup(rg): 'Duplicate group: "${rg.name}"';
			case RemapRules(_): srcRules.length==1 ? 'Duplicate 1 rule' : 'Duplicate ${srcRules.length} rules';
		}
		loadTemplate("ruleRemap.html", { title:title });
		canBeClosedManually = false;

		// List used IntGrid IDs & groups
		for(r in srcRules)
		for(cx in 0...r.size)
		for(cy in 0...r.size)
		for(c in r.getCellConditions(cx,cy)) {
			var v = M.iabs(c);
			if( v==0 || v==Const.AUTO_LAYER_ANYTHING )
				continue;
			if( v>999 )
				groupRemaps.set(v,v);
			else
				idRemaps.set(v,v);
		}
		for(r in srcRules)
			if( r.outOfBoundsValue!=null && r.outOfBoundsValue>0 && !idRemaps.exists(r.outOfBoundsValue) )
				idRemaps.set(r.outOfBoundsValue, r.outOfBoundsValue);

		// Create ID remappers
		var jIdsList = jContent.find(".intGridIds");
		var sortedIds = [ for(k in idRemaps.keys()) k ];
		sortedIds.sort( (a,b)->Reflect.compare(a,b) );
		if( sortedIds.length==0 )
			jIdsList.append('<li class="empty">No IntGrid value used</li>');
		for(v in sortedIds)
			jIdsList.append( makeIdRemapper(v, idRemaps.get(v)) );

		// Create group remappers
		var jGroupsList = jContent.find(".intGridGroups");
		var sortedGroups = [ for(k in groupRemaps.keys()) k ];
		sortedGroups.sort( (a,b)->Reflect.compare(a,b) );
		if( sortedGroups.length==0 )
			jContent.find(".groupsSection").hide();
		else
			for(v in sortedGroups)
				jGroupsList.append( makeGroupRemapper(v, groupRemaps.get(v)) );

		// List used tiles
		td = project.defs.getTilesetDef(ld.tilesetDefUid);
		var doneTileIds = new Map();
		allTileIds = [];
		for(r in srcRules)
		for(rectIds in r.tileRectsIds)
		for(tid in rectIds)
			if( !doneTileIds.exists(tid) ) {
				doneTileIds.set(tid,true);
				allTileIds.push(tid);
			}
		allTileIds.sort( (a,b)->Reflect.compare(a,b) );

		// Tile picker (offset mode)
		tileset = new ui.Tileset(jContent.find(".tileset"), td, OneTile);
		tileset.onSelectAnything = ()->{
			if( allTileIds.length==0 )
				return;
			var tid = tileset.getSelectedTileIds()[0];
			var fcx = td.getTileCx( allTileIds[0] );
			var fcy = td.getTileCy( allTileIds[0] );
			var tcx = td.getTileCx(tid);
			var tcy = td.getTileCy(tid);
			setTileOffset(tcx-fcx, tcy-fcy);
		}
		setTileOffset(0,0,true);
		tileset.fitView();

		// Tile remap mode
		var jModes = jContent.find(".tileModes input[name=tileRemapMode]");
		jModes.filter("[value=offset]").prop("checked", true);
		jModes.change( (ev:js.jquery.Event)->{
			individualTileMode = jModes.filter(":checked").val()=="individual";
			updateTileMode();
		});
		updateTileMode();

		if( allTileIds.length==0 )
			jContent.find(".rightColumn").hide();

		// Confirm & remap!
		addButton(L.t._("Confirm"), ()->{
			switch mode {
				case RemapGroup(rg):
					var copyJson = rg.toJson(ld);
					copyJson.name += " copy";
					new InputDialog(
						L.t._("Name this new group"),
						copyJson.name,
						(s:String)->return s.length==0 ? "Please enter a valid name" : null,
						(s:String)->return s,
						(s:String)->{
							var copyGroup = ld.pasteRuleGroup( project, data.Clipboard.createTemp(CRuleGroup, copyJson), rg );
							copyGroup.name = s;
							applyRemaps(copyGroup.rules);
							onConfirm(copyGroup.rules);
							close();
						}
					);

				case RemapRules(rg, after):
					var json = { rules: srcRules.map( r->r.toJson(ld) ) };
					var copies = ld.pasteRules( project, rg, data.Clipboard.createTemp(CRules, json), after );
					if( copies==null )
						copies = [];
					applyRemaps(copies);
					onConfirm(copies);
					close();
			}
		});
		addCancel();
	}


	/** Apply all remaps (tiles, IntGrid values, IntGrid groups, out-of-bounds) to given rule copies **/
	function applyRemaps(rules:Array<AutoLayerRuleDef>) {
		for(r in rules) {
			// Tiles
			for(rectIds in r.tileRectsIds)
			for(i in 0...rectIds.length)
				rectIds[i] = remapTileId(rectIds[i]);

			// Pattern values & groups (all conditions of each cell)
			for(cx in 0...r.size)
			for(cy in 0...r.size) {
				var conds = r.getCellConditions(cx,cy);
				if( conds.length==0 )
					continue;
				var changed = false;
				var remapped = conds.map( v->{
					var av = M.iabs(v);
					if( av==0 || av==Const.AUTO_LAYER_ANYTHING )
						return v;
					var nv = av>999
						? ( groupRemaps.exists(av) ? groupRemaps.get(av) : av )
						: ( idRemaps.exists(av) ? idRemaps.get(av) : av );
					if( nv!=av )
						changed = true;
					return v<0 ? -nv : nv;
				});
				if( changed )
					r.setCellConditions(cx,cy, remapped);
			}
			r.updateUsedValues();

			// Out-of-bounds value
			if( r.outOfBoundsValue!=null && idRemaps.exists(r.outOfBoundsValue) )
				r.outOfBoundsValue = idRemaps.get(r.outOfBoundsValue);
		}
	}


	inline function remapTileId(tid:Int) : Int {
		if( individualTileMode )
			return tileRemaps.exists(tid) ? tileRemaps.get(tid) : tid;
		else
			return tid + tileOffsetX + tileOffsetY*td.cWid;
	}


	function lock() {
		jWrapper.find("button.confirm").prop("disabled",true);
	}
	function unlock() {
		jWrapper.find("button.confirm").prop("disabled",false);
	}


	function updateTileMode() {
		if( individualTileMode ) {
			jContent.find(".tileset").hide();
			jContent.find(".tileRemaps").show();
			updateTileRemapsList();
			unlock();
		}
		else {
			jContent.find(".tileRemaps").hide();
			jContent.find(".tileset").show();
			setTileOffset(tileOffsetX, tileOffsetY);
		}
	}


	function updateTileRemapsList() {
		var jList = jContent.find(".tileRemaps").empty();
		if( td==null )
			return;

		for(tid in allTileIds) {
			var jLi = new J('<li/>');
			jList.append(jLi);

			var jOld = td.createTileHtmlImageFromTileId(tid, 32);
			jOld.addClass("oldTile");
			jLi.append(jOld);

			jLi.append('<div class="icon right"/>');

			var newTid = tileRemaps.exists(tid) ? tileRemaps.get(tid) : tid;
			var jNew = td.createTileHtmlImageFromTileId(newTid, 32);
			jNew.addClass("newTile");
			if( newTid==tid )
				jNew.addClass("unchanged");
			jNew.attr("title", newTid==tid ? "No change (click to pick a replacement tile)" : "Left click to change, right click to reset");
			jNew.mousedown( (ev:js.jquery.Event)->{
				switch ev.button {
					case 0:
						JsTools.openTilePickerModal(td.uid, OneTile, [newTid], false, (tids)->{
							if( tids.length>0 ) {
								if( tids[0]==tid )
									tileRemaps.remove(tid);
								else
									tileRemaps.set(tid, tids[0]);
							}
							updateTileRemapsList();
						});

					case _:
						tileRemaps.remove(tid);
						updateTileRemapsList();
				}
			});
			jLi.append(jNew);
		}
	}


	function setTileOffset(ox:Int, oy:Int, scrollTo=false) {
		tileOffsetX = ox;
		tileOffsetY = oy;

		if( td==null )
			return;

		var valid = true;
		var offsetedIds = [];
		for(tid in allTileIds) {
			var tcx = td.getTileCx(tid) + tileOffsetX;
			var tcy = td.getTileCy(tid) + tileOffsetY;
			if( tcx>=0 && tcx<td.cWid && tcy>=0 && tcy<td.cHei )
				offsetedIds.push(tid+tileOffsetX + tileOffsetY*td.cWid);
			else
				valid = false;
		}

		if( valid )
			unlock();
		else
			lock();

		tileset.clearCursor();
		tileset.renderAtlas();

		// Render original tiles
		if( tileOffsetX!=0 || tileOffsetY!=0 )
			tileset.renderHighlightedTiles(allTileIds, "#080");

		// Render offseted tiles
		tileset.renderHighlightedTiles(offsetedIds, valid?dn.Col.inlineHex("#0f0"):dn.Col.inlineHex("#f00"));

		// Render arrows
		if( tileOffsetX!=0 || tileOffsetY!=0 ) {
			var offX = Std.int(td.tileGridSize*0.5);
			var offY = offX;
			for(idx in 0...allTileIds.length) {
				if( idx>=offsetedIds.length )
					break;
				tileset.renderArrow(
					td.getTileSourceX(allTileIds[idx])+offX, td.getTileSourceY(allTileIds[idx])+offY,
					td.getTileSourceX(offsetedIds[idx])+offX, td.getTileSourceY(offsetedIds[idx])+offY,
					valid ? dn.Col.inlineHex("#fff") : dn.Col.inlineHex("#f00")
				);
			}
		}

		// Focus
		if( scrollTo )
			tileset.focusAround(offsetedIds, true);
	}


	function makeIntGridId(id:Int, ?className:String, ?nameOverride:String) {
		var jId = new J('<div></div>');
		if( className!=null )
			jId.addClass(className);

		if( nameOverride!=null )
			jId.append(nameOverride);
		else if( ld.getIntGridValueDisplayName(id)!=null )
			jId.append(ld.getIntGridValueDisplayName(id));
		else
			jId.append('#$id');

		var col = ld.getIntGridValueColor(id);
		if( col!=null )
			jId.css({ backgroundColor: col.toHex() });
		return jId;
	}


	function makeIdRemapper(oldId:Int, newId:Int) : js.jquery.JQuery {
		var jMapper = new J("<li/>");

		var jOld = makeIntGridId(oldId, "oldId");
		jMapper.append(jOld);

		jMapper.append('<div class="icon right"/>');

		var jNew = makeIntGridId(newId, newId==oldId?"newId unchanged":"newId", newId==oldId?"No change":null);
		jMapper.append(jNew);
		jNew.click( _->{
			new ui.modal.dialog.IntGridValuePicker(jNew, ld, newId, id->{
				idRemaps.set(oldId, id);
				jMapper.replaceWith( makeIdRemapper(oldId, id) );
			});
		});

		return jMapper;
	}


	function makeIntGridGroup(ruleValue:Int, ?className:String, ?nameOverride:String) {
		var groupUid = ld.resolveIntGridGroupUidFromRuleValue(ruleValue);
		var jGroup = new J('<div></div>');
		if( className!=null )
			jGroup.addClass(className);

		if( nameOverride!=null )
			jGroup.append(nameOverride);
		else if( ld.hasIntGridGroup(groupUid) )
			jGroup.append( ld.getIntGridGroupDisplayName(groupUid) );
		else
			jGroup.append('Unknown group #$groupUid');

		var col = ld.hasIntGridGroup(groupUid) ? ld.getIntGridGroupColor(groupUid) : null;
		if( col!=null )
			jGroup.css({ backgroundColor: col.toHex() });
		return jGroup;
	}


	function makeGroupRemapper(oldValue:Int, newValue:Int) : js.jquery.JQuery {
		var jMapper = new J("<li/>");

		var jOld = makeIntGridGroup(oldValue, "oldId");
		jMapper.append(jOld);

		jMapper.append('<div class="icon right"/>');

		var jNew = makeIntGridGroup(newValue, newValue==oldValue?"newId unchanged":"newId", newValue==oldValue?"No change":null);
		jMapper.append(jNew);
		jNew.click( _->{
			var ctx = new ContextMenu(jNew);
			for( g in ld.getAllIntGridGroups() ) {
				var v = (g.uid+1)*1000;
				ctx.addAction({
					label: L.untranslated( ld.getIntGridGroupDisplayName(g.uid) ),
					selectionTick: v==newValue,
					cb: ()->{
						groupRemaps.set(oldValue, v);
						jMapper.replaceWith( makeGroupRemapper(oldValue, v) );
					},
				});
			}
		});

		return jMapper;
	}
}
