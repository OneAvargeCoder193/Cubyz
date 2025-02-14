#version 430

in vec3 mvVertexPos;
in float temperature;
in float magnitude;
in vec3 direction;

layout (location = 0, index = 0) out vec4 fragColor;
// layout (location = 0, index = 1) out vec4 blendColor;

struct Fog {
	vec3 color;
	float density;
	float fogLower;
	float fogHigher;
};

uniform Fog fog;

uniform ivec3 playerPositionInteger;
uniform vec3 playerPositionFraction;

const float h = 6.62607015e-34;
const float c = 2.99792458e8;
const float k_B = 1.380649e-23;

float plankRadiance(float wavelength) {
	float meters = wavelength * 1e-9;
	return (2 * h * pow(c, 2)) / (pow(meters, 5) * (exp(h * c / (meters * k_B * temperature)) - 1));
}

const vec3 wavelengths[95] = vec3[95](
	vec3(0.000129900000, 0.000003917000, 0.000606100000),
	vec3(0.000232100000, 0.000006965000, 0.001086000000),
	vec3(0.000414900000, 0.000012390000, 0.001946000000),
	vec3(0.000741600000, 0.000022020000, 0.003486000000),
	vec3(0.001368000000, 0.000039000000, 0.006450001000),
	vec3(0.002236000000, 0.000064000000, 0.010549990000),
	vec3(0.004243000000, 0.000120000000, 0.020050010000),
	vec3(0.007650000000, 0.000217000000, 0.036210000000),
	vec3(0.014310000000, 0.000396000000, 0.067850010000),
	vec3(0.023190000000, 0.000640000000, 0.110200000000),
	vec3(0.043510000000, 0.001210000000, 0.207400000000),
	vec3(0.077630000000, 0.002180000000, 0.371300000000),
	vec3(0.134380000000, 0.004000000000, 0.645600000000),
	vec3(0.214770000000, 0.007300000000, 1.039050100000),
	vec3(0.283900000000, 0.011600000000, 1.385600000000),
	vec3(0.328500000000, 0.016840000000, 1.622960000000),
	vec3(0.348280000000, 0.023000000000, 1.747060000000),
	vec3(0.348060000000, 0.029800000000, 1.782600000000),
	vec3(0.336200000000, 0.038000000000, 1.772110000000),
	vec3(0.318700000000, 0.048000000000, 1.744100000000),
	vec3(0.290800000000, 0.060000000000, 1.669200000000),
	vec3(0.251100000000, 0.073900000000, 1.528100000000),
	vec3(0.195360000000, 0.090980000000, 1.287640000000),
	vec3(0.142100000000, 0.112600000000, 1.041900000000),
	vec3(0.095640000000, 0.139020000000, 0.812950100000),
	vec3(0.057950010000, 0.169300000000, 0.616200000000),
	vec3(0.032010000000, 0.208020000000, 0.465180000000),
	vec3(0.014700000000, 0.258600000000, 0.353300000000),
	vec3(0.004900000000, 0.323000000000, 0.272000000000),
	vec3(0.002400000000, 0.407300000000, 0.212300000000),
	vec3(0.009300000000, 0.503000000000, 0.158200000000),
	vec3(0.029100000000, 0.608200000000, 0.111700000000),
	vec3(0.063270000000, 0.710000000000, 0.078249990000),
	vec3(0.109600000000, 0.793200000000, 0.057250010000),
	vec3(0.165500000000, 0.862000000000, 0.042160000000),
	vec3(0.225749900000, 0.914850100000, 0.029840000000),
	vec3(0.290400000000, 0.954000000000, 0.020300000000),
	vec3(0.359700000000, 0.980300000000, 0.013400000000),
	vec3(0.433449900000, 0.994950100000, 0.008749999000),
	vec3(0.512050100000, 1.000000000000, 0.005749999000),
	vec3(0.594500000000, 0.995000000000, 0.003900000000),
	vec3(0.678400000000, 0.978600000000, 0.002749999000),
	vec3(0.762100000000, 0.952000000000, 0.002100000000),
	vec3(0.842500000000, 0.915400000000, 0.001800000000),
	vec3(0.916300000000, 0.870000000000, 0.001650001000),
	vec3(0.978600000000, 0.816300000000, 0.001400000000),
	vec3(1.026300000000, 0.757000000000, 0.001100000000),
	vec3(1.056700000000, 0.694900000000, 0.001000000000),
	vec3(1.062200000000, 0.631000000000, 0.000800000000),
	vec3(1.045600000000, 0.566800000000, 0.000600000000),
	vec3(1.002600000000, 0.503000000000, 0.000340000000),
	vec3(0.938400000000, 0.441200000000, 0.000240000000),
	vec3(0.854449900000, 0.381000000000, 0.000190000000),
	vec3(0.751400000000, 0.321000000000, 0.000100000000),
	vec3(0.642400000000, 0.265000000000, 0.000049999990),
	vec3(0.541900000000, 0.217000000000, 0.000030000000),
	vec3(0.447900000000, 0.175000000000, 0.000020000000),
	vec3(0.360800000000, 0.138200000000, 0.000010000000),
	vec3(0.283500000000, 0.107000000000, 0.000000000000),
	vec3(0.218700000000, 0.081600000000, 0.000000000000),
	vec3(0.164900000000, 0.061000000000, 0.000000000000),
	vec3(0.121200000000, 0.044580000000, 0.000000000000),
	vec3(0.087400000000, 0.032000000000, 0.000000000000),
	vec3(0.063600000000, 0.023200000000, 0.000000000000),
	vec3(0.046770000000, 0.017000000000, 0.000000000000),
	vec3(0.032900000000, 0.011920000000, 0.000000000000),
	vec3(0.022700000000, 0.008210000000, 0.000000000000),
	vec3(0.015840000000, 0.005723000000, 0.000000000000),
	vec3(0.011359160000, 0.004102000000, 0.000000000000),
	vec3(0.008110916000, 0.002929000000, 0.000000000000),
	vec3(0.005790346000, 0.002091000000, 0.000000000000),
	vec3(0.004109457000, 0.001484000000, 0.000000000000),
	vec3(0.002899327000, 0.001047000000, 0.000000000000),
	vec3(0.002049190000, 0.000740000000, 0.000000000000),
	vec3(0.001439971000, 0.000520000000, 0.000000000000),
	vec3(0.000999949300, 0.000361100000, 0.000000000000),
	vec3(0.000690078600, 0.000249200000, 0.000000000000),
	vec3(0.000476021300, 0.000171900000, 0.000000000000),
	vec3(0.000332301100, 0.000120000000, 0.000000000000),
	vec3(0.000234826100, 0.000084800000, 0.000000000000),
	vec3(0.000166150500, 0.000060000000, 0.000000000000),
	vec3(0.000117413000, 0.000042400000, 0.000000000000),
	vec3(0.000083075270, 0.000030000000, 0.000000000000),
	vec3(0.000058706520, 0.000021200000, 0.000000000000),
	vec3(0.000041509940, 0.000014990000, 0.000000000000),
	vec3(0.000029353260, 0.000010600000, 0.000000000000),
	vec3(0.000020673830, 0.000007465700, 0.000000000000),
	vec3(0.000014559770, 0.000005257800, 0.000000000000),
	vec3(0.000010253980, 0.000003702900, 0.000000000000),
	vec3(0.000007221456, 0.000002607800, 0.000000000000),
	vec3(0.000005085868, 0.000001836600, 0.000000000000),
	vec3(0.000003581652, 0.000001293400, 0.000000000000),
	vec3(0.000002522525, 0.000000910930, 0.000000000000),
	vec3(0.000001776509, 0.000000641530, 0.000000000000),
	vec3(0.000001251141, 0.000000451810, 0.000000000000)
);

