# Ищет логотипы через каталог Radio Browser (по адресу потока и по названию) и скачивает их в out/
import io, json, os, sys, urllib.parse, urllib.request
from PIL import Image
os.makedirs('out', exist_ok=True)
H = {'User-Agent': 'PodRadio/1.0'}
def get(u, t=25):
    return urllib.request.urlopen(urllib.request.Request(u, headers=H), timeout=t).read()
res = {}
for ln in open(sys.argv[1], encoding='utf-8'):
    p = [x.strip() for x in ln.rstrip('\n').split('|')] + ['', '', '']
    name, url, extra = p[0], p[1], [x for x in p[2:] if x.startswith('http')]
    if not name: continue
    cands = list(extra)
    for q in ['byurl?url=' + urllib.parse.quote(url, safe=''), 'search?name=' + urllib.parse.quote(p[3] or name) + '&limit=10&order=votes&reverse=true']:
        try:
            for st in json.loads(get('https://de1.api.radio-browser.info/json/stations/' + q)):
                if st.get('favicon'): cands.append(st['favicon']); print(name, '→', st['name'], st['favicon'])
        except Exception as e: print('::warning::', name, q[:40], e)
    for c in cands:
        for u in [c, 'https://wsrv.nl/?url=' + urllib.parse.quote(c, safe='') + '&w=256&output=png']:
            try:
                im = Image.open(io.BytesIO(get(u))); im.load()
                if min(im.size) < 48: raise Exception('мелкая %s' % (im.size,))
                im = im.convert('RGBA'); im.thumbnail((256, 256)); fn = 'f_%d.png' % len(res)
                im.save('out/' + fn); res[name] = {'file': fn, 'src': c}; break
            except Exception as e: print('::warning::', name, u[:80], e)
        if name in res: break
json.dump(res, open('out/map.json', 'w'), ensure_ascii=False, indent=1)
print('найдено', len(res))
