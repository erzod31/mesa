"""Small public follow-up sample: DOM/schema differences and image HEAD only."""
from html import unescape
from html.parser import HTMLParser
import json
from pathlib import Path
import re
from urllib.request import Request, urlopen
from auditar_fuentes_recetas import fetch, ROOT
from server.importer import Scripts, clean

class Node:
    def __init__(self, tag='', attrs=None): self.tag=tag; self.attrs=attrs or {}; self.children=[]
    def nodes(self):
        yield self
        for child in self.children:
            if isinstance(child, Node): yield from child.nodes()
    def text(self): return ''.join(c.text() if isinstance(c,Node) else c for c in self.children)

class DOM(HTMLParser):
    def __init__(self): super().__init__(); self.root=Node(); self.stack=[self.root]
    def handle_starttag(self, tag, attrs):
        n=Node(tag,dict(attrs)); self.stack[-1].children.append(n)
        if tag not in {'area','base','br','col','embed','hr','img','input','link','meta','param','source','track','wbr'}: self.stack.append(n)
    def handle_data(self,data): self.stack[-1].children.append(data)
    def handle_endtag(self,tag):
        for i in range(len(self.stack)-1,0,-1):
            if self.stack[i].tag==tag: self.stack=self.stack[:i]; break

def recipes(value):
    if isinstance(value,dict):
        if value.get('@type') == 'Recipe' or (isinstance(value.get('@type'),list) and 'Recipe' in value['@type']): yield value
        for v in value.values(): yield from recipes(v)
    if isinstance(value,list):
        for v in value: yield from recipes(v)

def details(url):
    raw,final,status,mime,encoding=fetch(url); text=raw.decode(encoding,errors='replace')
    dom=DOM(); dom.feed(text); nodes=list(dom.root.nodes())
    blocks=Scripts(); blocks.feed(text); rs=[]
    for b in blocks.parts:
        try: rs.extend(recipes(json.loads(b)))
        except ValueError: pass
    ingredients=[]
    for n in nodes:
        if any(c in (n.attrs.get('class') or '').split() for c in ['field--name-field-ingredients','field-name-field-ingredients','field_ingredients']):
            ingredients=[clean(x.text()) for x in n.nodes() if x.tag=='li' or 'ingredient' in (x.attrs.get('class') or '').split()]
    return {'url':final,'schema_recipes':[{'ingredient_entries':len(r.get('recipeIngredient',[])), 'ingredient_entry_lengths':[len(x) for x in r.get('recipeIngredient',[])], 'instruction_entries':len(r.get('recipeInstructions',[]))} for r in rs], 'html_ingredient_items':len(ingredients), 'html_ingredients_with_numbers':sum(bool(re.search('[0-9¼½¾⅓⅔⅛⅜⅝⅞]',x)) for x in ingredients), 'field_classes':list(dict.fromkeys(n.attrs['class'] for n in nodes if re.search('ingredient|instruction',n.attrs.get('class') or '',re.I)))[:15]}

if __name__=='__main__':
    audit=json.loads((ROOT/'output/fuentes-recetas-auditoria-2026-10-11.json').read_text(encoding='utf-8'))
    ids={'foodhero-enchiladas','foodhero-granola','recetinas-tortilla'}
    result={'method':'Read-only public GET and photo HEAD. No image content downloaded. DOM counts are source-specific, not a general recipe validator.', 'dom':[details(p['requested_url']) for p in audit['pages'] if p['id'] in ids], 'wordpress':[], 'image_head':[]}
    raw,_,_,_,_=fetch('https://public-api.wordpress.com/rest/v1.1/sites/delokos.wordpress.com/posts/?number=3&page=1')
    data=json.loads(raw)
    for p in data['posts']:
        dom=DOM(); dom.feed(p['content']); nodes=list(dom.root.nodes())
        quantities=[n.text() for n in nodes if n.tag=='p' and '–' in n.text()]
        result['wordpress'].append({'id':p['ID'],'title':clean(p['title']), 'url':p['URL'], 'body_images':len([n for n in nodes if n.tag=='img']), 'attachments':len(p['attachments']), 'quantity_paragraphs':len(quantities), 'numeric_tokens_in_quantity_paragraphs':sum(len(re.findall('[0-9¼½¾⅓⅔⅛⅜⅝⅞]',x)) for x in quantities), 'licence_links':list(dict.fromkeys(n.attrs.get('href') for n in nodes if n.tag=='a' and 'creativecommons.org/licenses' in (n.attrs.get('href') or '')))})
    raw,_,_,_,_=fetch('https://public-api.wordpress.com/rest/v1.1/sites/delokos.wordpress.com/posts/?number=1&page=2&fields=ID,title,URL')
    second=json.loads(raw); result['pagination_second_page']={'found':second['found'], 'id':second['posts'][0]['ID'], 'url':second['posts'][0]['URL']}
    for key in ['bonviveur-tortilla','hogarmania-tortilla','foodhero-enchiladas','petitchef-editorial','delokos-arroz']:
        p=next(p for p in audit['pages'] if p['id']==key)
        photos=p.get('recipe',{}).get('photo_urls') or [p.get('open_graph_image')]
        url=photos[0]
        try:
            with urlopen(Request(url,method='HEAD',headers={'User-Agent':'Mesa-Source-Research/1.0'}),timeout=20) as r:
                result['image_head'].append({'id':key,'url':url,'status':r.status,'type':r.headers.get_content_type(),'bytes':r.headers.get('Content-Length')})
        except Exception as e: result['image_head'].append({'id':key,'url':url,'error':str(e)})
    out=ROOT/'output/fuentes-recetas-integridad-2026-10-11.json'; out.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False,indent=2))
