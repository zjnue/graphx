package graphx;

import flash.display.Graphics;
import flash.display.LoaderInfo;
import flash.display.Sprite;
import flash.display.Stage;
import flash.display.StageScaleMode;
import flash.events.Event;
import flash.Lib;
import flash.net.URLLoader;
import flash.net.URLRequest;
import flash.text.TextField;
import flash.text.TextFieldAutoSize;
import flash.text.TextFormat;

import graphx.Path;

class VizTokenizer {
	
	var str:String;
	
	public function new(str:String) {
		this.str = str;
	}
	
	public function takeChar() : String {
		var r = ~/^(\S+)\s*/;
		var matches = r.match(this.str);
		if (matches) {
			this.str = this.str.substr( r.matched(0).length );
			return r.matched(1);
		} else
			return '';
	}
	
	public function takeNumbers(?num:Int = 1) : Array<Float> {
		var tokens = new Array<Float>();
		for (i in 0...num) {
			var char = takeChar();
			if (char != '')
				tokens.push( Std.parseFloat(char) );
		}
		return tokens;
	}
	
	public function takeNumber() : Float {
		return Std.parseFloat( takeChar() );
	}
	
	public function takeString() : String {
		var byteCount = Std.parseInt(this.takeChar());
		var charCount = 0;
		var charCode = -1;
		if ('-' != this.str.charAt(0)) {
			return '';
		}
		while (0 < byteCount) {
			++charCount;
			charCode = this.str.charCodeAt(charCount);
			if (0x80 > charCode) {
				--byteCount;
			} else if (0x800 > charCode) {
				byteCount -= 2;
			} else {
				byteCount -= 3;
			}
		}
		var s = this.str.substr(1, charCount);
		this.str = ~/^\s+/.replace(this.str.substr(1 + charCount), '');
		return s;
	}
}

class VizEntity {
	
	public var defaultAttrHashName:String;
	public var name:String;
	public var viz:Viz;
	public var rootGraph:VizGraph;
	public var parentGraph:VizGraph;
	public var immediateGraph:VizGraph;
	
	public var attrs:Hash<String>;
	public var drawAttrs:Hash<String>;
	
	public var bbRect:Rect;
	public var escStringMatchRe:EReg;
	
	public function new(defaultAttrHashName, name, viz, ?rootGraph, ?parentGraph, ?immediateGraph) {
		this.defaultAttrHashName = defaultAttrHashName;
		this.name = name;
		this.viz = viz;
		this.rootGraph = rootGraph;
		this.parentGraph = parentGraph;
		this.immediateGraph = immediateGraph;
		attrs = new Hash();
		drawAttrs = new Hash();
	}
	
	public function initBB() {
		var r = ~/([0-9.]+),([0-9.]+)/;
		var matches = r.match(this.getAttr('pos'));
		if (matches) {
			var x = Math.round( Std.parseFloat(r.matched(1)) );
			var y = Math.round( this.viz.height - Std.parseFloat(r.matched(2)) );
			this.bbRect = new Rect(x, y, x, y);
		}
	}
	
	function getAttr(attrName:String, ?escString:Bool=false) {
		var attrValue = null;
		if (!this.attrs.exists(attrName)) {
			var graph = this.parentGraph;
			while (graph != null) {
				if (cast( Reflect.field(graph, this.defaultAttrHashName) ).exists(attrName)) {
					attrValue = cast( Reflect.field(graph, this.defaultAttrHashName) ).get(attrName);
					graph = graph.parentGraph;
				} else {
					break;
				}
			}
		} else
			attrValue = this.attrs.get(attrName);
			
		if (attrValue != null && escString) {
			var me = this;
			attrValue = this.escStringMatchRe.customReplace( attrValue, function( r:EReg ) {
				return switch( r.matched(1) ) {
					case 'N', 'E': me.name;
					case 'T': cast(me,VizEdge).tailNode;
					case 'H': cast(me,VizEdge).headNode;
					case 'G': me.immediateGraph.name;
					case 'L': me.getAttr('label', true);
				}
			});
		}
		return attrValue;
	}
	
