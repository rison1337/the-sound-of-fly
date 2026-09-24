vec3 design_paper(float p) {
	return p<.5?vec3(.935,.94,.918):(p<1.5?vec3(.945,.926,.865):(p<2.5?vec3(.89,.925,.885):vec3(.94,.92,.91)));
}
vec3 design_ink(float p) { return vec3(.023,.028,.036); }
vec3 design_accent(float p) {
	return p<.5?vec3(.39,.27,.96):(p<1.5?vec3(.08,.27,.97):(p<2.5?vec3(.70,.96,.14):vec3(.97,.18,.095)));
}
