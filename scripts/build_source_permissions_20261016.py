"""Publish the implemented source policy, separately from the research snapshot."""
from html import escape
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/fuentes-fiables-2026-10-16'


def main():
    sources=json.loads((ROOT/'server/sources.json').read_text(encoding='utf8'))
    researched=json.loads((OUT/'comparativa.json').read_text(encoding='utf8'))['sources']
    active={s['id']:s for s in sources}
    requests=json.loads((OUT/'solicitudes-permiso.json').read_text(encoding='utf8'))
    sent=sum(r['status']=='enviado_respuesta_pendiente' for r in requests)
    def request_status(name):
        row=next((r for r in requests if r['name']==name),{})
        return 'Solicitud enviada por Gmail; respuesta pendiente. No equivale a una autorización concedida.' if row.get('status')=='enviado_respuesta_pendiente' else 'Solicitud preparada en Gmail; no enviada ni concedida.'
    reasons={
      'ca-alberta':'Licencia CC BY 4.0 localizada; el servidor devuelve 403 a las descargas oficiales probadas. Sin adaptación operativa.',
      'mesa-polaca':'Integrada como book-polaca: 12 fichas en español, fotografías verificadas, CC BY 4.0. Texto incluido y fotografías del PDF mediante el PC.',
      'fao-chile':'Licencia publicada localizada. No se incorpora al catálogo fotográfico: usa ilustraciones y las páginas contiguas no siempre corresponden a la misma receta. Se detectó además una instrucción con film plástico en el horno que requiere aclaración editorial.',
      'ar-unlp':'Licencia localizada; faltan identificar los derechos y la correspondencia de cada imagen. No se activa un catálogo incompleto.',
      'fao-saberes':'Adaptación y traducción sujetas al aviso específico de esta obra. '+request_status('FAO · derechos y licencias'),
      'fao-guajira':'Obra grande, con posibles créditos de terceros. Faltan revisión visual y asociación de fotos; no se publica.',
      'co-picante':'Licencia editorial localizada; la descarga probada falló. Falta revisar recetas y fotografías.',
      'cl-uchile':'La cláusula SinDerivadas requiere resolver el alcance de las adaptaciones antes de distribuirlas.',
      'us-foodhero':request_status('Food Hero / Oregon State University'),
      'es-anna':request_status('Anna Recetas Fáciles'),
      'es-petitchef':'Catálogo e importación suspendidos en Mesa hasta autorización. '+request_status('Petitchef')+' Sigue disponible el enlace al sitio original.',
      'arasaac':'Referencia de accesibilidad; no es un catálogo fotográfico listo para importar.',
    }
    decisions=[]
    for row in researched:
        source=active.get(row['id'])
        if row['id'] in reasons:decision=reasons[row['id']]
        elif source and source['mode']!='book':decision='Integrada con licencia, créditos y enlace de origen; solo fichas con cantidades, preparación y foto.'
        else:decision=row['integration']+' No activada como catálogo autorizado.'
        decisions.append({'id':row['id'],'name':row['name'],'url':row['url'],'decision':decision})
    payload={'date':'2026-10-16','version':'1.15.0+31','registered_sources':len(sources),
       'enabled_catalogues':sum(s['mode']!='book' for s in sources),'pending_publishers':sum(s['mode']=='book' for s in sources),
       'new_catalogues':['es-creativegan','book-polaca'],'curated_photo_recipes':12,
       'permissions_requested':sent>0,'permission_requests_sent':sent,'permission_drafts':len(requests)-sent,'permissions_granted_by_email':0,
       'photos':'No image assets or persistent photo cache. PDF downloaded to PC RAM only, max 30 MB, one document, expires after 5 minutes; reviewed SHA-256 and pages only.',
       'research_decisions':decisions,'sources':sources}
    (OUT/'aplicacion-y-permisos.json').write_text(json.dumps(payload,ensure_ascii=False,indent=2),encoding='utf8')
    ranked=sorted(sources,key=lambda s:(s['recipe_count'] is None,-(s['recipe_count'] or 0),s['name']))
    rows=[];position=0
    for s in ranked:
        count=s['recipe_count']
        if count is not None:position+=1
        label='Total sin verificar' if count is None else f'{count:,}'.replace(',','.')
        if s['count_kind']=='reviewed_selection':label+=' fichas revisadas en Mesa'
        status='Consulta · autorización pendiente' if s['mode']=='book' else 'Texto incluido · fotos mediante PC' if s['mode']=='asset' else 'Catálogo con licencia'
        license=s.get('license') or 'Permiso general no verificado'
        rows.append(f'<tr><td>{position if count is not None else "—"}</td><td><a href="{escape(s["url"],quote=True)}">{escape(s["name"])}</a><small>{escape(s["country"])}</small></td><td>{label}<small>{escape(s["count_kind"])} · {s["count_checked_at"]}</small></td><td>{status}<small>{escape(license)}</small></td><td>{escape(s["count_note"])} <a href="{escape(s["count_evidence"] or s["url"],quote=True)}">Comprobar cifra</a></td></tr>')
    details=''.join(f'<details><summary>{escape(r["name"])}</summary><p>{escape(r["decision"])}</p><a href="{escape(r["url"],quote=True)}">Evidencia y sitio original</a></details>' for r in decisions)
    html='''<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Mesa · fuentes y permisos aplicados</title>
<style>body{margin:0;background:#f7f4eb;color:#24372e;font:17px/1.6 system-ui}main{max-width:1180px;margin:auto;padding:30px 22px 70px}section,header{background:white;border-radius:24px;padding:26px;margin-bottom:22px}h1{font-size:clamp(28px,5vw,43px);line-height:1.2}h2{font-size:25px}a{color:#215a43;text-underline-offset:3px}small{display:block;color:#536459;font-size:14px}input{box-sizing:border-box;width:100%;border:2px solid #647c6c;border-radius:14px;font:inherit;padding:12px;margin:12px 0}table{border-collapse:collapse;width:100%;font-size:15px}th,td{text-align:left;padding:15px 12px;border-bottom:1px solid #dce3db;vertical-align:top}th{background:#ecf3eb}.table{overflow:auto}details{padding:15px 0;border-bottom:1px solid #dce3db}summary{cursor:pointer;font-weight:650}a:focus-visible,summary:focus-visible{outline:3px solid #aa5d3e;outline-offset:5px}.meta{color:#526458}ul{padding-left:24px}</style>
<main><header><p class="meta">Mesa 1.15.0 · revisión del 16 de octubre de 2026</p><h1>Fuentes disponibles y permisos</h1><p>24 fuentes registradas: 10 catálogos habilitados y 14 sitios de consulta pendientes de autorización. El tamaño anunciado por un editor no equivale al número de fichas importables en Mesa.</p><p>CreatiVegan incorpora un lector propio para evitar duplicaciones. Mesa polaca añade 12 fichas con fotografías, cantidades originales y licencia CC BY 4.0. Las recetas ya guardadas por la familia se conservan.</p><p><strong>Autorizaciones externas:</strong> __PERMISSION_STATUS__</p></header>
<section><h2>Fotografías y apertura rápida</h2><p>Los textos de Mesa polaca se abren sin descargar el PDF. Sus fotos requieren conectar Mesa al ordenador: este consulta el documento oficial, comprueba su huella y extrae únicamente la imagen de una página revisada. La primera foto puede esperar a la descarga del PDF (21 MB). El documento permanece temporalmente en RAM hasta cinco minutos; no se guardan fotografías en disco, en la APK, en las recetas ni en la sincronización.</p><p>Las fotos de CreatiVegan se consultan directamente desde Internet. Se excluyen anuncios y portadas de libros ajenos a la preparación. Se conservan autoría, licencia y marcas de agua.</p></section>
<section><h2>Ranking completo de las 24 fuentes</h2><p>Los recuentos históricos conservan su fecha de comprobación. «Total sin verificar» no significa cero. Mesa polaca cuenta solo las fichas revisadas incluidas, no todo el fondo editorial.</p><label>Buscar fuente, país, licencia o estado<input id="search" type="search" autocomplete="off" placeholder="Ej.: CreatiVegan, México, pendiente"></label><p id="count" role="status">24 fuentes</p><div class="table"><table><thead><tr><th>Puesto</th><th>Fuente</th><th>Cantidad y fecha</th><th>Disponibilidad y licencia</th><th>Alcance del recuento</th></tr></thead><tbody>ROWS</tbody></table></div></section>
<section><h2>Decisión sobre las 30 fuentes y servicios investigados</h2><p>Las fuentes retiradas por petición anterior no se reactivan sin revisar sus condiciones. Una licencia publicada no elimina bloqueos técnicos, derechos de terceros o errores editoriales.</p>DETAILS</section>
<section><h2>Documentación verificable</h2><ul><li><a href="investigacion-fuentes-fiables-2026-10-16.html">Investigación inicial y evidencias</a></li><li><a href="output/fuentes-fiables-2026-10-16/aplicacion-y-permisos.json">Estado aplicado y decisiones en JSON</a></li><li><a href="https://creativegan.net/archives/licencias-fotos-y-recetas/">Condiciones de CreatiVegan</a></li><li><a href="https://bunkatura.pl/pdf/mesa_polaca.pdf#page=128">Créditos y licencia de Mesa polaca</a></li></ul></section></main>
<script>const input=document.querySelector('#search');input.addEventListener('input',()=>{let n=0;const q=input.value.toLocaleLowerCase('es').normalize('NFD').replace(/[\\u0300-\\u036f]/g,'');document.querySelectorAll('tbody tr').forEach(row=>{row.hidden=!row.textContent.toLocaleLowerCase('es').normalize('NFD').replace(/[\\u0300-\\u036f]/g,'').includes(q);if(!row.hidden)n++});document.querySelector('#count').textContent=n+' de 24 fuentes'});</script></html>'''.replace('ROWS',''.join(rows)).replace('DETAILS',details).replace('__PERMISSION_STATUS__',f'{sent} solicitudes enviadas por Gmail con autorización del usuario. Se solicita uso gratuito, familiar y privado, fotografías con créditos y adaptaciones identificadas. Las respuestas y los permisos siguen pendientes; el envío no concede autorización. {len(requests)-sent} borradores sin enviar.')
    validation=OUT/'publicacion-1.15.0-31.json'
    if validation.exists():
        html=html.replace('<section><h2>Documentación verificable</h2>', '<section><h2>Comprobación de la publicación</h2><p>162 pruebas del cliente y 121 del servidor aprobadas, análisis sin incidencias y una prueba adicional del lector Flutter con la fuente real. Windows compilado y abierto. Android release probado en MesaTest: creación, guardado, cantidades, cocina, reinicio y cuatro destinos. APK ARM64 descargada por HTTPS y firma familiar verificada. No se ha instalado en un teléfono físico.</p><p><a href="output/fuentes-fiables-2026-10-16/publicacion-1.15.0-31.json">Ver evidencias y límites de la comprobación</a></p></section><section><h2>Documentación verificable</h2>')
    for name in ['estado-fuentes-mesa.html','aplicacion-fuentes-2026-10-16.html']:(ROOT/name).write_text(html,encoding='utf8')
    # Keep the original research as a dated snapshot with a prominent correction.
    report=ROOT/'investigacion-fuentes-fiables-2026-10-16.html'
    content=report.read_text(encoding='utf8')
    banner='<aside style="padding:20px;background:#fff2d7;color:#25372e">Actualización de implementación: <a href="aplicacion-fuentes-2026-10-16.html">ver fuentes aplicadas y permisos pendientes</a>. FAO Chile utiliza ilustraciones; no se incorpora como catálogo fotográfico.</aside>'
    if 'Actualización de implementación:' not in content:report.write_text(content.replace('<body>','<body>'+banner,1),encoding='utf8')
    print(json.dumps({k:payload[k] for k in ['registered_sources','enabled_catalogues','pending_publishers','curated_photo_recipes']}))


if __name__=='__main__':main()