	public function draw(ctx:Graphics, ctxScale:Float, redrawCanvasOnly:Bool) {
		
		var i, tokens, fillColor;
		var strokeColor = {color:this.viz.lineColor, alpha:1.0};
		var fontSize:Int = 12;
		var fontFamily:String = 'Times New Roman';
		var path:Path = null;
		var filled = false;
		var bbDiv:Sprite = null;
		if (!redrawCanvasOnly) {
			this.initBB();
		}
		for (drawAttr in drawAttrs) {
			var command = drawAttr;
			var tokenizer = new VizTokenizer(command);
			var token = tokenizer.takeChar();
			if (token != null && token != '') {
				var dashStyle = 'solid';
				while (token != null && token != '') {
					switch (token) {
						case 'E', // filled ellipse
							 'e': // unfilled ellipse
							filled = ('E' == token);
							var cx = tokenizer.takeNumber();
							var cy = this.viz.height - tokenizer.takeNumber();
							var rx = tokenizer.takeNumber();
							var ry = tokenizer.takeNumber();
							path = new Ellipse(cx, cy, rx, ry);
						case 'P', // filled polygon
							 'p', // unfilled polygon
							 'L': // polyline
							filled = ('P' == token);
							var closed = ('L' != token);
							var numPoints = Std.int(tokenizer.takeNumber());
							tokens = tokenizer.takeNumbers(2 * numPoints); // points
							path = new Path();
							for (i in 1...numPoints) {
								var indx = i * 2;
								path.addBezier([
									new Point(tokens[indx - 2], this.viz.height - tokens[indx - 1]),
									new Point(tokens[indx],     this.viz.height - tokens[indx + 1])
								]);
							}
							if (closed) {
								path.addBezier([
									new Point(tokens[2 * numPoints - 2], this.viz.height - tokens[2 * numPoints - 1]),
									new Point(tokens[0],                 this.viz.height - tokens[1])
								]);
							}
						case 'B', // unfilled b-spline
							 'b': // filled b-spline
							filled = ('b' == token);
							var numPoints = Std.int(tokenizer.takeNumber());
							tokens = tokenizer.takeNumbers(2 * numPoints); // points
							path = new Path();
							var i = 2;
							while (i < 2 * numPoints) {
								path.addBezier([
									new Point(tokens[i - 2], this.viz.height - tokens[i - 1]),
									new Point(tokens[i],     this.viz.height - tokens[i + 1]),
									new Point(tokens[i + 2], this.viz.height - tokens[i + 3]),
									new Point(tokens[i + 4], this.viz.height - tokens[i + 5])
								]);
								i += 6;
							}
						case 'I': // image
							var l = tokenizer.takeNumber();
							var b = this.viz.height - tokenizer.takeNumber();
							var w = tokenizer.takeNumber();
							var h = tokenizer.takeNumber();
							var src = tokenizer.takeString();
							if (!this.viz.images.exists(src)) {
								this.viz.images.set(src, new VizImage(this.viz, src));
							}
							this.viz.images.get(src).draw(ctx, l, b - h, w, h);
						case 'T': // text
							var l = tokenizer.takeNumber();
							var t = this.viz.height - tokenizer.takeNumber();
							var textAlign = tokenizer.takeNumber();
							var textWidth = Math.round(ctxScale * tokenizer.takeNumber());
							var str = tokenizer.takeString();
							
							if (!redrawCanvasOnly && !(~/^\s*$/.match(str)) ) {
								str = StringTools.htmlEscape(str);
								var matches:Bool;
								var r:EReg;
								do {
									r = ~/ ( +)/;
									matches = r.match(str);
									if (matches) {
										var spaces = ' ';
										for (i in 0...r.matched(1).length) {
											spaces += '&nbsp;';
										}
										str = ~/  +/.replace(str, spaces);
									}
								} while (matches);
								
								// TODO: add href etc
								/*
								var text;
								var url = this.getAttr('URL', true);
								var href = url != null ? url : this.getAttr('href', true);
								if (href != null && href != '') {
									var tmpTarget = this.getAttr('target', true);
									var target = tmpTarget != null ? tmpTarget : '_self';
									var tmpTooltip = this.getAttr('tooltip', true);
									var tooltip = tmpTooltip != null ? tmpTooltip : this.getAttr('label', true);
//									debug(this.name + ', href ' + href + ', target ' + target + ', tooltip ' + tooltip);
									
									text = new Element('a', {href: href, target: target, title: tooltip});
									['onclick', 'onmousedown', 'onmouseup', 'onmouseover', 'onmousemove', 'onmouseout'].each(function(attrName) {
										var attrValue = this.getAttr(attrName, true);
										if (attrValue != null) {
											text.writeAttribute(attrName, attrValue);
										}
									}.bind(this));
									text.setStyle({
										textDecoration: 'none'
									});
								} else {
									//text = new Element('span');
								}
								*/
								var preText = '<P ALIGN="CENTER"><FONT';
								preText += ' SIZE="' + Std.string( fontSize ) + '"';
								preText += ' COLOR="#' + StringTools.hex(strokeColor.color, 6) + '"';
								if (fontFamily != null && fontFamily != '')
									preText += ' FACE="' + fontFamily + '"';
								preText += '>';
								var postText = '</FONT></P>';
								
								// TODO: improve positioning
								/*
								text.update(str);
								text.setStyle({
									fontSize: Math.round(fontSize * ctxScale * this.viz.bbScale) + 'px',
									fontFamily: fontFamily,
									color: strokeColor.textColor,
									position: 'absolute',
									textAlign: (-1 == textAlign) ? 'left' : (1 == textAlign) ? 'right' : 'center',
									left: (l - (1 + textAlign) * textWidth) + 'px',
									top: t + 'px',
									width: (2 * textWidth) + 'px'
								});
								if (1 != strokeColor.opacity) text.setOpacity(strokeColor.opacity);
								this.viz.elements.appendChild(text);
								*/
								var tf:TextField = new TextField();
								tf.autoSize = TextFieldAutoSize.CENTER;
								tf.htmlText = preText + str + postText;
								tf.x = l - tf.width/2;
								tf.y = t - tf.height*5/6;
								this.viz.canvas.addChild(tf);
							}
							
							
						case 'C', // set fill color
							 'c': // set pen color
							var fill = ('C' == token);
							var color = this.parseColorFlash(tokenizer.takeString());
							if (fill) {
								fillColor = color;
								ctx.beginFill(color.color, color.alpha);
								this.viz.fillStyle = color.color;
							} else {
								strokeColor = color;
								ctx.lineStyle(this.viz.lineWidth, color.color, color.alpha);
								this.viz.strokeStyle = color.color;
							}
						case 'F': // set font
							fontSize = Std.int(tokenizer.takeNumber());
							fontFamily = tokenizer.takeString();
							switch (fontFamily) {
								case 'Times-Roman':
									fontFamily = 'Times New Roman';
								case 'Courier':
									fontFamily = 'Courier New';
								case 'Helvetica':
									fontFamily = 'Arial';
								default:
									// nothing
							}
						case 'S': // set style
							var style = tokenizer.takeString();
							switch (style) {
								case 'solid', 'filled': // nothing
								case 'dashed', 'dotted':
									dashStyle = style;
								case 'bold':
									this.viz.lineWidth = 2;
									ctx.lineStyle(this.viz.lineWidth, this.viz.lineColor, this.viz.lineAlpha);
								default:
									var r = ~/^setlinewidth\((.*)\)$/;
									var matches = r.match(style);
									if (matches) {
										this.viz.lineWidth = Std.parseFloat(r.matched(1));
										ctx.lineStyle(this.viz.lineWidth, this.viz.lineColor, this.viz.lineAlpha);
									} else {
										//Logger.log('unknown style ' + style);
									}
							}
						default:
							//Logger.log('unknown token ' + token);
							return;
					}
					if (path != null) {
						this.viz.drawPath(ctx, path, filled, dashStyle);
						if (!redrawCanvasOnly) this.bbRect.expandToInclude(path.getBB());
						path = null;
					}
					token = tokenizer.takeChar();
				}
				this.viz.lineWidth = 1.0;
			}
		}
	}
	
