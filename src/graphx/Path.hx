package graphx;

import flash.display.Graphics;

class Point {
	
	public var x : Float;
	public var y : Float;
	
	public function new(x:Float, y:Float) {
		this.x = x;
		this.y = y;
	}
	
	public function offset(dx:Float, dy:Float) {
		x += dx;
		y += dy;
	}
	
	public function distanceFrom(point:Point) {
		var dx = x - point.x;
		var dy = y - point.y;
		return Math.sqrt(dx * dx + dy * dy);
	}
	
	public function makePath(ctx:Graphics) {
		ctx.moveTo(x, y);
		ctx.lineTo(x + 1, y);
	}
}

class Bezier {
	
	public var points : Array<Point>;
	public var order : Int;
	
	public function new(points:Array<Point>) {
		this.points = points;
		this.order = points.length;
		var me = this;
		pathCommands = [
			null,
			// This will have an effect if there's a line thickness or end cap.
			function(ctx:Graphics, x:Float, y:Float) {
				ctx.lineTo(x + 0.001, y);
			},
			function(ctx:Graphics, x:Float, y:Float) {
				ctx.lineTo(x, y);
			},
			function(ctx:Graphics, x1:Float, y1:Float, x2:Float, y2:Float) {
				ctx.curveTo(x1, y1, x2, y2);
			},
			function(ctx:Graphics, x1:Float, y1:Float, x2:Float, y2:Float, x3:Float, y3:Float) {
				me.bezierCurveTo(ctx, x1, y1, x2, y2, x3, y3);
			}
		];
	}
	
	// from Timothee Groleau : Bezier_lib.as - v1.2 - 19/05/02
	// http://www.timotheegroleau.com/Flash/articles/cubic_bezier/bezier_lib.as
	//
	// Add a drawCubicBezier2 to the movieClip prototype based on a MidPoint 
	// simplified version of the midPoint algorithm by Helen Triolo
	//
	// This function will trace a cubic approximation of the cubic Bezier
	// It will calculate a serie of [control point/Destination point] which 
	// will be used to draw quadratic Bezier starting from P0
	public function bezierCurveTo(ctx:Graphics, x1:Float, y1:Float, x2:Float, y2:Float, x3:Float, y3:Float) {
		var x0 = this.points[0].x;
		var y0 = this.points[0].y;
		
		// calculates the useful base points
		var ptA = getPointOnSegment(x0, y0, x1, y1, 3/4);
		var ptB = getPointOnSegment(x3, y3, x2, y2, 3/4);
		
		// get 1/16 of the [P3, P0] segment
		var dx = (x3 - x0) / 16;
		var dy = (y3 - y0) / 16;
		
		// calculates control point 1
		var ptC_1 = getPointOnSegment(x0, y0, x1, y1, 3/8);
		
		// calculates control point 2
		var ptC_2 = getPointOnSegment(ptA.x, ptA.y, ptB.x, ptB.y, 3/8);
		ptC_2.x -= dx;
		ptC_2.y -= dy;
		
		// calculates control point 3
		var ptC_3 = getPointOnSegment(ptB.x, ptB.y, ptA.x, ptA.y, 3/8);
		ptC_3.x += dx;
		ptC_3.y += dy;
		
		// calculates control point 4
		var ptC_4 = getPointOnSegment(x3, y3, x2, y2, 3/8);
		
		// calculates the 3 anchor points
		var Pa_1 = getMiddle(ptC_1.x, ptC_1.y, ptC_2.x, ptC_2.y);
		var Pa_2 = getMiddle(ptA.x, ptA.y, ptB.x, ptB.y);
		var Pa_3 = getMiddle(ptC_3.x, ptC_3.y, ptC_4.x, ptC_4.y);
		
		// draw the four quadratic subsegments
		ctx.curveTo(ptC_1.x, ptC_1.y, Pa_1.x, Pa_1.y);
		ctx.curveTo(ptC_2.x, ptC_2.y, Pa_2.x, Pa_2.y);
		ctx.curveTo(ptC_3.x, ptC_3.y, Pa_3.x, Pa_3.y);
		ctx.curveTo(ptC_4.x, ptC_4.y, x3, y3);
	}
	
