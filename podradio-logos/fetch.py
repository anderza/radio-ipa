# Скачивает логотипы станций из stations.txt (Название | URL | Жанр | Логотип), уменьшает до 256px и кладёт в out/
import io, json, os, sys, urllib.parse, urllib.request
from PIL import Image
os.makedirs('out', exist_ok=True)
res = {}
for i, ln in enumerate(open(sys.argv[1], encoding='utf-8')):
    p = [x.strip() for x in ln.rstrip('\n').split('|')] + ['', '', '']
    n, l = p[0], p[3]
    if not l.startswith('http'):
        continue
    img = None
    for url in [l, 'https://wsrv.nl/?url=' + urllib.parse.quote(l, safe='') + '&w=256&output=png']:
        try:
            r = urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/130 Safari/537.36', 'Accept': 'image/*,*/*'}), timeout=25)
            img = Image.open(io.BytesIO(r.read())); img.load(); break
        except Exception as e:
            print('::warning::', n, url[:80], e)
    if img is None:
        continue
    img = img.convert('RGBA'); img.thumbnail((256, 256))
    fn = 'st%03d.png' % i
    img.save('out/' + fn, optimize=True); res[n + '\t' + p[1]] = fn
json.dump(res, open('out/map.json', 'w'), ensure_ascii=False, indent=0)
print('скачано', len(res))
