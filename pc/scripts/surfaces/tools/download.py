"""Download CC0 PBR sources into RAW_DIR/<src>_<id>/ (one new directory per asset; untrusted data stays there).
usage: python3 -I download.py RAW_DIR [--res 2k] ph:id acg:Id ...
  ph:  Poly Haven API (api.polyhaven.com/files/<id>) -> Diffuse / nor_gl / Rough / AO / Displacement jpg at the resolution
  acg: ambientCG <Id>_<RES>-JPG.zip (extracted with zipfile, member names sanitised)
"""
import io, json, os, sys, urllib.request, zipfile

UA = {'User-Agent': 'LaGardienne-surfaces/1.0 (indie horror game, CC0 texture download)'}
raw = sys.argv[1]
args = sys.argv[2:]
res = '2k'
if args and args[0] == '--res':
    res = args[1]
    args = args[2:]


def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=300).read()


for it in args:
    src, aid = it.split(':', 1)
    d = os.path.join(raw, '%s_%s_%s' % (src, aid, res))
    if os.path.isdir(d) and os.listdir(d):
        print('skip', d)
        continue
    os.makedirs(d, exist_ok=True)
    if src == 'ph':
        files = json.loads(get('https://api.polyhaven.com/files/%s' % aid))
        open(os.path.join(d, 'files.json'), 'w').write(json.dumps(files))
        for m in ('Diffuse', 'nor_gl', 'Rough', 'AO', 'Displacement'):
            if m in files and res in files[m] and 'jpg' in files[m][res]:
                url = files[m][res]['jpg']['url']
                name = os.path.basename(url)
                if '/' in name or '..' in name:
                    continue
                data = get(url)
                open(os.path.join(d, name), 'wb').write(data)
                print(' ', aid, m, len(data))
    else:
        zres = res.upper() + '-JPG'
        data = get('https://ambientcg.com/get?file=%s_%s.zip' % (aid, zres))
        z = zipfile.ZipFile(io.BytesIO(data))
        for zi in z.infolist():
            name = os.path.basename(zi.filename)
            if not name or name.startswith('.') or not name.lower().endswith(('.jpg', '.jpeg', '.png', '.mtlx', '.usda')):
                continue
            open(os.path.join(d, name), 'wb').write(z.read(zi))
        print(' ', aid, 'zip', len(data), sorted(os.listdir(d)))
print('done')
