"""Download Poly Haven 2K texture maps (diff, nor_gl, arm) of model assets into RAW/models_2k/<id>/.
usage: python3 -I download_models.py RAW_DIR id1 id2 ..."""
import json, os, sys, urllib.request

UA = {'User-Agent': 'LaGardienne-surfaces/1.0 (indie horror game, CC0 texture download)'}
raw = sys.argv[1]


def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=300).read()


for aid in sys.argv[2:]:
    d = os.path.join(raw, 'models_2k', aid)
    os.makedirs(d, exist_ok=True)
    try:
        files = json.loads(get('https://api.polyhaven.com/files/%s' % aid))
    except Exception as e:  # noqa
        print('FAIL', aid, e)
        continue
    # the gltf entry lists every texture of every material (some models have several sets)
    inc = files.get('gltf', {}).get('2k', {}).get('gltf', {}).get('include', {})
    got = []
    for rel, info in inc.items():
        name = os.path.basename(rel)
        if '..' in name or '/' in name or not name.lower().endswith('.jpg'):
            continue
        has_arm = any('_arm_' in os.path.basename(r) for r in inc)
        if not any(k in name for k in ('_diff_', '_nor_gl_', '_arm_')) and not (not has_arm and '_rough_' in name):
            continue
        p = os.path.join(d, name)
        if not os.path.exists(p):
            open(p, 'wb').write(get(info['url']))
        got.append((name, os.path.getsize(p) // 1024))
    print(aid, got)
