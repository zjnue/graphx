import neko.FileSystem;
import neko.io.File;
import neko.Sys;

class Convert {
	
	public static function main() {
		new Convert();
	}
	
	public function new() {
		
		var cwd = Sys.getCwd();
		var binPath = cwd + "../bin/";
		var graphsPath = cwd + "../graphs/";
		
		for ( fileName in FileSystem.readDirectory(graphsPath) ) {
			
			if (!Type.enumEq(FileSystem.kind(graphsPath + fileName), neko.FileKind.kfile) || fileName.indexOf(".gv") == -1)
				continue;
			
			neko.Lib.println("processing: " + fileName);
			
			// get dot
			var dot = File.getContent(graphsPath + fileName);
			dot = dot.split("\r").join("");
			
			// get xdot
			var proc = new neko.io.Process("dot", ["-Txdot", graphsPath + fileName]);
			var xdot = proc.stdout.readAll().toString();
			xdot = xdot.split("\r").join("");
			
			// get graph width and height
			var r = ~/\"0,0,([0-9.]+),([0-9.]+)\"/;
			var matches = r.match(xdot);
			
			var padding = 8.0;
			var scaleFactor = 96.0 / 72.0;
			var w = matches ? Math.ceil( Std.parseFloat(r.matched(1)) * scaleFactor + 2 * padding ) : 100;
			var h = matches ? Math.ceil( Std.parseFloat(r.matched(2)) * scaleFactor + 2 * padding ) : 100;
			
			// set swf max w and h at 1200
			if (w > 1200 || h > 1200) {
				w = 1200;
				h = 1200;
			}
			neko.Lib.println("  ..  w = " + Std.string(w) + " h = " + Std.string(h));
			
			// write png
			proc = new neko.io.Process("dot", ["-Tpng", "-o" + binPath + fileName + ".png", graphsPath + fileName]);
			neko.Lib.println("  ..  png done");
			
			// write xdot
			writeFile(binPath + fileName + ".xdot", xdot);
			neko.Lib.println("  ..  xdot done");
			
			// write swf
			proc = new neko.io.Process("haxe", ["-main", "graphx.Viz", "-cp", "../src", "-swf", binPath + fileName + ".swf", "-swf-version", "9", 
				"-swf-header", Std.string(w) + ":" + Std.string(h) + ":40:FFFFFF"]);
			neko.Lib.println("  ..  swf done");
			
			// write html
			writeHtml(binPath, fileName, dot, xdot, Std.string(w), Std.string(h));
			neko.Lib.println("  ..  html done");
		}
	}
	
	function writeHtml( outPath : String, fileName : String, dot : String, xdot : String, w : String, h : String ) {
		
		var str = haxe.Resource.getString("index_html");
		var t = new haxe.Template(str);
		var output = t.execute( { title : "Index", inhtml : fileName + ".in.html", outhtml : fileName + ".out.html"} );
		writeFile( outPath + fileName + ".index.html", output );
		
		str = haxe.Resource.getString("in_html");
		t = new haxe.Template(str);
		output = t.execute( {title : "In", data : dot, command : "dot " + fileName + " -Tpng -o" + fileName + ".png", graph : fileName + ".png"} );
		writeFile( outPath + fileName + ".in.html", output );
		
		str = haxe.Resource.getString("out_html");
		t = new haxe.Template(str);
		output = t.execute( {
			title : "Out", data : xdot, command : "dot " + fileName + " -Txdot -o" + fileName + ".xdot", 
			graph : fileName + ".swf", graph_width : w, graph_height : h, input : fileName + ".xdot"
		} );
		writeFile( outPath + fileName + ".out.html", output );
	}
	
	function writeFile( absolutFilePath : String, content : String ) {
		var out = neko.io.File.write(absolutFilePath, false);
		out.writeString(content);
		out.close();
	}
}