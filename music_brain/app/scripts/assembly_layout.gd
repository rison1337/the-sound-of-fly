extends RefCounted
## Spatial grammars with reserved cells and depth lanes. Screen overlap is
## intentional; independent solid surfaces do not share the same depth slab.
static func pose(d: Dictionary, kind: int, g: int, j: int, development: float, time: float) -> Transform3D:
	var family := int(d.topology)
	var groups := int(d.branches); var columns := int(d.columns)
	var profile := float(d.profile[(g*3+j)%16])
	var pos := Vector3.ZERO; var rot := Vector3.ZERO; var scale := Vector3.ONE
	var fold := development*float(d.fold)
	match family:
		0: # Full frame editorial panels unfolding from a common graphic plane.
			pos=Vector3((float(g%3)-1.)*4.6,(.5-float(g/3))*4.1,-float(g%2)*.7)
			rot=Vector3(0.,(float(g%2)*2.-1.)*fold*.18,0.)
			scale=Vector3(2.1,1.85,.35)
		1: # Folded relief: parallel sheets with physical clearance for the folds.
			pos=Vector3((float(g)-1.)*4.8,0.,-float(g)*.6)
			rot.y=(float(g)-1.)*fold*.28
			scale=Vector3(2.15,4.,.65)
		2: # Architecture. Segments are shorter than their reserved depth interval.
			if j<20:
				var theta := float(g)*TAU/float(groups+2)
				pos=Vector3(cos(theta)*5.8,sin(theta)*5.8,-float(j)*5.)
				rot.z=theta
				scale=Vector3(1.1+profile*.6,.7+profile*.4,3.3+profile*.7)
			else:
				pos.z=-float(g)*18.-5.
				scale=Vector3(4.8,4.8,.18)
		3: # A radial chamber surrounding the camera, not a thin central ladder.
			pos=Vector3(0,0,-float(g)*3.5)
			rot.z=float(g)*.4+float(d.twist)*development
			scale=Vector3(4.3+profile*.4,4.3+profile*.4,1.2)
		4: # Offset vertical partitions; no crossing sheets.
			pos=Vector3((float(g)-float(groups+1)*.5)*1.72,0.,-float(g%3)*1.6)
			scale=Vector3(.70,4.4,.28)
		5: # Aperture: independent concentric contours in separate depth lanes.
			if j==0:
				pos.z=-float(groups+4)*1.25; scale=Vector3(3.6,3.6,.1)
			else:
				pos.z=-float(g)*1.25
				rot.z=float(g)*.61+fold*.4
				scale=Vector3(4.8-float(g)*.15,4.8-float(g)*.15,1.0)
		6: # Macro ribbon banks. Separate sheets, with a near-surface camera.
			pos=Vector3((float(g)-float(groups-1)*.5)*5.4,0.,-float(j)*1.35)
			rot=Vector3(.08,0.,0.)
			scale=Vector3(2.05,3.1,.30)
			if j>=20: pos.z=-float(columns)*1.35-2.; scale=Vector3(2.05,3.6,.12)
		7: # Two by two framed editorial views.
			pos=Vector3((float(g%2)-.5)*6.9,(.5-float((g/2)%2))*4.6,-float(g%2)*.9)
			rot.y=(float(g%2)*2.-1.)*fold*.10
			scale=Vector3(3.2,2.05,.15)
		8: # Four walls made of panels, with a completely open camera corridor.
			var side := g%4; var row := g/4
			pos=Vector3(0,0,-float(row)*8.-4.)
			if side<2: pos.x=(-1. if side==0 else 1.)*5.7; rot.y=PI*.5
			else: pos.y=(-1. if side==2 else 1.)*5.7; rot.x=PI*.5
			scale=Vector3(3.55,5.4,.15) if side<2 else Vector3(5.4,3.55,.15)
		9: # Cutout sheet. Clear cells, each containing a related small assembly.
			pos=Vector3((float(g%3)-1.)*4.8,(.5-float(g/3))*4.2,-float(g%3)*.7)
			rot.z=(profile-.5)*.22
			scale=Vector3(1.7+profile*.3,1.65,.18)
		10: # A succession of large cropped sculptures and small distant inserts.
			# Separate depth reservations, deliberately unequal scales; no icon grid.
			var xs := [-3.8,3.4,-.8,5.2,-5.6,2.4,-2.6,4.6,-4.4,.6]
			var ys := [.9,-1.3,2.6,1.8,-2.0,3.,-3.1,.5,2.1,-.8]
			pos=Vector3(float(xs[g%10]),float(ys[g%10]),-float(g)*8.-1.)
			rot=Vector3(.25+profile*.6,float(d.twist)*.4,float(g)*.7)
			var mass := 2.8 if g==0 else (2.1 if g==1 else 1.1+profile*.6)
			if kind==0: mass*=1.25
			scale=Vector3(mass,mass*(.8+profile*.35),mass*.65)
		11: # Nested frames. Their centres are holes, allowing a true plunge.
			pos=Vector3(0,0,-float(g)*3.5)
			rot.z=sin(float(g)*.4)*float(d.twist)*.09
			scale=Vector3(6.,4.,.12)
	# The musical phrase determines panel proportions as well as motion. A
	# lead-led phrase forms two broad columns; a percussive phrase forms three
	# narrower columns. All contents retain the same parent cell and clearance.
	if family in [0,9] and d.has("choreography"):
		var plan: Dictionary=d.choreography
		var cols := int(plan.get("panel_columns",3))
		var rows := int(ceil(float(6 if family==9 else groups)/cols))
		var cell := Vector2(13.8/cols,8.2/maxi(1,rows))
		pos.x=(float(g%cols)-float(cols-1)*.5)*cell.x
		pos.y=(float(rows-1)*.5-float(g/cols))*cell.y
		var width := float(plan.get("panel_width",.84))
		scale.x=cell.x*.5*width
		scale.y=cell.y*.5*(.80+profile*.08)
	# Children use the parent's frame, with separate local depth for solids.
	# Contours are overridden by the resolver to use the exact filled surface.
	if family in [0,1,4,7,9,11]:
		if kind==4:
			pos+=Vector3(.35,-.1,1.6); scale=Vector3.ONE*(.45+profile*.15); rot=Vector3.ZERO
		elif kind==1:
			pos+=Vector3(.0,.15,1.6); scale=Vector3(1.05,1.05,.8)
		elif kind==2:
			var n := maxi(0,j-2)
			pos+=Vector3(0.,-.9+float(n%4)*.60,.9)
			scale=Vector3(.9+profile,.025,.05)
		elif kind==0 and family==1 and j>=2:
			pos+=Vector3(0.,(float(j-2)/maxi(1,columns*2-1)-.5)*6.8,1.0)
			scale=Vector3(1.9,.025,.025)
	elif family in [3,5]:
		if kind==4:
			pos+=Vector3(3.5,0.,.7); scale=Vector3.ONE*.25
		elif kind==2:
			var theta := float(j)*TAU/5.
			pos+=Vector3(cos(theta)*3.6,sin(theta)*3.6,.6)
			scale=Vector3(.10,.30+profile*.45,.1); rot.z=theta
	elif family==10:
		if kind==0 and j>=20:
			pos+=Vector3(2.,-.6,-2.6); scale=Vector3(2.2,2.5,.12)
		elif kind==0: scale.z=.15
		elif kind==1:
			pos+=Vector3(-.8,2.5,1.8); scale=Vector3(1.2,1.2,.8); rot.z+=.7
		elif kind==2:
			pos+=Vector3((float(j)-4.)*.85,-2.5,1.5)
			scale=Vector3(.27,.4+profile*.35,.20)
	# Motion is a bounded part of each grammar; external camera travel creates
	# the large change in scale and parallax instead of enlarging all geometry.
	if family in [0,7,9]: pos.y+=(profile-.5)*.3*development
	# Scale domain axes before rotating them into the world. Basis.scaled()
	# scales world axes, which collapsed tunnel walls and caused crossings.
	return Transform3D(Basis.from_euler(rot)*Basis.from_scale(scale),pos)