	public function parseColorFlash(color:String) {
		var c = color.split("#").join("");
		var col = Std.parseInt('0x' + c.substr(0, 6));
		var alpha = 1.0;
		if (c.length > 6)
			alpha = Std.parseInt('0x' + c.substr( -2)) / 255.0;
		return { color:col, alpha:alpha };
	}
	
	public function parseColor(color:String) {
		var parsedColor = {opacity: 1.0, canvasColor: '', textColor: ''};
		// rgb/rgba
		if (~/^#(?:[0-9a-f]{2}\s*){3,4}$/i.match(color)) {
			return this.viz.parseHexColor(color);
		}
		// hsv
		var hsvRe = ~/^(\d+(?:\.\d+)?)[\s,]+(\d+(?:\.\d+)?)[\s,]+(\d+(?:\.\d+)?)$/;
		var matches = hsvRe.match(color);
		if (matches) {
			parsedColor.canvasColor = parsedColor.textColor = this.viz.hsvToRgbColor(
				Std.parseInt(hsvRe.matched(1)), Std.parseInt(hsvRe.matched(2)), Std.parseInt(hsvRe.matched(3))
			);
			return parsedColor;
		}
		// named color
		var colAtt = this.getAttr('colorscheme');
		var colorScheme = colAtt != null ? colAtt : 'X11';
		var colorName = color;
		var namedColRe = ~/^\/(.*)\/(.*)$/;
		matches = namedColRe.match(color);
		if (matches) {
			if (namedColRe.matched(1) != null && namedColRe.matched(1) != '') {
				colorScheme = namedColRe.matched(1);
			}
			colorName = namedColRe.matched(2);
		} else {
			var r = ~/^\/(.*)$/;
			matches = r.match(color);
			if (matches) {
				colorScheme = 'X11';
				colorName = r.matched(1);
			}
		}
		colorName = colorName.toLowerCase();
		var colorData = '';
		var colorSchemeData = null;
		var colorSchemeName = colorScheme.toLowerCase();
		if (this.viz.colors.exists(colorSchemeName)) {
			colorSchemeData = this.viz.colors.get(colorSchemeName);
			if (colorSchemeData.exists(colorName)) {
				colorData = colorSchemeData.get(colorName);
				return this.viz.parseHexColor('#' + colorData);
			}
		}
		if (this.viz.colors.get('fallback').exists(colorName)) {
			colorData = this.viz.colors.get('fallback').get(colorName);
			return this.viz.parseHexColor('#' + colorData);
		}
		if (colorSchemeData == null) {
			//Logger.log('unknown color scheme ' + colorScheme);
		}
		// unknown
		//Logger.log('unknown color ' + color + '; color scheme is ' + colorScheme);
		parsedColor.canvasColor = parsedColor.textColor = '#000000';
		return parsedColor;
	}
	
}

