uniform float presentation=0.;
uniform float framing_shape=.5;
uniform float previous_presentation=0.;
uniform float previous_framing=.5;
uniform float mask_progress=1.;
uniform float editorial_aspect=1.6;

// Views own the whole frame. Screen-space cards amputated foreground objects.
// Cut on the scored onset; camera and object motion supply continuity.
// No delayed wipe or blend of differently projected constructions.
float editorial_paper(vec2 uv) {
    return (presentation==1. || presentation==3.)?1.:0.;
}
