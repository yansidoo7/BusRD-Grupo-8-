#!/usr/bin/env python3
"""Pruebas reales contra una instancia SQL Server 2022 DESECHABLE.
Borra BusRD y BusRD_Recuperada. No ejecutar contra producción.
No genera resultados de éxito si no hubo conexión y pruebas satisfactorias.
"""
import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import re
import time
import traceback
import pytds

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--recrear-base-pruebas', action='store_true', required=True)
parser.add_argument('--viaje', type=int, required=True, help='Viaje asignado; usar 16400 solo como ejemplo técnico')
args = parser.parse_args()
OUT = ROOT / 'evidencias' / time.strftime('%Y%m%d-%H%M%S')
OUT.mkdir(parents=True, exist_ok=False)
results = []

def connect(database='master'):
    return pytds.connect(os.getenv('BUSRD_HOST','127.0.0.1'),
        port=int(os.getenv('BUSRD_PORT','1433')), user=os.getenv('BUSRD_USER','sa'),
        password=os.environ['BUSRD_PASSWORD'], database=database,
        autocommit=True, timeout=240, login_timeout=10, appname='BusRD-Grupo8-validacion')

def collect(cur):
    sets = []
    while True:
        if cur.description:
            names = [d[0] for d in cur.description]
            rows = cur.fetchall()
            sets.append({'columnas':names,'filas':[list(row) for row in rows]})
        if not cur.nextset(): break
    return sets

def query(sql, database='BusRD'):
    with connect(database) as cn:
        with cn.cursor() as cur:
            cur.execute(sql)
            return collect(cur)

def scalar(sql, database='BusRD'):
    data = query(sql,database)
    return data[0]['filas'][0][0]

def record(name, detail):
    results.append({'prueba':name,'estado':'OK','detalle':detail})
    print('OK:',name,flush=True)

def require(ok, message):
    if not ok: raise AssertionError(message)

def script(path, label=None):
    path=ROOT/path
    log=[]
    # GO conserva la conexión y el contexto USE entre lotes.
    with connect() as cn:
        for number,batch in enumerate(re.split(r'^\s*GO\s*(?:--[^\n]*)?$',path.read_text(encoding='utf-8-sig'),flags=re.M|re.I),1):
            if not batch.strip():continue
            with cn.cursor() as cur:
                cur.execute(batch)
                data=collect(cur)
                messages=repr(cur.messages)
                log.append({'lote':number,'resultados':data,'mensajes':messages})
    (OUT/((label or path.stem)+'.json')).write_text(json.dumps(log,ensure_ascii=False,default=str,indent=2))
    record(label or path.name,'Ejecutado sin excepción SQL no controlada; resultados guardados')

FREE = '''SELECT MAX(s.NumeroAsiento) FROM dbo.Viajes v JOIN dbo.Asientos s ON s.AutobusID=v.AutobusID
WHERE v.ViajeID={v} AND NOT EXISTS(SELECT 1 FROM dbo.Boletos b
WHERE b.ViajeID=v.ViajeID AND b.NumeroAsiento=s.NumeroAsiento AND b.Estado='Activo')'''