class VizNode extends VizEntity {
	
	public function new(name, viz, rootGraph, parentGraph) {
		super('nodeAttrs', name, viz, rootGraph, parentGraph, parentGraph);
		escStringMatchRe = new EReg('([NGL])', 'g');
	}
}

class VizEdge extends VizEntity {
	
	public var tailNode:String;
	public var headNode:String;
	
	public function new(name:String, viz:Viz, rootGraph, parentGraph, tailNode, headNode) {
		super('edgeAttrs', name, viz, rootGraph, parentGraph, parentGraph);
		this.tailNode = tailNode;
		this.headNode = headNode;
		escStringMatchRe = new EReg('([EGTHL])', 'g');
	}
	
}

class VizGraph extends VizEntity {
	
	public var subgraphs:Array<VizGraph>;
	public var strict:Bool;
	public var type:String;
	public var nodes:Array<VizNode>;
	public var edges:Array<VizEdge>;
	public var nodeAttrs:Hash<String>;
	public var edgeAttrs:Hash<String>;
	
	public function new(name:String, viz:Viz, ?rootGraph, ?parentGraph) {
		super('attrs', name, viz, rootGraph, parentGraph, this);
		nodes = [];
		edges = [];
		subgraphs = [];
		nodeAttrs = new Hash();
		edgeAttrs = new Hash();
		escStringMatchRe = new EReg('([GL])', 'g');
	}
	