	// from Timothee Groleau : Bezier_lib.as - v1.2 - 19/05/02
	// return a point on a segment [P0, P1] which distance from P0
	// is ratio of the length [P0, P1]
	public function getPointOnSegment(x0:Float, y0:Float, x1:Float, y1:Float, ratio:Float) {
		return { x : (x0 + ((x1 - x0) * ratio)), y : (y0 + ((y1 - y0) * ratio)) };
	}
	
	// from Timothee Groleau : Bezier_lib.as - v1.2 - 19/05/02
	// return the middle of a segment define by two points
	public function getMiddle(x0:Float, y0:Float, x1:Float, y1:Float) {
		return { x : ((x0 + x1) / 2), y : ((y0 + y1) / 2) };
	}
	
	public function offset(dx:Float, dy:Float) {
		for (point in points)
			point.offset(dx, dy);
	}
	
	public function getBB() {
		if (this.order == 0)
			return null;
		var l, t, r, b, p = points[0];
		l = r = p.x;
		t = b = p.y;
		for (point in points) {
			l = Math.min(l, point.x);
			t = Math.min(t, point.y);
			r = Math.max(r, point.x);
			b = Math.max(b, point.y);
		}
		return new Rect(l, t, r, b);
	}
	
	public function isPointInBB(x:Float, y:Float, ?tolerance=0) {
		var bb = getBB();
		if (0 < tolerance) {
			bb = bb.clone();
			bb.inset(-tolerance, -tolerance);
		}
		return !(x < bb.l || x > bb.r || y < bb.t || y > bb.b);
	}
	
	public function isPointOnBezier(x:Float, y:Float, ?tolerance=0) {
		if (!this.isPointInBB(x, y, tolerance))
			return false;
		var segments = chordPoints();
		var p1 = segments[0].p;
		var p2, x1, y1, x2, y2, bb, twice_area, base, height;
		for (segment in segments) {
			p2 = segment.p;
			x1 = p1.x;
			y1 = p1.y;
			x2 = p2.x;
			y2 = p2.y;
			bb = new Rect(x1, y1, x2, y2);
			if (bb.isPointInBB(x, y, tolerance)) {
				twice_area = Math.abs(x1 * y2 + x2 * y + x * y1 - x2 * y1 - x * y2 - x1 * y);
				base = p1.distanceFrom(p2);
				height = twice_area / base;
				if (height <= tolerance)
					return true;
			}
			p1 = p2;
		}
		return false;
	}
	
	// Based on Oliver Steele's bezier.js library.
	public function controlPolygonLength() {
		var len:Float = 0;
		for (i in 1...this.order)
			len += this.points[i - 1].distanceFrom(this.points[i]);
		return len;
	}
	
	// Based on Oliver Steele's bezier.js library.
	public function chordLength() {
		return this.points[0].distanceFrom(this.points[this.order - 1]);
	}
	
	// From Oliver Steele's bezier.js library.
	public function triangle() {
		var upper = this.points;
		var m = [upper];
		for (i in 1...this.order) {
			var lower = [];
			for (j in 0...this.order-i) {
				var c0 = upper[j];
				var c1 = upper[j + 1];
				lower[j] = new Point((c0.x + c1.x) / 2, (c0.y + c1.y) / 2);
			}
			m.push(lower);
			upper = lower;
		}
		return m;
	}
	
	// Based on Oliver Steele's bezier.js library.
	public function triangleAtT(t:Float) {
		var s = 1 - t;
		var upper = this.points;
		var m = [upper];
		for (i in 1...this.order) {
			var lower = [];
			for (j in 0...this.order-i) {
				var c0 = upper[j];
				var c1 = upper[j + 1];
				lower[j] = new Point(c0.x * s + c1.x * t, c0.y * s + c1.y * t);
			}
			m.push(lower);
			upper = lower;
		}
		return m;
	}
	
	// Returns two beziers resulting from splitting this bezier at t=0.5.
	// Based on Oliver Steele's bezier.js library.
	public function split(?t:Float=0.5) {
		var m = (0.5 == t) ? triangle() : triangleAtT(t);
		var leftPoints  = new Array<Point>();
		var rightPoints = new Array<Point>();
		for (i in 0...this.order) {
			leftPoints.push( m[i][0] );
			rightPoints.push( m[this.order - 1 - i][i] );
		}
		return {left: new Bezier(leftPoints), right: new Bezier(rightPoints)};
	}
	
