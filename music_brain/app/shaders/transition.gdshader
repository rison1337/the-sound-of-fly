shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/editorial_mask.gdshaderinc"
void fragment() {
    // Camera and objects already carry the musical motion. A second UV warp
    // here detached the image from its marks and introduced overlapping slices.
    vec4 current=texture(TEXTURE,UV);
    current.a*=1.-editorial_paper(UV);
    COLOR=current;
}