	override public function initBB() {
		var coords = this.getAttr('bb').split(',');
		this.bbRect = new Rect(
			Std.parseFloat(coords[0]), this.viz.height - Std.parseFloat(coords[1]), 
			Std.parseFloat(coords[2]), this.viz.height - Std.parseFloat(coords[3])
		);
	}
	
	override public function draw(ctx:Graphics, ctxScale:Float, redrawCanvasOnly:Bool) {
		super.draw(ctx, ctxScale, redrawCanvasOnly);
		for (node in nodes)
			node.draw(ctx, ctxScale, redrawCanvasOnly);
		for (subgraph in subgraphs)
			subgraph.draw(ctx, ctxScale, redrawCanvasOnly);
		for (edge in edges)
			edge.draw(ctx, ctxScale, redrawCanvasOnly);
	}
}

class Viz {
	
	static var idMatch:String = '([a-zA-Z\x80-\xffff_][0-9a-zA-Z\x80-\xffff_]*|-?(?:\\.\\d+|\\d+(?:\\.\\d*)?)|"(?:\\\\"|[^"])*"|<(?:<[^>]*>|[^<>]+?)+>)';
	static var nodeIdMatch:String = idMatch + '(?::' + idMatch + ')?(?::' + idMatch + ')?';
	static var graphMatchRe:EReg = new EReg('^(strict\\s+)?(graph|digraph)(?:\\s+' + idMatch + ')?\\s*{$', 'i');
	static var subgraphMatchRe:EReg = new EReg('^(?:subgraph\\s+)?' + idMatch + '?\\s*{$', 'i');
	static var nodeMatchRe:EReg = new EReg('^(' + nodeIdMatch + ')\\s+\\[(.+)\\];$','');
	static var edgeMatchRe:EReg = new EReg('^(' + nodeIdMatch + '\\s*-[->]\\s*' + nodeIdMatch + ')\\s+\\[(.+)\\];$','');
	static var attrMatchRe:EReg = new EReg('^' + idMatch + '=' + idMatch + '(?:[,\\s]+|$)', '');
		
	public static function main() {
		new Viz();
	}
	
	public var maxXdotVersion:String;
	public var imagePath:String;
	public var scale:Float;
	public var padding:Float;
	public var dashLength:Float;
	public var dotSpacing:Float;
	public var images:Hash<VizImage>;
	public var numImages:Int;
	public var numImagesFinished:Int;
	
	public var canvas:Sprite;
	public var colors:Hash<Hash<String>>;
	
	public var loader:URLLoader;
	
	public var lineWidth:Float;
	public var lineColor:Int;
	public var lineAlpha:Float;
	public var dashStyle:String;
	public var fillStyle:Int;
	public var strokeStyle:Int;
	public var lineCap:flash.display.CapsStyle;
	
	public function new() {
		
		maxXdotVersion = '1.2';
		colors = new Hash();
		
		var fallBackHash = new Hash<String>();
		fallBackHash.set('black', '000000');
		fallBackHash.set('lightgrey', 'd3d3d3');
		fallBackHash.set('white', 'ffffff');
		colors.set('fallback', fallBackHash);
		
		imagePath = "";
		scale = 1.0;
		padding = 8.0;
		dashLength = 6.0;
		dotSpacing = 4.0;
		images = new Hash();
		numImages = 0;
		numImagesFinished = 0;
		
		lineWidth = 1.0;
		lineColor = 0xffffff;
		lineAlpha = 1.0;
		fillStyle = strokeStyle = 0xffffff;
		dashStyle = 'solid';
		lineCap = flash.display.CapsStyle.ROUND;
		
		Lib.current.stage.scaleMode = StageScaleMode.NO_SCALE;
		canvas = new Sprite();
		Lib.current.addChild(canvas);
		
		var inputUrl = Reflect.field( Reflect.field( Reflect.field(Lib.current, "loaderInfo"), "parameters" ), "input");
		
		loader = new URLLoader();
		loader.addEventListener(Event.COMPLETE, loaded);
		//var url = "../../bin/cluster.gv.xdot";
		//loader.load(new URLRequest(url));
		loader.load(new URLRequest(inputUrl));
	}
	