	// Returns a bezier which is the portion of this bezier from t1 to t2.
	// Thanks to Peter Zin on comp.graphics.algorithms.
	public function mid(t1:Float, t2:Float) {
		return this.split(t2).left.split(t1 / t2).right;
	}
	
	// Returns points (and their corresponding times in the bezier) that form
	// an approximate polygonal representation of the bezier.
	// Based on the algorithm described in Jeremy Gibbons' dashed.ps.gz
	public function chordPoints() {
		return [ { tStart: 0.0, tEnd: 0.0, dt: 0.0, p: this.points[0] } ].concat(this._chordPoints(0, 1));
	}
	
	function _chordPoints(tStart:Float, tEnd:Float) {
		var tolerance = 0.001;
		var dt = tEnd - tStart;
		if (this.controlPolygonLength() <= (1 + tolerance) * this.chordLength()) {
			return [{tStart: tStart, tEnd: tEnd, dt: dt, p: this.points[this.order - 1]}];
		} else {
			var tMid = tStart + dt / 2;
			var halves = this.split();
			return halves.left._chordPoints(tStart, tMid).concat(halves.right._chordPoints(tMid, tEnd));
		}
	}
	
	// Returns an array of times between 0 and 1 that mark the bezier evenly
	// in space.
	// Based in part on the algorithm described in Jeremy Gibbons' dashed.ps.gz
	public function markedEvery(distance:Float, ?firstDistance:Float=-1.0) {
		var nextDistance = (firstDistance != -1.0) ? firstDistance : distance;
		var segments = chordPoints();
		var times = [];
		var t = 0.0; // time
		var dt = 0.0; // delta t
		var segment;
		var remainingDistance;
		for (i in 1...segments.length) {
			segment = segments[i];
			var segLen = segment.p.distanceFrom(segments[i - 1].p);
			if (0 == segLen) {
				t += segment.dt;
			} else {
				dt = nextDistance / segLen * segment.dt;
				var remainingSegLen = segLen;
				while (remainingSegLen >= nextDistance) {
					remainingSegLen -= nextDistance;
					t += dt;
					times.push(t);
					if (distance != nextDistance) {
						nextDistance = distance;
						dt = nextDistance / segLen * segment.dt;
					}
				}
				nextDistance -= remainingSegLen;
				t = segment.tEnd;
			}
		}
		return {times: times, nextDistance: nextDistance};
	}
	
	// Return the coefficients of the polynomials for x and y in t.
	// From Oliver Steele's bezier.js library.
	public function coefficients() {
		// This function deals with polynomials, represented as
		// arrays of coefficients.  p[i] is the coefficient of n^i.
		
		// p0, p1 => p0 + (p1 - p0) * n
		// side-effects (denormalizes) p0, for convienence
		var interpolate = function(p0:Array<Float>, p1:Array<Float>) {
			p0.push(0.0);
			var p = [p0[0]];
			for (i in 0...p1.length)
				p.push(p0[i + 1] + p1[i] - p0[i]);
			return p;
		}
		// folds +interpolate+ across a graph whose fringe is
		// the polynomial elements of +ns+, and returns its TOP
		var collapse = function(ns:Array<Array<Float>>) {
			while (ns.length > 1) {
				var ps = new Array<Array<Float>>();
				for (i in 0...ns.length-1)
					ps.push(interpolate(ns[i], ns[i + 1]));
				ns = ps;
			}
			return ns[0];
		}
		// xps and yps are arrays of polynomials --- concretely realized
		// as arrays of arrays
		var xps = [];
		var yps = [];
		for (pt in this.points) {
			xps.push([pt.x]);
			yps.push([pt.y]);
		}
		return {xs: collapse(xps), ys: collapse(yps)};
	}
	
	// Return the point at time t.
	// From Oliver Steele's bezier.js library.
	public function pointAtT(t:Float) {
		var c = coefficients();
		var cx = c.xs, cy = c.ys;
		// evaluate cx[0] + cx[1]t +cx[2]t^2 ....
		
		// optimization: start from the end, to save one
		// muliplicate per order (we never need an explicit t^n)
		
		// optimization: special-case the last element
		// to save a multiply-add
		var x = cx[cx.length - 1], y = cy[cy.length - 1];
		var i = cx.length - 1;
		while (--i >= 0) {
			x = x * t + cx[i];
			y = y * t + cy[i];
		}
		return new Point(x, y);
	}
	