vec3 calculateColor() {
	vec3 total = vec3(0);
	for (int wavelength = 360; wavelength < 831; wavelength += 5) {
		float spectrum = plankRadiance(wavelength);
		total += spectrum * wavelengths[(wavelength - 360) / 5] * 5;
	}

	total /= max(max(total.x, total.y), total.z);
	
	mat3 conv = mat3(3.2406, -0.9689, 0.0557,
					 -1.5372, 1.8758, -0.2040,
					 -0.4986, 0.0415, 1.0570);
	
	vec3 rgb = conv * total;

	return mix(1.055 * pow(rgb, vec3(1 / 2.4)) - 0.055, 12.92 * rgb, vec3(lessThanEqual(rgb, vec3(0.0031308))));
}

float densityIntegral(float dist, float zStart, float zDist, float fogLower, float fogHigher) {
	// The density is constant until fogLower, then gets smaller linearly until reaching fogHigher, past which there is no fog.
	if(zDist < 0) {
		zStart += zDist;
		zDist = -zDist;
	}
	if(zDist == 0) {
		zDist = 0.1;
	}
	zStart /= zDist;
	fogLower /= zDist;
	fogHigher /= zDist;
	zDist = 1;
	float beginLower = min(fogLower, zStart);
	float endLower = min(fogLower, zStart + zDist);
	float beginMid = max(fogLower, min(fogHigher, zStart));
	float endMid = max(fogLower, min(fogHigher, zStart + zDist));
	float midIntegral = -0.5*(endMid - fogHigher)*(endMid - fogHigher)/(fogHigher - fogLower) - -0.5*(beginMid - fogHigher)*(beginMid - fogHigher)/(fogHigher - fogLower);
	if(fogHigher == fogLower) midIntegral = 0;

	return (endLower - beginLower + midIntegral)/zDist*dist;
}