	function loaded( e : Event ) {
		parse( e.target.data );
	}
	
	// parse props
	public var graphs:Array<VizGraph>;
	public var width:Float;
	public var height:Float;
	public var maxWidth:Float;
	public var maxHeight:Float;
	public var bbEnlarge:Bool;
	public var bbScale:Float;
	public var dpi:Float;
	public var bgcolor:{color:Int,alpha:Float};
	
	public function parse(xdot:String) {
		graphs = [];
		width = 0.0;
		height = 0.0;
		maxWidth = -1.0;
		maxHeight = -1.0;
		bbEnlarge = false;
		bbScale = 1.0;
		dpi = 96;
		bgcolor = {
			color: 0xffffff,
			alpha:1.0
		};
		var xdotRe:EReg = ~/\r?\n/;
		//var lines = xdotRe.split(xdot);
		var lines = xdot.split("\r").join("").split("\n");
		var i = 0;
		var entity:VizEntity;
		var rootGraph:VizGraph = null;
		var attrs:String = "";
		var drawAttrHash = new Hash<String>();
		var attrHash = new Hash<String>();
		var isGraph = false;
		var entityName = "";
		var line, lastChar, matches, attrName, attrValue;
		var containers = new Array<VizGraph>();
		while (i < lines.length) {
			var r : EReg = ~/^\s+/;
			line = r.replace(lines[i++], '');
			if ('' != line && '#' != line.substr(0, 1)) {
				while (i < lines.length && ';' != (lastChar = line.substr(-1)) && '{' != lastChar && '}' != lastChar) {
					if ('\\' == lastChar) {
						line = line.substr(0, line.length - 1);
					}
					line += lines[i++];
				}
				if (0 == containers.length) {
					matches = graphMatchRe.match(line);
					if (matches) {
						rootGraph = new VizGraph(graphMatchRe.matched(3), this);
						containers.unshift(rootGraph);
						containers[0].strict = (null != graphMatchRe.matched(1));
						containers[0].type = ('graph' == graphMatchRe.matched(2)) ? 'undirected' : 'directed';
						containers[0].attrs.set('xdotversion', '1.0');
						graphs.push(containers[0]);
					}
				} else {
					matches = subgraphMatchRe.match(line);
					if (matches) {
						containers.unshift( new VizGraph(subgraphMatchRe.matched(1), this, rootGraph, containers[0]) );
						containers[1].subgraphs.push(containers[0]);
					}
				}
				if (matches) {
					//Logger.log('begin container ' + containers[0].name);
				} else if ('}' == line) {
					//Logger.log('end container ' + containers[0].name);
					containers.shift();
					if (0 == containers.length) {
						break;
					}
				} else {
					matches = nodeMatchRe.match(line);
					if (matches) {
						entityName = nodeMatchRe.matched(2);
						attrs = nodeMatchRe.matched(5);
						drawAttrHash = containers[0].drawAttrs;
						isGraph = false;
						switch (entityName) {
							case 'graph':
								attrHash = containers[0].attrs;
								isGraph = true;
							case 'node':
								attrHash = containers[0].nodeAttrs;
							case 'edge':
								attrHash = containers[0].edgeAttrs;
							default:
								entity = new VizNode(entityName, this, rootGraph, containers[0]);
								attrHash = entity.attrs;
								drawAttrHash = entity.drawAttrs;
								containers[0].nodes.push(cast(entity,VizNode));
						}
					} else {
						matches = edgeMatchRe.match(line);
						if (matches) {
							entityName = edgeMatchRe.matched(1);
							attrs = edgeMatchRe.matched(8);
							entity = new VizEdge(entityName, this, rootGraph, containers[0], edgeMatchRe.matched(2), edgeMatchRe.matched(5));
							attrHash = entity.attrs;
							drawAttrHash = entity.drawAttrs;
							containers[0].edges.push(cast(entity,VizEdge));
						}
					}
					if (matches) {
						do {
							if (0 == attrs.length)
								break;
							matches = attrMatchRe.match(attrs);
							if (matches) {
								attrs = attrs.substr(attrMatchRe.matched(0).length);
								attrName = attrMatchRe.matched(1);
								attrValue = unescape(attrMatchRe.matched(2));
								if (~/^_.*draw_$/.match(attrName)) {
									drawAttrHash.set(attrName, attrValue);
								} else {
									attrHash.set(attrName, attrValue);
								}
								if (isGraph && 1 == containers.length) {
									switch (attrName) {
										case 'bb':
											var bb = attrValue.split(',');
											width  = Std.parseFloat(bb[2]);
											height = Std.parseFloat(bb[3]);
										case 'bgcolor':
											bgcolor = rootGraph.parseColorFlash(attrValue);
										case 'dpi':
											dpi = Std.parseFloat( attrValue );
										case 'size':
											var sizeRe:EReg = ~/^(\d+|\d*(?:\.\d+)),\s*(\d+|\d*(?:\.\d+))(!?)$/;
											var size = sizeRe.match(attrValue);
											if (size) {
												maxWidth  = 72 * Std.parseFloat(sizeRe.matched(1));
												maxHeight = 72 * Std.parseFloat(sizeRe.matched(2));
												bbEnlarge = ('!' == sizeRe.matched(3));
											} else {
												//Logger.log('can\'t parse size');
											}
										case 'xdotversion':
											if (0 > this.versionCompare(this.maxXdotVersion, attrHash.get('xdotversion'))) {
												//Logger.log('unsupported xdotversion ' + attrHash.get('xdotversion') + '; ' +
												//	'this script currently supports up to xdotversion ' + this.maxXdotVersion);
											}
									}
								}
							} else {
								//Logger.log('can\'t read attributes for entity ' + entityName + ' from ' + attrs);
							}
						} while (matches);
					}
				}
			}
		}
		draw();
	}
	