	// Render the Bezier to a WHATWG 2D canvas context.
	// Based on Oliver Steele's bezier.js library.
	public function makePath(ctx, ?moveTo:Bool=true) {
		if (moveTo)
			ctx.moveTo(this.points[0].x, this.points[0].y);
		var fn:Dynamic = {call:this.pathCommands[this.order]};
		if (fn.call != null) {
			var coords = [];
			var start = 1 == this.order ? 0 : 1;
			for (i in start...this.points.length) {
				coords.push(this.points[i].x);
				coords.push(this.points[i].y);
			}
			var args = new Array<Dynamic>();
			args = args.concat([ctx]).concat(coords);
			Reflect.callMethod(fn, Reflect.field(fn, "call"), args);
		}
	}
	
	// Wrapper functions to work around Safari, in which, up to at least 2.0.3,
	// fn.apply isn't defined on the context primitives.
	// Based on Oliver Steele's bezier.js library.
	var pathCommands : Array<Dynamic>;
	
	public function makeDashedPath(ctx, dashLength, ?firstDistance, ?drawFirst:Bool = true) {
		if (firstDistance == null)
			firstDistance = dashLength;
		var markedEvery = this.markedEvery(dashLength, firstDistance);
		if (drawFirst)
			markedEvery.times.unshift(0);
		var drawLast = (markedEvery.times.length % 2) != 0;
		if (drawLast)
			markedEvery.times.push(1);
		var i = 1;
		while (i < markedEvery.times.length) {
			this.mid(markedEvery.times[i - 1], markedEvery.times[i]).makePath(ctx);
			i += 2;
		}
		return { firstDistance: markedEvery.nextDistance, drawFirst: drawLast };
	}
	
	public function makeDottedPath(ctx, dotSpacing, ?firstDistance:Float=-999.0) {
		if (firstDistance == -999.0)
			firstDistance = dotSpacing;
		var markedEvery = this.markedEvery(dotSpacing, firstDistance);
		if (dotSpacing == firstDistance)
			markedEvery.times.unshift(0);
		for (t in markedEvery.times)
			pointAtT(t).makePath(ctx);
		return markedEvery.nextDistance;
	}
}

class Path {
	
	public var segments:Array<Bezier>;
	
	public function new(?segments:Array<Bezier>=null) {
		this.segments = segments == null ? [] : segments;
	}
	
	public function setupSegments() {}
	
	// Based on Oliver Steele's bezier.js library.
	public function addBezier(points:Array<Point>) {
		this.segments.push( new Bezier(points) );
	}
	
	public function offset(dx, dy) {
		if (0 == this.segments.length)
			this.setupSegments();
		for (segment in segments)
			segment.offset(dx, dy);
	}
	
	public function getBB() {
		if (0 == this.segments.length)
			this.setupSegments();
		var l, t, r, b, p = this.segments[0].points[0];
		l = r = p.x;
		t = b = p.y;
		for (segment in segments) {
			for (point in segment.points) {
				l = Math.min(l, point.x);
				t = Math.min(t, point.y);
				r = Math.max(r, point.x);
				b = Math.max(b, point.y);
			}
		}
		return new Rect(l, t, r, b);
	}
	
	public function isPointInBB(x, y, ?tolerance=0) {
		var bb = this.getBB();
		if (0 < tolerance) {
			bb = bb.clone();
			bb.inset(-tolerance, -tolerance);
		}
		return !(x < bb.l || x > bb.r || y < bb.t || y > bb.b);
	}
	
	public function isPointOnPath(x, y, ?tolerance=0) {
		if (!this.isPointInBB(x, y, tolerance))
			return false;
		for (segment in segments)
			if (segment.isPointOnBezier(x, y, tolerance))
				return true;
		return false;
	}
	
	public function isPointInPath(x, y) {
		return false;
	}
	
	// Based on Oliver Steele's bezier.js library.
	public function makePath(ctx) {
		if (0 == this.segments.length)
			this.setupSegments();
		var moveTo = true;
		for (segment in segments) {
			segment.makePath(ctx, moveTo);
			moveTo = false;
		}
	}
	
