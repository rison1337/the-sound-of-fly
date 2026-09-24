extends RefCounted
## JSON header then exactly frame_bytes bytes; never scan binary for newlines.
var buffer := PackedByteArray()
var header := {}
var failed := false

func feed(bytes: PackedByteArray) -> Array:
	buffer.append_array(bytes)
	var packets := []
	while not failed:
		if header.is_empty():
			var end := buffer.find(10)
			if end<0:
				if buffer.size()>65536: failed=true
				break
			if end>65536:
				failed=true
				break
			var parsed: Variant=JSON.parse_string(buffer.slice(0,end).get_string_from_utf8())
			buffer=buffer.slice(end+1)
			if not parsed is Dictionary:
				failed=true
				break
			header=parsed
			if header.is_empty(): continue
		var count := int(header.get("frame_bytes",0))
		if count<0 or count>4194304:
			failed=true
			break
		if buffer.size()<count: break
		packets.append([header,buffer.slice(0,count)])
		buffer=buffer.slice(count)
		header={}
	return packets
