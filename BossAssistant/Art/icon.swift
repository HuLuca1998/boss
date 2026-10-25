import AppKit
let folder=CommandLine.arguments[1]
for size in [16,32,64,128,256,512,1024] {
 let image=NSImage(size:NSSize(width:size,height:size));image.lockFocus()
 let s=CGFloat(size)
 let bg=NSBezierPath(roundedRect:NSRect(x:0,y:0,width:s,height:s),xRadius:s*0.22,yRadius:s*0.22)
 NSGradient(starting:NSColor(red:0.06,green:0.13,blue:0.18,alpha:1),ending:NSColor(red:0.025,green:0.04,blue:0.075,alpha:1))!.draw(in:bg,angle:-45)
 let ring=NSBezierPath(ovalIn:NSRect(x:s*0.21,y:s*0.21,width:s*0.58,height:s*0.58));ring.lineWidth=s*0.045;NSColor(red:0.2,green:0.88,blue:0.76,alpha:1).setStroke();ring.stroke()
 let cross=NSBezierPath();cross.lineWidth=s*0.04;cross.lineCapStyle = .round
 for (a,b) in [(NSPoint(x:s*0.5,y:s*0.13),NSPoint(x:s*0.5,y:s*0.29)),(NSPoint(x:s*0.5,y:s*0.71),NSPoint(x:s*0.5,y:s*0.87)),(NSPoint(x:s*0.13,y:s*0.5),NSPoint(x:s*0.29,y:s*0.5)),(NSPoint(x:s*0.71,y:s*0.5),NSPoint(x:s*0.87,y:s*0.5))]{cross.move(to:a);cross.line(to:b)}
 cross.stroke()
 let bolt=NSBezierPath();bolt.move(to:NSPoint(x:s*0.55,y:s*0.68));bolt.line(to:NSPoint(x:s*0.37,y:s*0.46));bolt.line(to:NSPoint(x:s*0.49,y:s*0.46));bolt.line(to:NSPoint(x:s*0.45,y:s*0.32));bolt.line(to:NSPoint(x:s*0.64,y:s*0.55));bolt.line(to:NSPoint(x:s*0.52,y:s*0.55));bolt.close();NSColor.white.setFill();bolt.fill()
 image.unlockFocus();let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!;let data=rep.representation(using:.png,properties:[:])!
 let names:[Int:[String]]=[16:["icon_16x16.png"],32:["icon_16x16@2x.png","icon_32x32.png"],64:["icon_32x32@2x.png"],128:["icon_128x128.png"],256:["icon_128x128@2x.png","icon_256x256.png"],512:["icon_256x256@2x.png","icon_512x512.png"],1024:["icon_512x512@2x.png"]]
 for name in names[size]! {try data.write(to:URL(fileURLWithPath:folder).appendingPathComponent(name))}
}
