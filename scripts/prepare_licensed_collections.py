"""Curate licensed PDF recipe text. Images remain remote references, never assets.

Run with the bundled Python (pdfplumber/pypdf). Inputs are the public research
documents reviewed on 2026-10-16. The frozen text is checked into both clients.
"""
from hashlib import sha256
import json
from pathlib import Path
import re
import pdfplumber

ROOT=Path(__file__).resolve().parents[1]
POLISH_TITLES=['Tortitas proziaki','Ñoquis perezosos de queso','Arenques al estilo de Casubia','Pastel de patatas',
 'Sopa de rábano con huevo y salchicha blanca','Empanadillas rusas y de ciruela','Rollo de carne silesiano',
 'Aguja de cerdo asado con comino','Tarta de manzana','Pastel de miel con confitura',
 'Galletas de jengibre katarzynki','Cócteles Levístico y En el matorral de frambuesas']



def clean(text):
    return re.sub(r'\s+',' ',re.sub(r'(?<=\w)-\s*\n(?=\w)','',text)).strip()


def recipe(provider,title,page,ingredients,steps,servings=None):
    config=CONFIG[provider]
    photo_url=config['url']+'?mesa_recipe_image='+str(page+1)
    source=config['url']+'#page='+str(page)
    return {'title':title,'ingredients':ingredients,'steps':steps,'servings':servings or 1,
      'servings_declared':servings is not None,'yield_original':str(servings) if servings else '',
      'yield_unit':'porciones','minutes':0,'language':'es','source':source,
      'tags':[config['country']],'notes':config['attribution']+'. '+config['license']+
      '. Formato y títulos adaptados a Mesa; cantidades y preparación conservadas. Ver páginas originales para el contexto y notas editoriales.',
      'photos':[{'url':photo_url,'source':source,'caption':title,'artist':config['attribution'],
      'license':config['license'],'license_url':config['license_url']}],
      'origin':{'provider':provider,'id':str(page),'url':source,'attribution':config['attribution'],
      'license':config['license'],'license_url':config['license_url'],'language':'es','reuse_status':'published_license'}}


CONFIG={
 'book-polaca':{'url':'https://bunkatura.pl/pdf/mesa_polaca.pdf','country':'Polonia',
 'attribution':'Magdalena Tomaszewska-Bolałek · Fundación Bunkatura; traducción Maria Schneider',
 'license':'CC BY 4.0','license_url':'https://creativecommons.org/licenses/by/4.0/'},

}


def polish(pdf):
    results=[]
    for pn,title in zip(range(90,114,2),POLISH_TITLES):
        p=pdf.pages[pn-1]
        # The quantity block is visually separated from the historical preface
        # and the preparation by larger vertical gaps; preserve original words.
        ls=p.extract_text_lines()
        start=next(i for i,l in enumerate(ls) if re.match(r'^\d+[–\d.,/]*\s+\S',l['text']) and l['top']>150)
        end=start+1
        while end<len(ls) and ls[end]['top']-ls[end-1]['top']<19: end+=1
        y0,y1=ls[start]['top']-13,ls[end-1]['bottom']+2
        columns=([(0,160,'Masa:'),(160,318,'Relleno ruso:'),(318,p.width,'Relleno de ciruelas:')]
          if pn==100 else [(0,235,'Levístico:'),(235,p.width,'En el matorral de frambuesas:')]
          if pn==112 else [(0,235,'Arenques:'),(235,p.width,'Adobo de vinagre:')]
          if pn==94 else [(0,235,'Masa:'),(235,p.width,'Relleno:')]
          if pn==108 else [(0,235,''),(235,p.width,'')]
          if pn in {96,98,102} else [(0,p.width,'')])
        ingredients=[]
        for x0,x1,heading in columns:
            block=p.within_bbox((x0,y0,x1,y1)).extract_text(x_tolerance=1) or ''
            vals=[clean(s) for s in block.splitlines() if clean(s)]
            if heading:
                ingredients.append(heading)
                vals=[s for s in vals if s.rstrip(':').casefold()!=heading.rstrip(':').casefold()]
            ingredients.extend(vals)
        # Rejoin source line wraps only where the original columns wrap a single ingredient.
        joins={94:[('500 g de arenques frescos','o salados (filetes)')],
          98:[('rábano fresco (según el gusto), puede ser','sustituido por el rábano seco'),('sal, pimienta, mejorana, pimienta de','Jamaica, ajo seco, laurel')],
          102:[('200 g de pepinillos encurtidos','(fermentados)')]}
        for first,second in joins.get(pn,[]):
            index=ingredients.index(first)
            assert ingredients[index+1]==second
            ingredients[index:index+2]=[first+' '+second]
        # Start at the first procedure line after the quantity block. Avoid
        # marginal pottery credits and page numbers, retain italic food names.
        bottom=p.crop((30,ls[end]['top']-1,p.width-30,p.height-37)).extract_text(x_tolerance=2) or ''
        bottom=re.sub(r'\n(?:[A-ZÁÉÍÓÚÑ /‘’]+|\d+)$','',bottom).strip()
        # Paragraph wraps are layout only. A single complete step is preferable
        # to inventing boundaries that could separate a warning from its action.
        steps=[clean(bottom)]
        results.append(recipe('book-polaca',title,pn,ingredients,steps))
    return results


if __name__=='__main__':
    for provider, filename, parser in [('book-polaca','mesa-polaca',polish)]:
        path=ROOT/'tmp/pdfs/fuentes-20261016'/f'{filename}.pdf'
        with pdfplumber.open(path) as pdf:rows=parser(pdf)
        assert all(r['ingredients'] and r['steps'] and any(re.search(r'\d',s) for s in r['ingredients']) for r in rows)
        payload={'provider':provider,'checked_at':'2026-10-16','document':CONFIG[provider]|{
            'sha256':sha256(path.read_bytes()).hexdigest(),'photo_pages':[int(r['origin']['id'])+1 for r in rows]},'recipes':rows}
        for directory in [ROOT/'server/licensed_collections',ROOT/'client/assets/catalogs']:
            directory.mkdir(parents=True,exist_ok=True)
            (directory/f'{provider}.json').write_text(json.dumps(payload,ensure_ascii=False,indent=2),encoding='utf-8')
        print(provider,len(rows),[(r['title'],len(r['ingredients']),len(r['steps'])) for r in rows])
