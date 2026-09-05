package ui;

class RulePatternEditor {
	public var jRoot : js.jquery.JQuery;

	var rule : data.def.AutoLayerRuleDef;
	var sourceDef : data.def.LayerDef;
	var layerDef : data.def.LayerDef;
	var previewMode : Bool;
	var explainCell : Null< (desc:Null<String>)->Void >;
	var getSelectedValue: Null< Void->Int >;
	var onChange: Null< Void->Void >;

	var drawButton = -1;
	var valueAtStartPoint : Null<Int> = null; // value when clicking starts
	var cellEditor : Null<ui.modal.dialog.RuleCellEditor>; // popup editing the multiple conditions of a cell

	public function new(
		rule: data.def.AutoLayerRuleDef,
		sourceDef: data.def.LayerDef,
		layerDef: data.def.LayerDef,
		previewMode=false,
		?explainCell: (desc:Null<String>)->Void,
		?getSelectedValue: Void->Int,
		?onChange: Void->Void
	) {
		this.rule = rule;
		this.sourceDef = sourceDef;
		this.layerDef = layerDef;
		this.previewMode = previewMode;
		this.explainCell = explainCell;
		this.getSelectedValue = getSelectedValue;
		this.onChange = onChange;

		valueAtStartPoint = null;
		jRoot = new J('<div/>');

		render();
	}


	inline function isEditable() return onChange!=null;