	public function makeDashedPath(ctx, dashLength:Float, ?firstDistance:Float=-1.0, ?drawFirst=true) {
		if (0 == this.segments.length)
			this.setupSegments();
		var info = {
			drawFirst: drawFirst,
			firstDistance: (firstDistance != -1.0) ? firstDistance : dashLength
		};
		for (segment in segments) {
			info = segment.makeDashedPath(ctx, dashLength, info.firstDistance, Reflect.field(info, "drawFirst") );
		}
	}
	
	public function makeDottedPath(ctx, dotSpacing, ?firstDistance=-1.0) {
		if (0 == this.segments.length)
			this.setupSegments();
		if (firstDistance == -1.0)
			firstDistance = dotSpacing;
		for (segment in segments) {
			firstDistance = segment.makeDottedPath(ctx, dotSpacing, firstDistance);
		}
	}
}

class Polygon extends Path {
	
	public var points:Array<Point>;
	
	public function new(?points:Array<Point>=null) {
		this.points = points == null ? [] : points;
		super();
	}
	
	override public function setupSegments() {
		var i = 0;
		var next = 0;
		for (p in this.points) {
			next = i + 1;
			if (this.points.length == next) next = 0;
			this.addBezier([
				p,
				this.points[next]
			]);
			i++;
		}
	}
}

class Rect extends Polygon {
	
	public var l:Float;
	public var t:Float;
	public var r:Float;
	public var b:Float;
	
	public function new(l:Float, t:Float, r:Float, b:Float) {
		this.l = l;
		this.t = t;
		this.r = r;
		this.b = b;
		super();
	}
	
	public function clone() {
		return new Rect(l,t,r,b);
	}
	
	public function inset(ix, iy) {
		this.l += ix;
		this.t += iy;
		this.r -= ix;
		this.b -= iy;
		return this;
	}
	
	public function expandToInclude(rect:Rect) {
		this.l = Math.min(this.l, rect.l);
		this.t = Math.min(this.t, rect.t);
		this.r = Math.max(this.r, rect.r);
		this.b = Math.max(this.b, rect.b);
	}
	
	public function getWidth() {
		return this.r - this.l;
	}
	
	public function getHeight() {
		return this.b - this.t;
	}
	
	override public function setupSegments() {
		var w = this.getWidth();
		var h = this.getHeight();
		this.points = [
			new Point(this.l, this.t),
			new Point(this.l + w, this.t),
			new Point(this.l + w, this.t + h),
			new Point(this.l, this.t + h)
		];
		super.setupSegments();
	}
}

class Ellipse extends Path {
	
	public static var KAPPA : Float = 0.5522847498;
	
	var cx:Float;
	var cy:Float;
	var rx:Float;
	var ry:Float;
	
	public function new(cx:Float, cy:Float, rx:Float, ry:Float) {
		super();
		this.cx = cx; // center x
		this.cy = cy; // center y
		this.rx = rx; // radius x
		this.ry = ry; // radius y
	}
	
	override public function setupSegments() {
		this.addBezier([
			new Point(this.cx, this.cy - this.ry),
			new Point(this.cx + KAPPA * this.rx, this.cy - this.ry),
			new Point(this.cx + this.rx, this.cy - KAPPA * this.ry),
			new Point(this.cx + this.rx, this.cy)
		]);
		this.addBezier([
			new Point(this.cx + this.rx, this.cy),
			new Point(this.cx + this.rx, this.cy + KAPPA * this.ry),
			new Point(this.cx + KAPPA * this.rx, this.cy + this.ry),
			new Point(this.cx, this.cy + this.ry)
		]);
		this.addBezier([
			new Point(this.cx, this.cy + this.ry),
			new Point(this.cx - KAPPA * this.rx, this.cy + this.ry),
			new Point(this.cx - this.rx, this.cy + KAPPA * this.ry),
			new Point(this.cx - this.rx, this.cy)
		]);
		this.addBezier([
			new Point(this.cx - this.rx, this.cy),
			new Point(this.cx - this.rx, this.cy - KAPPA * this.ry),
			new Point(this.cx - KAPPA * this.rx, this.cy - this.ry),
			new Point(this.cx, this.cy - this.ry)
		]);
	}
}
