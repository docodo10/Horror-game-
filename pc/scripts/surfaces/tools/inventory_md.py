"""Markdown inventory of level.glb materials (nodes, maps, factors) and of model GLB materials.
usage: inventory_md.py level.glb models_dir model1 model2 ..."""
import io, json, struct, sys, os
from PIL import Image


def load(path):
    f = open(path, 'rb').read()
    clen, _ = struct.unpack('<II', f[12:20])
    return f, json.loads(f[20:20 + clen]), 20 + clen + 8


level, models_dir = sys.argv[1], sys.argv[2]
f, j, _ = load(level)
imgs, texs = j.get('images', []), j.get('textures', [])


def tname(ti):
    if ti is None:
        return ''
    im = imgs[texs[ti['index']]['source']]
    return os.path.basename(im.get('uri') or im.get('name') or '?').replace('_basecolor', '').replace('.jpg', '').replace('.png', '')


users = {}
for n in j['nodes']:
    if 'mesh' in n:
        for p in j['meshes'][n['mesh']]['primitives']:
            if 'material' in p:
                users.setdefault(p['material'], []).append(n.get('name'))
print('| # | material | nodes | maps (exported 1K) | base colour / rough / metal | extras |')
print('|---|---|---|---|---|---|')
for i, m in enumerate(j['materials']):
    pbr = m.get('pbrMetallicRoughness', {})
    maps = [x for x in [tname(pbr.get('baseColorTexture')), tname(pbr.get('metallicRoughnessTexture')), tname(m.get('normalTexture')),
                        tname(m.get('occlusionTexture'))] if x]
    bc = pbr.get('baseColorFactor', [1, 1, 1, 1])
    ex = m.get('extras', {})
    flags = ', '.join(k for k in ('vertexColors', 'overbright', 'depthWrite', 'polygonOffset', 'blending') if k in ex)
    if 'envZone' in ex:
        flags += (', ' if flags else '') + 'envZone %s' % ex['envZone']
    nodes = ', '.join(users.get(i, []))
    if len(nodes) > 70:
        nodes = nodes[:67] + '...'
    print('| %d | `%s` | %s | %s | (%.2f %.2f %.2f) / %s / %s | %s |' % (
        i, m.get('name'), nodes, ' + '.join(maps), bc[0], bc[1], bc[2], pbr.get('roughnessFactor', 1), pbr.get('metallicFactor', 1), flags))

print()
print('| model | material | maps (embedded) |')
print('|---|---|---|')
for name in sys.argv[3:]:
    mf, mj, boff = load(os.path.join(models_dir, name + '.glb'))
    mimgs, mtexs, views = mj.get('images', []), mj.get('textures', []), mj.get('bufferViews', [])

    def info(ti):
        if ti is None:
            return None
        t = mtexs[ti['index']]
        src = t.get('source', t.get('extensions', {}).get('EXT_texture_webp', {}).get('source'))
        im = mimgs[src]
        bv = views[im['bufferView']]
        data = mf[boff + bv.get('byteOffset', 0): boff + bv.get('byteOffset', 0) + bv['byteLength']]
        try:
            w, h = Image.open(io.BytesIO(data)).size
        except Exception:
            w = h = 0
        return '%dx%d %s' % (w, h, im.get('mimeType', '').replace('image/', ''))
    for m in mj.get('materials', []):
        pbr = m.get('pbrMetallicRoughness', {})
        parts = []
        for lab, ti in (('albedo', pbr.get('baseColorTexture')), ('rough/metal', pbr.get('metallicRoughnessTexture')),
                        ('normal', m.get('normalTexture'))):
            s = info(ti)
            if s:
                parts.append('%s %s' % (lab, s))
        print('| `%s` | `%s` | %s |' % (name, m.get('name'), ', '.join(parts)))