	function draw(?redrawCanvasOnly:Bool = false) {
		
		var ctxScale = this.scale * this.dpi / 72;
		var width  = Math.round(ctxScale * this.width  + 2 * this.padding);
		var height = Math.round(ctxScale * this.height + 2 * this.padding);
		if (!redrawCanvasOnly) {
			this.canvas.width  = width;
			this.canvas.height = height;
			while (canvas.numChildren > 0)
				canvas.removeChildAt(0);
			this.canvas.graphics.clear();
		}
		canvas.x = canvas.y = this.padding;
		canvas.scaleX = canvas.scaleY = ctxScale;
		canvas.graphics.lineStyle(lineWidth, lineColor, lineAlpha, null, null, lineCap);
		graphs[0].draw(canvas.graphics, ctxScale, redrawCanvasOnly);
		
		var maxScale = 1.0;
		if (maxWidth != -1.0 && (canvas.width + 2 * padding) > maxWidth) {
			maxScale = maxWidth / (canvas.width + 2 * padding);
		}
		if (maxHeight != -1.0 && (canvas.height + 2 * padding) > maxHeight) {
			var tmp = maxHeight / (canvas.height + 2 * padding);
			if (tmp < maxScale)
				maxScale = tmp;
		}
		
		if (maxScale == 1.0) {
			var stageW = canvas.stage.stageWidth;
			var stageH = canvas.stage.stageHeight;
			if (stageW < canvas.width || stageH < canvas.height) {
				var scaleFactor = stageW / canvas.width;
				if ((stageH / canvas.height) < scaleFactor)
					scaleFactor = stageH / canvas.height;
				canvas.scaleX = scaleFactor;
				canvas.scaleY = scaleFactor;
			}
		} else {
			canvas.width *= ctxScale * maxScale;
			canvas.height *= ctxScale * maxScale;
		}
	}
	
	public function drawPath(ctx:Graphics, path:Path, filled:Bool, dashStyle:String) {
		if (filled) {
			path.makePath(ctx);
			ctx.endFill();
		}
		if (this.fillStyle != this.strokeStyle || !filled)  {
			var oldLineWidth = -999.0;
			switch (dashStyle) {
				case 'dashed':
					path.makeDashedPath(ctx, this.dashLength);
				case 'dotted':
					oldLineWidth = this.lineWidth;
					this.lineWidth *= 2;
					ctx.lineStyle(lineWidth, lineColor, lineAlpha);
					path.makeDottedPath(ctx, this.dotSpacing);
				default: // 'solid', etc
					if (!filled) {
						path.makePath(ctx);
					}
			}
			if (oldLineWidth != -999.0) {
				this.lineWidth = oldLineWidth;
				ctx.lineStyle(lineWidth, lineColor, lineAlpha);
			}
		}
	}
	