float calculateFogDistance(float dist, float densityAdjustment, float zStart, float zScale, float fogDensity, float fogLower, float fogHigher) {
	float distCameraTerrain = densityIntegral(dist*densityAdjustment, zStart, zScale*dist*densityAdjustment, fogLower, fogHigher)*fogDensity;
	float distFromCamera = abs(densityIntegral(mvVertexPos.y*densityAdjustment, zStart, zScale*mvVertexPos.y*densityAdjustment, fogLower, fogHigher))*fogDensity;
	float distFromTerrain = distFromCamera - distCameraTerrain;
	if(distCameraTerrain < 10) { // Resolution range is sufficient.
		return distFromTerrain;
	} else {
		// Here we have a few options to deal with this. We could for example weaken the fog effect to fit the entire range.
		// I decided to keep the fog strength close to the camera and far away, with a fog-free region in between.
		// I decided to this because I want far away fog to work (e.g. a distant ocean) as well as close fog(e.g. the top surface of the water when the player is under it)
		if(distFromTerrain > -5) {
			return distFromTerrain;
		} else if(distFromCamera < 5) {
			return distFromCamera - 10;
		} else {
			return -5;
		}
	}
}

void applyFrontfaceFog(float fogDistance, vec3 fogColor) {
	float fogFactor = exp(fogDistance);
	fragColor.rgb = fogColor*(1 - fogFactor);
	fragColor.a = fogFactor;
}

void main() {
	float light = pow(10.0, -0.4 * magnitude);
	float brightness = max(light, 1);
	float opacity = min(light, 1);

	fragColor = vec4(calculateColor() * light, 1);
	
	// float densityAdjustment = sqrt(dot(mvVertexPos, mvVertexPos))/abs(mvVertexPos.y);
	// float dist = mvVertexPos.z;
	// float playerZ = playerPositionFraction.z + playerPositionInteger.z;

	// float airFogDistance = calculateFogDistance(dist, densityAdjustment, playerZ, normalize(direction).z, fog.density, fog.fogLower, fog.fogHigher);
	
	// blendColor.rgb = vec3(1 - opacity);

	// applyFrontfaceFog(airFogDistance, fog.color);

	// fragColor.rgb *= blendColor.rgb;
	// fragColor.rgb += calculateColor() * brightness;

	// blendColor.rgb *= fragColor.a;
	// fragColor.a = 1;
}