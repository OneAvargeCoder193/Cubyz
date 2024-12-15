verts = [
    [0.0, 0.0, 0.0],
    [1.0, 0.0, 0.0],
    [1.0, 0.0, 1.0],
    [0.0, 0.0, 1.0],
    [0.0, 1.0, 0.0],
    [1.0, 1.0, 0.0],
    [1.0, 1.0, 1.0],
    [0.0, 1.0, 1.0],
]

normals = [
    [0.0, -1.0, 0.0],
    [0.0, 1.0, 0.0],
    [0.0, 0.0, 1.0],
    [0.0, 0.0, -1.0],
    [-1.0, 0.0, 0.0],
    [1.0, 0.0, 0.0]
]

tris = [
    [0, 3, 1, 2],
    [5, 6, 4, 7],
    [3, 7, 2, 6],
    [1, 5, 0, 4],
    [4, 7, 0, 3],
    [1, 2, 5, 6]
]

uvs = [
    [0.0, 0.0],
    [0.0, 1.0],
    [1.0, 0.0],
    [1.0, 1.0]
]

data = []

inds = []


ind = 0
for p in range(6):
    data.extend(verts[tris[p][0]])
    data.extend(uvs[0])
    data.extend(normals[p])

    data.extend(verts[tris[p][1]])
    data.extend(uvs[1])
    data.extend(normals[p])

    data.extend(verts[tris[p][2]])
    data.extend(uvs[2])
    data.extend(normals[p])

    data.extend(verts[tris[p][3]])
    data.extend(uvs[3])
    data.extend(normals[p])

    inds.append(ind)
    inds.append(ind + 1)
    inds.append(ind + 2)
    inds.append(ind + 2)
    inds.append(ind + 1)
    inds.append(ind + 3)

    ind += 4

for i in range(0, len(data), 8):
    for j in data[i:i+8]:
        print(str(j).rjust(4, " ") + "f", end=", ")
    print("")