	function render() {
		// Init root
		jRoot.empty().off();
		jRoot.removeClass();
		jRoot.addClass("autoPatternGrid");
		jRoot.addClass("size-"+rule.size);

		if( isEditable() )
			jRoot.addClass("editable");

		if( previewMode )
			jRoot.addClass("preview");

		// Add a rollover tip
		function addExplain(jTarget:js.jquery.JQuery, desc:String) {
			if( explainCell==null )
				return;

			jTarget
				.mouseover( function(_) {
					explainCell(desc);
				})
				.mouseout( function(_) {
					explainCell(null);
				});
		}

		var buttonDown = -1;

		for(cy in 0...rule.size)
		for(cx in 0...rule.size) {
			var coordId = cx+cy*rule.size;
			var isCenter = cx==Std.int(rule.size/2) && cy==Std.int(rule.size/2);

			// Cell wrapper
			var jCell = new J('<div class="cell"/>');
			jCell.appendTo(jRoot);
			if( isEditable() )
				jCell.addClass("editable");

			// Center guide
			if( isCenter ) {
				switch rule.tileMode {
					case Single:
						jCell.addClass("center");

					case Stamp:
						var jStampPreview = new J('<div class="stampPreview"/>');
						jStampPreview.appendTo(jCell);
						var previewWid = 32;
						var previewHei = 32;
						if( rule.tileRectsIds.length>0 && rule.tileRectsIds[0].length>1 ) {
							var td = Editor.ME.curLayerInstance.getTilesetDef();
							if( td!=null ) {
								var bounds = td.getTileGroupBounds(rule.tileRectsIds[0]);
								if( bounds.wid>1 )
									previewWid = Std.int( previewWid * 1.9 );
								if( bounds.hei>1 )
									previewHei = Std.int( previewHei * 1.9 );
							}
						}
						jStampPreview.css("width", previewWid + "px");
						jStampPreview.css("height", previewHei + "px");
						jStampPreview.css("left", ( rule.pivotX * (32-previewWid) ) + "px");
						jStampPreview.css("top", ( rule.pivotY * (32-previewHei) ) + "px");
				}

				// Render actual Tile in context
				if( previewMode ) {
					var td = Editor.ME.curLayerInstance.getTilesetDef();
					if( td!=null ) {
						var jTile = td.createCanvasFromTileId(rule.tileRectsIds.length>0 ? rule.tileRectsIds[0][0] : null, 32);
						jCell.append(jTile);
						if( rule.tileRectsIds.length>1 )
							jTile.addClass("multi");
					}
				}
			}

			// Cell value (color + tile)
			if( !isCenter || !previewMode ) {
				var ruleValue = rule.getPattern(cx,cy);
				if( rule.hasMultiConditions(cx,cy) )
					renderMultiConditionsCell(jCell, cx, cy, addExplain);
				else if( ruleValue!=0 ) {
					var intGridVal = M.iabs(ruleValue);
					if( ruleValue>0 ) {
						// Required value
						if( intGridVal == Const.AUTO_LAYER_ANYTHING ) {
							jCell.addClass("anything");
							addExplain(jCell, 'This cell should contain any IntGrid value to match.');
						}
						else if( intGridVal>999 ) {
							var groupUid = sourceDef.resolveIntGridGroupUidFromRuleValue(intGridVal);
							var color = sourceDef.getIntGridGroupColor(groupUid);
							jCell.addClass("group");
							if( color!=null ) {
								jCell.css("background-color", color.toCssRgba(0.9));
								jCell.css("outline-color", color.toWhite(0.6).toHex());
							}
							var name = sourceDef.getIntGridGroupDisplayName(groupUid);
							addExplain(jCell, 'This cell should contain any IntGrid value from the group $name to match.');
						}
						else if( sourceDef.hasIntGridValue(intGridVal) ) {
							jCell.css("background-color", C.intToHex( sourceDef.getIntGridValueDef(intGridVal).color ) );
							var iv = sourceDef.getIntGridValueDef(intGridVal);
							if( iv.tile!=null )
								jCell.prepend( sourceDef._project.resolveTileRectAsHtmlImg(iv.tile).addClass("valueIcon") );
							addExplain(jCell, 'This cell should contain "${sourceDef.getIntGridValueDisplayName(intGridVal)}" to match.');
						}
						else
							jCell.addClass("unknown");
					}
					else {
						// Forbidden value
						jCell.addClass("not");
						var icon = intGridVal!=Const.AUTO_LAYER_ANYTHING ? "cross" : "nothing";
						jCell.append('<span class="cellIcon $icon"></span>');

						if( intGridVal == Const.AUTO_LAYER_ANYTHING ) {
							jCell.addClass("anything");
							addExplain(jCell, 'This cell should NOT contain any IntGrid value to match.');
						}
						else if( intGridVal>999 ) {
							var groupUid = sourceDef.resolveIntGridGroupUidFromRuleValue(intGridVal);
							var color = sourceDef.getIntGridGroupColor(groupUid);
							jCell.addClass("group");
							if( color!=null ) {
								jCell.css("background-color", color.toCssRgba(0.9));
								jCell.css("outline-color", color.toWhite(0.6).toHex());
							}
							var name = sourceDef.getIntGridGroupDisplayName(groupUid);
							addExplain(jCell, 'This cell should NOT contain any IntGrid value from the group $name to match.');
						}
						else if( sourceDef.hasIntGridValue(intGridVal) ) {
							jCell.css("background-color", C.intToHex( sourceDef.getIntGridValueDef(intGridVal).color ) );
							var iv = sourceDef.getIntGridValueDef(intGridVal);
							if( iv.tile!=null )
								jCell.prepend( sourceDef._project.resolveTileRectAsHtmlImg(iv.tile).addClass("valueIcon") );
							addExplain(jCell, 'This cell should NOT contain "${sourceDef.getIntGridValueDisplayName(intGridVal)}" to match.');
						}
						else
							jCell.addClass("error");
					}
				}
				else {
					// "Anything" value
					addExplain(jCell, 'This cell content doesn\'t matter.');
					jCell.addClass("empty");
				}
			}

			// Edit grid value
			if( isEditable() ) {

				var anyChange = false;
				function draw(fromDrag:Bool) {
					// Dragging over a cell with multiple conditions doesn't erase it (an explicit click does)
					if( fromDrag && rule.hasMultiConditions(cx,cy) )
						return;

					var v = rule.getPattern(cx,cy);
					switch drawButton {
						case 0:
							// Require value
							if( valueAtStartPoint>=0 )
								rule.setPattern(cx,cy, getSelectedValue());
							else if( v<0 )
								rule.setPattern(cx,cy, 0);

						case 2:
							// Forbid value
							if( valueAtStartPoint==0 )
								rule.setPattern(cx,cy, -getSelectedValue());
							else
								rule.setPattern(cx,cy, 0);

						case 1:
							// Clear
							rule.setPattern(cx,cy,0);

						case _:
					}

					// Refresh
					if( v!=rule.getPattern(cx,cy) ) {
						anyChange = true;
						rule.updateUsedValues();
						render();
					}

				}

				jCell.mousedown( (ev:js.jquery.Event)->{
					// Shift+click, or left click on a cell that already has multiple conditions: edit the conditions of this cell
					if( ev.shiftKey || ev.button==0 && rule.hasMultiConditions(cx,cy) ) {
						ev.preventDefault();
						openCellEditor(jCell, cx, cy);
						return;
					}

					valueAtStartPoint = rule.getPattern(cx,cy);
					drawButton = ev.button;
					App.ME.jBody.on("mouseup.rulePattern", (_)->{
						drawButton = -1;
						App.ME.jBody.off("mouseup.rulePattern");
						if( anyChange )
							onChange();
					});
					draw(false);
				});

				jCell.mousemove( function(ev:js.jquery.Event) {
					if( drawButton>=0 && !ev.shiftKey )
						draw(true);
				});
			}
		}

		// Keep the cell editor popup anchored to the (rebuilt) cell it edits
		if( cellEditor!=null && !cellEditor.destroyed ) {
			var jNewCell = jRoot.children(".cell").eq( cellEditor.cx + cellEditor.cy*rule.size );
			if( jNewCell.length>0 )
				cellEditor.setAnchor( MA_JQuery(jNewCell) );
		}

		return jRoot;
	}


