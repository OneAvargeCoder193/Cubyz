#version 460

layout(location = 0) out vec3 startPosition;
layout(location = 1) out vec3 direction;
layout(location = 2) out vec3 cameraSpacePos;
layout(location = 3) out vec2 uv;
layout(location = 4) flat out int faceNormalIndex;
layout(location = 5) flat out vec3 faceNormal;
layout(location = 6) flat out int voxelModel;
layout(location = 7) flat out int textureIndex;
layout(location = 8) flat out uvec3 lower;
layout(location = 9) flat out uvec3 upper;

layout(location = 0) uniform mat4 projectionMatrix;
layout(location = 1) uniform mat4 viewMatrix;
layout(location = 2) uniform mat4 modelMatrix;
layout(location = 3) uniform int modelIndex;
layout(location = 4) uniform int block;

layout(std430, binding = 2) buffer _modelInfo
{
	uint modelInfo[];
};

struct QuadInfo {
	vec3 normal;
	float corners[4][3];
	vec2 cornerUV[4];
	uint textureSlot;
	int opaqueInLod;
};

layout(std430, binding = 4) buffer _quads
{
	QuadInfo quads[];
};


const int[24] positions = int[24](
	0x010,
	0x110,
	0x011,
	0x111,

	0x000,
	0x001,
	0x100,
	0x101,

	0x100,
	0x101,
	0x110,
	0x111,

	0x000,
	0x010,
	0x001,
	0x011,

	0x001,
	0x011,
	0x101,
	0x111,

	0x000,
	0x100,
	0x010,
	0x110
);

void main() {
	int faceID = gl_VertexID >> 2;
	int vertexID = gl_VertexID & 3;
	int voxelModelIndex = modelIndex;
	bool isBlock = block != 0;
	vec3 pos;
	if(isBlock) {
		uint modelAndTexture = modelInfo[voxelModelIndex + faceID*2];
		uint offsetByNormal = modelInfo[voxelModelIndex + faceID*2 + 1];
		uint quadIndex = modelAndTexture >> 16u;
		textureIndex = int(modelAndTexture & 65535u);

		pos = vec3(quads[quadIndex].corners[vertexID][0], quads[quadIndex].corners[vertexID][1], quads[quadIndex].corners[vertexID][2]);
		uv = quads[quadIndex].cornerUV[vertexID];
		if(offsetByNormal != 0) {
			pos += quads[quadIndex].normal;
		}
		faceNormal = quads[quadIndex].normal;
	} else {
		int position = positions[gl_VertexID];
		pos = vec3 (
			position >> 8 & 1,
			position >> 4 & 1,
			position >> 0 & 1
		);
		faceNormalIndex = faceID;
		upper.x = modelInfo[voxelModelIndex++];
		upper.y = modelInfo[voxelModelIndex++];
		upper.z = modelInfo[voxelModelIndex++];
		lower = uvec3(0);

		startPosition = lower + vec3(upper - lower)*0.999*pos;
		float scale = max(upper.x - lower.x, max(upper.y - lower.y, upper.z - lower.z));
		pos = pos*(upper - lower)/scale + (0.5 - (lower + upper)/scale/2);
		textureIndex = -1;
	}
	voxelModel = voxelModelIndex;


	vec4 worldSpace = modelMatrix*vec4(pos, 1);
	direction = (transpose(mat3(modelMatrix))*worldSpace.xyz).xyz;

	vec4 cameraSpace = viewMatrix*worldSpace;
	gl_Position = projectionMatrix*cameraSpace;
	cameraSpacePos = cameraSpace.xyz;
}