def concurrency(safe):
    seat=scalar(FREE.format(v=args.viaje))
    require(seat is not None,'No hay asiento libre')
    # El recurso se selecciona ANTES de iniciar ambas conexiones.
    def sell(client):
        start=time.monotonic()
        sql=(f"DECLARE @id INT; EXEC dbo.sp_VenderBoleto {args.viaje},{seat},{client},'Web','Tarjeta',@id OUTPUT,1; SELECT @id;"
             if safe else f"EXEC dbo.sp_VenderBoleto_v0 {args.viaje},{seat},{client},'Web','Tarjeta';")
        try: return {'cliente':client,'ok':True,'resultado':query(sql),'segundos':time.monotonic()-start}
        except pytds.Error as ex:
            return {'cliente':client,'ok':False,'numero':getattr(ex,'number',None),'error':str(ex),'segundos':time.monotonic()-start}
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        a=pool.submit(sell,1)
        time.sleep(1)
        b=pool.submit(sell,2)
        ra,rb=a.result(),b.result()
    count=scalar(f"SELECT COUNT(*) FROM dbo.Boletos WHERE ViajeID={args.viaje} AND NumeroAsiento={seat} AND Estado='Activo'")
    name='concurrencia_segura' if safe else 'doble_venta_v0'
    detail={'viaje':args.viaje,'asiento':seat,'A':ra,'B':rb,'activos':count}
    (OUT/(name+'.json')).write_text(json.dumps(detail,ensure_ascii=False,default=str,indent=2))
    if safe:
        require(ra['ok'] and not rb['ok'] and rb.get('numero')==50007 and count==1,'No se demostró rechazo por asiento ocupado: '+str(detail))
        require(rb['segundos']>=7,'No se demostró espera de la segunda venta')
    else: require(ra['ok'] and rb['ok'] and count==2,'No se reprodujo la doble venta: '+str(detail))
    record(name,detail)

def metrics(phase):
    original=(ROOT/'recursos/03_consultas_lentas.sql').read_text()
    original=original.replace('INT = 16000','INT = '+str(args.viaje)).replace("'40200012345'","'40200008000'")
    if phase=='despues':
        s=(ROOT/'scripts/06_indices_y_consultas_optimizadas.sql').read_text()
        original=s[s.index('/* C1 optimizada */'):s.index('/* =========================================================\n   D.')]
        original=original.replace('(SELECT ViajeID FROM dbo.ConfiguracionGrupo WHERE GrupoID=8)',str(args.viaje))
    batches=re.split(r'^\s*GO\s*(?:--[^\n]*)?$',original,flags=re.M|re.I)
    logs=[]; num=0
    with connect('BusRD') as cn:
        for batch in batches:
            if not batch.strip() or not re.search(r'\bSELECT\b',batch,re.I):continue
            num+=1
            with cn.cursor() as cur:
                cur.execute('SET STATISTICS IO ON; SET STATISTICS TIME ON; SET STATISTICS XML ON;\n'+batch)
                sets=collect(cur)
                for data in sets:
                    for row in data['filas']:
                        if len(row)==1 and isinstance(row[0],str) and '<ShowPlanXML' in row[0]:
                            (OUT/f'C{num}_{phase}.sqlplan').write_text(row[0])
                logs.append({'consulta':num,'resultados':sets,'mensajes':repr(cur.messages)})
    (OUT/f'metricas_{phase}.json').write_text(json.dumps(logs,ensure_ascii=False,default=str,indent=2))
    record('metricas_'+phase,'Planes reales y mensajes del motor; no se inventan tiempos ni lecturas')

