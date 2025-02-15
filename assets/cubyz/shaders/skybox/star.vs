#version 430

in vec3 vPos;
in vec3 vColor;

uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;

out vec3 color;

void main() {
	gl_Position = projectionMatrix*viewMatrix*vec4(vPos, 1);

	color = vColor;
}
