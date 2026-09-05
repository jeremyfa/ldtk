package ui.modal.dialog;

/**
	Popup editing the multiple conditions of a single rule pattern cell.
	A cell matches if (it has no required value, or the cell value is one of the required values) AND (the cell value is none of the forbidden values).
**/
class RuleCellEditor extends ui.modal.Dialog {
	public var cx(default,null) : Int;
	public var cy(default,null) : Int;

	var rule : data.def.AutoLayerRuleDef;
	var sourceDef : data.def.LayerDef;
	var onChange : Void->Void;

	public function new(jTarget:js.jquery.JQuery, rule:data.def.AutoLayerRuleDef, cx:Int, cy:Int, sourceDef:data.def.LayerDef, onChange:Void->Void) {
		super();

		this.rule = rule;
		this.cx = cx;
		this.cy = cy;
		this.sourceDef = sourceDef;
		this.onChange = onChange;

		loadTemplate("ruleCellEditor");
		setTransparentMask();

		// Help is only shown if the rule editor help is enabled
		var ruleEditor = ui.Modal.getFirst(ui.modal.dialog.RuleEditor);
		if( ruleEditor==null || !ruleEditor.isGuidedMode() )
			jContent.find(".help").hide();

		render();
		setAnchor( MA_JQuery(jTarget) );
	}


	inline function getConditions() {
		return rule.getCellConditions(cx,cy);
	}


	/** Add or remove a single condition (+v = required, -v = forbidden). Required and forbidden states of a value are mutually exclusive. **/
	function toggle(term:Int) {
		var conds = getConditions();
		if( conds.contains(term) )
			conds.remove(term);
		else {
			conds.remove(-term);
			conds.push(term);
		}
		applyConditions(conds);
	}


	function applyConditions(conds:Array<Int>) {
		rule.setCellConditions(cx, cy, conds);
		onChange();
		render();
	}


	/** True if the current conditions can never be satisfied **/
	function isNeverMatching(positives:Array<Int>, negatives:Array<Int>) : Bool {
		if( positives.length==0 )
			return false;

		for(p in positives) {
			var excluded = false;

			if( p==Const.AUTO_LAYER_ANYTHING )
				excluded = negatives.contains(-Const.AUTO_LAYER_ANYTHING);
			else if( p<=999 ) {
				var iv = sourceDef.getIntGridValueDef(p);
				for(n in negatives) {
					var an = -n;
					if( an==p )
						excluded = true;
					else if( an>999 && an!=Const.AUTO_LAYER_ANYTHING && iv!=null && sourceDef.resolveIntGridGroupUidFromRuleValue(an)==iv.groupUid )
						excluded = true;
				}
			}

			if( !excluded )
				return false; // at least one required value can match
		}
		return true;
	}


	function render() {
		jContent.find("*").off();

		var conds = getConditions();
		var positives = conds.filter( v->v>0 );
		var negatives = conds.filter( v->v<0 );

		// Summary
		var jSummary = jContent.find(".summary");
		if( conds.length==0 )
			jSummary.text("This cell is ignored (no condition).");
		else {
			var parts = [];
			if( positives.length>0 )
				parts.push( "Must be " + positives.map( v->ui.RulePatternEditor.describeTerm(sourceDef,v) ).join(" or ") + "." );
			if( negatives.length>0 )
				parts.push( "Must NOT be " + negatives.map( v->ui.RulePatternEditor.describeTerm(sourceDef,v) ).join(", nor ") + "." );
			jSummary.text( parts.join(" ") );
		}

		// Warning
		var jWarning = jContent.find(".warning");
		if( isNeverMatching(positives, negatives) )
			jWarning.text("WARNING: these conditions can never be satisfied, this rule will never match.").show();
		else
			jWarning.empty().hide();

		// Value rows
		var jList = jContent.find("ul.conditions");
		jList.children("li:not(.header)").remove();

		function _addRow(term:Int, jSwatch:js.jquery.JQuery, name:String, ?className:String) {
			var jRow = new J('<li/>');
			if( className!=null )
				jRow.addClass(className);
			jList.append(jRow);

			jRow.append( jSwatch.addClass("swatch") );
			jRow.append( new J('<span class="name"/>').text(name) );

			var isRequired = conds.contains(term);
			var isForbidden = conds.contains(-term);
			if( isRequired )
				jRow.addClass("required");
			if( isForbidden )
				jRow.addClass("forbidden");

			var jReq = new J('<button class="transparent req"> <span class="icon selectionTick"></span> </button>');
			jReq.find(".icon").addClass( isRequired ? "checkboxOn" : "checkboxOff" );
			jReq.attr("title", "Required: the cell can contain this value (required values are combined with OR)");
			jReq.click( _->toggle(term) );
			jRow.append(jReq);

			var jForbid = new J('<button class="transparent forbid"> <span class="icon selectionTick"></span> </button>');
			jForbid.find(".icon").addClass( isForbidden ? "checkboxOn" : "checkboxOff" );
			jForbid.attr("title", "Forbidden: the cell must not contain this value");
			jForbid.click( _->toggle(-term) );
			jRow.append(jForbid);
		}

		for( g in sourceDef.getGroupedIntGridValues() ) {
			if( sourceDef.hasIntGridGroups() ) {
				var jSwatch = new J('<div class="groupSwatch"><span class="icon folder"></span></div>');
				if( g.color!=null )
					jSwatch.css("background-color", g.color.toHex());
				_addRow( sourceDef.getRuleValueFromGroupUid(g.groupUid), jSwatch, 'Group: ${g.displayName}', "group" );
			}

			for( iv in g.all ) {
				var name = sourceDef.getIntGridValueDisplayName(iv.value);
				_addRow( iv.value, JsTools.createIntGridValue(project, iv, false), name==null ? '#${iv.value}' : name );
			}
		}

		_addRow( Const.AUTO_LAYER_ANYTHING, new J('<div class="anySwatch">?</div>'), "Any value / No value", "any" );

		// Clear
		jContent.find("button.clear").click( _->applyConditions([]) );
	}
}