try:
    version=scalar('SELECT @@VERSION','master')
    require('SQL Server 2022' in version,'Se requiere SQL Server 2022: '+version)
    record('motor',version)
    script(Path('recursos/01_BusRD_base.sql'))
    script(Path('scripts/00_configuracion.sql'))
    query(f'UPDATE dbo.ConfiguracionGrupo SET ViajeID={args.viaje}, AsignacionConfirmada=0 WHERE GrupoID=8')
    require(scalar(f"SELECT COUNT(*) FROM dbo.Viajes WHERE ViajeID={args.viaje} AND Estado='Programado'")==1,'Viaje inválido o no Programado')
    script(Path('recursos/02_sp_VenderBoleto_v0.sql'))
    metrics('antes')
    concurrency(False)
    for file in ['01_integridad.sql','02_sp_VenderBoleto.sql','03_sp_AnularBoleto.sql']:
        script(Path('scripts')/file)
    require(scalar("SELECT COUNT(*) FROM (SELECT ViajeID,NumeroAsiento FROM dbo.Boletos WHERE Estado='Activo' GROUP BY ViajeID,NumeroAsiento HAVING COUNT(*)>1) d")==0,'Persisten duplicados')
    require(scalar('SELECT COUNT(*) FROM dbo.Pagos p LEFT JOIN dbo.Boletos b ON p.BoletoID=b.BoletoID WHERE b.BoletoID IS NULL')==0,'Persisten pagos huérfanos')
    require(scalar("SELECT COUNT(*) FROM sys.foreign_keys WHERE is_disabled=1 OR is_not_trusted=1")==0,'FK deshabilitada o no confiable')
    record('integridad','Sin duplicados ni huérfanos; FKs habilitadas y confiables')
    script(Path('validacion/assert_todos_los_viajes.sql'))
    concurrency(True)
    script(Path('validacion/assert_transacciones.sql'))
    # Anular dos veces no debe duplicar el reverso; el asiento debe poder revenderse.
    seat=scalar(FREE.format(v=args.viaje))
    sold=query(f"DECLARE @id INT; EXEC dbo.sp_VenderBoleto {args.viaje},{seat},1,'Web','Tarjeta',@id OUTPUT; SELECT @id;")
    boleto=sold[0]['filas'][0][0]
    query(f'EXEC dbo.sp_AnularBoleto {boleto}')
    require(scalar(f'SELECT SUM(Monto) FROM dbo.Pagos WHERE BoletoID={boleto}')==0,'Reverso no cuadra')
    try:
        query(f'EXEC dbo.sp_AnularBoleto {boleto}')
        raise AssertionError('Permitió doble anulación')
    except pytds.Error as ex: require(getattr(ex,'number',None)==50011,'Error inesperado al repetir anulación')
    query(f"DECLARE @id INT; EXEC dbo.sp_VenderBoleto {args.viaje},{seat},2,'Web','Tarjeta',@id OUTPUT;")
    record('anulacion','Reverso neto cero, doble anulación rechazada, asiento vendido de nuevo')
    script(Path('scripts/06_indices_y_consultas_optimizadas.sql'))
    metrics('despues')
    script(Path('validacion/assert_equivalencia.sql'))
    script(Path('scripts/07_seguridad.sql'))
    script(Path('validacion/assert_permisos.sql'))
    script(Path('scripts/08_respaldo_y_restauracion.sql'))
    require(scalar('SELECT COUNT(*) FROM tempdb.dbo.BusRD_VentasPrueba')==8,'No hubo ocho ventas')
    require(scalar('SELECT COUNT(*) FROM tempdb.dbo.BusRD_VentasPrueba t JOIN BusRD_Recuperada.dbo.Boletos b ON b.BoletoID=t.BoletoID','master')==8,'No se recuperaron las ocho ventas')
    for a,b in [('tempdb.dbo.BusRD_SnapshotBoletos',f'(SELECT * FROM BusRD_Recuperada.dbo.Boletos WHERE ViajeID={args.viaje})'),
                (f'(SELECT * FROM BusRD_Recuperada.dbo.Boletos WHERE ViajeID={args.viaje})','tempdb.dbo.BusRD_SnapshotBoletos')]:
        # Derivadas necesitan alias; usar una CTE para ambos orígenes.
        sa=f'SELECT * FROM {a}' if not a.startswith('(') else a[1:-1]
        sb=f'SELECT * FROM {b}' if not b.startswith('(') else b[1:-1]
        require(scalar(f'SELECT COUNT(*) FROM ({sa} EXCEPT {sb}) d','master')==0,'La restauración difiere de la referencia')
    record('recuperacion_STOPAT','Ocho ventas recuperadas y boletos del viaje idénticos en ambos sentidos')
except Exception as ex:
    results.append({'prueba':'validacion','estado':'FALLO','detalle':type(ex).__name__+': '+str(ex)})
    (OUT/'error.txt').write_text(traceback.format_exc())
    print('FALLO:',ex,flush=True)
    raise
finally:
    (OUT/'resumen.json').write_text(json.dumps(results,ensure_ascii=False,default=str,indent=2))
    print('Registros:',OUT,flush=True)