	function unescape(str:String) :String {
		var r:EReg = ~/^"(.*)"$/;
		var matches = r.match(str);
		if (matches) {
			return ~/\\"/g.replace(r.matched(1), '"');
		} else {
			return str;
		}
	}
	
	public function parseHexColor(color:String) {
		var r:EReg = ~/^#([0-9a-f]{2})\s*([0-9a-f]{2})\s*([0-9a-f]{2})\s*([0-9a-f]{2})?$/i;
		var matches = r.match(color);
		var canvasColor:String = '0xff00ff'; // own default
		var textColor = '#' + r.matched(1) + r.matched(2) + r.matched(3);
		var opacity = 1.0;
		if (matches) {
			if (r.matched(4) != null) { // rgba
				opacity = Std.parseInt('0x'+r.matched(4)) / 255;
				canvasColor = 'rgba(' + Std.string(Std.parseInt('0x' + r.matched(1))) + ',' + Std.string(Std.parseInt('0x' + r.matched(2))) + ',' + 
					Std.string(Std.parseInt('0x'+r.matched(3))) + ',' + Std.string(opacity) + ')';
			} else { // rgb
				canvasColor = textColor;
			}
		}
		return {canvasColor: canvasColor, textColor: textColor, opacity: opacity};
	}
	
	public function hsvToRgbColor(h:Int, s:Int, v:Int) {
		var i:Int;
		var f, p, q, t;
		var r:Float = 0xff, g:Float = 0xff, b:Float = 0xff;
		h *= 360;
		i = Math.floor(h / 60) % 6;
		f = h / 60 - i;
		p = v * (1 - s);
		q = v * (1 - f * s);
		t = v * (1 - (1 - f) * s);
		switch (i) {
			case 0: r = v; g = t; b = p;
			case 1: r = q; g = v; b = p;
			case 2: r = p; g = v; b = t;
			case 3: r = p; g = q; b = v;
			case 4: r = t; g = p; b = v;
			case 5: r = v; g = p; b = q;
		}
		return 'rgb(' + Math.round(255 * r) + ',' + Math.round(255 * g) + ',' + Math.round(255 * b) + ')';
	}
	
	function versionCompare(a:String, b:String):Int {
		var arr = a.split('.');
		var brr = b.split('.');
		var a1, b1;
		while (arr.length > 0 || brr.length > 0) {
			a1 = arr.length > 0 ? arr.shift() : '0';
			b1 = brr.length > 0 ? brr.shift() : '0';
			if (a1 < b1) return -1;
			if (a1 > b1) return 1;
		}
		return 0;
	}
}

class VizImage {
	
	var viz:Viz;
	var src:String;
	var finished:Bool;
	var loaded:Bool;
	var img:String;
	
	public function new(viz:Viz, src:String) {
		this.viz = viz;
		this.src = src;
		finished = true;
		loaded = false;
	}
	
	public function draw(ctx:Graphics, l:Float, t:Float, w:Float, h:Float) {
		if (this.finished) {
			if (this.loaded) {
				//drawImage(ctx, this.img, l, t, w, h);
				//Logger.log("draw: loaded");
			} else {
				this.drawBrokenImage(ctx, l, t, w, h);
			}
		}
	}
	
	public function drawBrokenImage(ctx:Graphics, l:Float, t:Float, w:Float, h:Float) {
		//Logger.log("drawBrokenImage");
	}
}

class Logger {
	
	#if flash
	static var t:flash.text.TextField;
	public static function log(msg:String) {
		if (t == null) {
			t = new flash.text.TextField();
			t.width = t.height = 400.;
			flash.Lib.current.addChild(t);
		}
		t.text += msg + "\n";
	}
	#else
	public static function log(msg:String) {
		trace(msg + "\n");
	}
	#end
}