	function openCellEditor(jCell:js.jquery.JQuery, cx:Int, cy:Int) {
		closeCellEditor();
		cellEditor = new ui.modal.dialog.RuleCellEditor(jCell, rule, cx, cy, sourceDef, ()->{
			render();
			if( onChange!=null )
				onChange();
		});
	}

	public function closeCellEditor() {
		if( cellEditor!=null && !cellEditor.destroyed )
			cellEditor.close();
		cellEditor = null;
	}


	/** Render a cell holding several conditions, as small sub-swatches (required values first, then forbidden ones) **/
	function renderMultiConditionsCell(jCell:js.jquery.JQuery, cx:Int, cy:Int, addExplain:(jTarget:js.jquery.JQuery, desc:String)->Void) {
		var conds = rule.getCellConditions(cx,cy);
		var positives = conds.filter( v->v>0 );
		var negatives = conds.filter( v->v<0 );
		var sorted = positives.concat(negatives);

		jCell.addClass("multi");

		// Sub-swatches (the panel preview of large patterns is too small to show them)
		if( !previewMode || rule.size<=5 ) {
			var max = 4;
			var shown = sorted.length>max ? max-1 : sorted.length;
			for(i in 0...shown) {
				var jCond = new J('<div class="cond"/>');
				jCond.appendTo(jCell);
				styleTerm(jCond, sorted[i]);
			}
			if( sorted.length>max )
				jCell.append('<div class="cond more">+${sorted.length-shown}</div>');
		}

		// Explanation
		var desc = [];
		if( positives.length>0 )
			desc.push( "This cell should be one of: " + positives.map( v->describeTerm(sourceDef,v) ).join(", ") + "." );
		if( negatives.length>0 )
			desc.push( "This cell should NOT be: " + negatives.map( v->describeTerm(sourceDef,v) ).join(", ") + "." );
		addExplain(jCell, desc.join("\\n"));
	}


	/** Apply the visual style of a single condition to given element (color, icon, "not" cross, etc.) **/
	function styleTerm(jEl:js.jquery.JQuery, term:Int) {
		var abs = M.iabs(term);

		if( term<0 ) {
			jEl.addClass("not");
			jEl.append('<span class="cellIcon ${abs==Const.AUTO_LAYER_ANYTHING ? "nothing" : "cross"}"></span>');
		}

		if( abs==Const.AUTO_LAYER_ANYTHING )
			jEl.addClass("anything");
		else if( abs>999 ) {
			var groupUid = sourceDef.resolveIntGridGroupUidFromRuleValue(abs);
			jEl.addClass("group");
			if( sourceDef.hasIntGridGroup(groupUid) ) {
				var color = sourceDef.getIntGridGroupColor(groupUid);
				if( color!=null )
					jEl.css("background-color", color.toCssRgba(0.9));
			}
			else
				jEl.addClass("unknown");
		}
		else if( sourceDef.hasIntGridValue(abs) ) {
			var iv = sourceDef.getIntGridValueDef(abs);
			jEl.css("background-color", C.intToHex(iv.color));
			if( iv.tile!=null )
				jEl.prepend( sourceDef._project.resolveTileRectAsHtmlImg(iv.tile).addClass("valueIcon") );
		}
		else
			jEl.addClass("unknown");
	}


	/** Human readable name of a single condition value (sign is ignored) **/
	public static function describeTerm(sourceDef:data.def.LayerDef, term:Int) : String {
		var abs = M.iabs(term);
		if( abs==Const.AUTO_LAYER_ANYTHING )
			return term>0 ? "any value" : "empty";
		else if( abs>999 ) {
			var groupUid = sourceDef.resolveIntGridGroupUidFromRuleValue(abs);
			return sourceDef.hasIntGridGroup(groupUid)
				? 'any value of group "${sourceDef.getIntGridGroupDisplayName(groupUid)}"'
				: 'unknown group';
		}
		else if( sourceDef.hasIntGridValue(abs) )
			return '"${sourceDef.getIntGridValueDisplayName(abs)}"';
		else
			return 'unknown value #$abs';
	}
}