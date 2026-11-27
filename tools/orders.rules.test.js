const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, collection, getDoc, getDocs, setDoc, updateDoc, deleteDoc, writeBatch, runTransaction,
  serverTimestamp, query, where, onSnapshot } = require('firebase/firestore');
let env;
const host = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8180').split(':');
before(async () => {
  env = await initializeTestEnvironment({projectId:'demo-la-granja-azul-orders',firestore:{
    host:host[0],port:Number(host[1]),rules:fs.readFileSync(path.join(__dirname,'..','firestore.rules'),'utf8')}});
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async ctx => {
    const db=ctx.firestore();
    for (const [uid,rol] of Object.entries({w1:'mesero',w2:'mesero',admin:'admin',super:'superadmin',k:'cocina',cash:'cajero',inactive:'mesero'})) {
      await setDoc(doc(db,'usuarios',uid),{rol,nombre:`Usuario ${uid}`,activo:uid!=='inactive'});
    }
    // Fase 2: el personal no exento necesita la jornada abierta para operar.
    for (const uid of ['w1','w2','k','cash','inactive']) await setDoc(doc(db,'estadoAsistencia',uid),{abierta:true,asistenciaId:'a'+uid});
    await setDoc(doc(db,'categorias/aves'),{nombre:'Aves',activo:true});
    await setDoc(doc(db,'carta/pollo'),{nombre:'Pollo',descripcion:'Brasa',categoriaId:'aves',precio:25.5,imagenUrl:'https://example.com/a.jpg',disponible:true});
    await setDoc(doc(db,'mesas/1'),{numero:'1',capacidad:4,activo:true,pedidoActivo:null});
  });
});
const db = uid => { const d=env.authenticatedContext(uid,{email_verified:true}).firestore(); d.uid=uid; return d; };
const anon = () => env.unauthenticatedContext().firestore();
function orderData(uid,table='1') {return {mesaId:table,meseroId:uid,meseroNombre:`Usuario ${uid}`,estado:'abierto',revision:0,cantidadDetalles:0,detalleModificado:'',creadoEn:serverTimestamp(),actualizadoEn:serverTimestamp()};}
async function open(database,uid,id,table='1') {
  return runTransaction(database,async tx=>{
    const ref=doc(database,'mesas',table);const d=(await tx.get(ref)).data();
    if(!d.activo || d.pedidoActivo!==null) throw Error('Mesa ocupada o inactiva');
    tx.set(doc(database,'pedidos',id),orderData(uid,table));tx.update(ref,{pedidoActivo:id});
  });
}
async function item(database,id,{quantity=2,notes='Sin sal',mode='add',patch={}}={}) {
  return runTransaction(database,async tx=>{
    const ref=doc(database,'pedidos',id); const order=(await tx.get(ref)).data();
    const line=doc(database,'pedidos',id,'detalles','pollo');
    const existing=(await tx.get(line)).data();
    let data;
    if(mode==='add') {
      const dish=(await tx.get(doc(database,'carta/pollo'))).data();
      data={nombre:dish.nombre,precio:dish.precio,cantidad:quantity,observaciones:notes,...patch};
    } else if(mode==='edit') data={...existing,cantidad:quantity,observaciones:notes,...patch};
    if(mode==='remove') tx.delete(line);else tx.set(line,data);
    tx.update(ref,{revision:order.revision+1,cantidadDetalles:order.cantidadDetalles+(mode==='add'?1:mode==='remove'?-1:0),detalleModificado:'pollo',actualizadoEn:serverTimestamp()});
  });
}
async function status(database,id,state,uid,patch={}) {
  return runTransaction(database,async tx=>{
    const ref=doc(database,'pedidos',id);const d=(await tx.get(ref)).data();
    const why=state==='cancelado'?{motivoCancelacion:'Cliente se fue',canceladoPor:uid}
      :state==='registrado'?{estadoCocina:'pendiente',registradoEn:serverTimestamp()}:{};
    tx.update(ref,{estado:state,revision:d.revision+1,actualizadoEn:serverTimestamp(),...why,...patch});
    if(state==='cancelado')tx.update(doc(database,'mesas',d.mesaId),{pedidoActivo:null});
  });
}
test('admin y super crean y editan mesas; número único y capacidad válida',async()=>{
  for(const uid of ['admin','super']) {
    const database=db(uid); const number=uid==='admin'?'2':'3';
    await assertSucceeds(setDoc(doc(database,'mesas',number),{numero:number,capacidad:6,activo:true,pedidoActivo:null}));
    await assertSucceeds(updateDoc(doc(database,'mesas',number),{capacidad:8,activo:false}));
    await assertSucceeds(updateDoc(doc(database,'mesas',number),{activo:true}));
  }
  for(const patch of [{capacidad:0},{capacidad:51},{capacidad:2.5},{numero:'2'},{extra:1}])
    await assertFails(updateDoc(doc(db('admin'),'mesas/1'),patch));
  await assertFails(setDoc(doc(db('admin'),'mesas/01'),{numero:'01',capacidad:4,activo:true,pedidoActivo:null}));
  await assertFails(deleteDoc(doc(db('super'),'mesas/1')));
});
test('dos meseros simultáneos: solo un pedido adquiere la mesa',async()=>{
  const results=await Promise.allSettled([open(db('w1'),'w1','a'),open(db('w2'),'w2','b')]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
  const orders=await getDocs(collection(db('admin'),'pedidos'));assert.equal(orders.size,1);
  const table=(await getDoc(doc(db('admin'),'mesas/1'))).data();assert.equal(table.pedidoActivo,orders.docs[0].id);
});
test('no se puede crear pedido sin bloquear mesa o en mesa inactiva',async()=>{
  await assertFails(setDoc(doc(db('w1'),'pedidos/a'),orderData('w1')));
  await updateDoc(doc(db('admin'),'mesas/1'),{activo:false});
  const database=db('w1');const batch=writeBatch(database);batch.set(doc(database,'pedidos/a'),orderData('w1'));batch.update(doc(database,'mesas/1'),{pedidoActivo:'a'});
  await assertFails(batch.commit());
});
test('no se puede desactivar, borrar ni liberar una mesa ocupada por fuera del pedido',async()=>{
  await open(db('w1'),'w1','a');
  for(const uid of ['admin','super','w1']) {
    await assertFails(updateDoc(doc(db(uid),'mesas/1'),{activo:false}));
    await assertFails(updateDoc(doc(db(uid),'mesas/1'),{pedidoActivo:null}));
  }
});
test('cancelar libera la mesa atómicamente y permite un nuevo pedido',async()=>{
  await open(db('w1'),'w1','a');await item(db('w1'),'a');
  await assertFails(updateDoc(doc(db('w1'),'pedidos/a'),{estado:'cancelado',revision:2,actualizadoEn:serverTimestamp()}));
  await assertSucceeds(status(db('w1'),'a','cancelado','w1'));
  await assertSucceeds(open(db('w2'),'w2','b'));
  await assertFails(item(db('w1'),'a',{mode:'edit'}));
});
test('pedido vacío no se registra, y registrado es inmutable y mantiene mesa ocupada',async()=>{
  await open(db('w1'),'w1','a');await assertFails(status(db('w1'),'a','registrado'));
  await item(db('w1'),'a');await assertSucceeds(status(db('w1'),'a','registrado'));
  await assertFails(item(db('w1'),'a',{mode:'edit'}));await assertFails(status(db('admin'),'a','cancelado','admin'));
  await assertFails(status(db('admin'),'a','abierto'));await assert.rejects(open(db('w2'),'w2','b'),/ocupada/);
  const database=db('w2');const batch=writeBatch(database);batch.set(doc(database,'pedidos/b'),orderData('w2'));batch.update(doc(database,'mesas/1'),{pedidoActivo:'b'});await assertFails(batch.commit());
});
test('agregar, editar y retirar cantidades y observaciones; contador no falsificable',async()=>{
  await open(db('w1'),'w1','a');await assertSucceeds(item(db('w1'),'a'));
  await assertSucceeds(item(db('w1'),'a',{mode:'edit',quantity:3,notes:'Sin ají'}));
  assert.equal((await getDoc(doc(db('w1'),'pedidos/a/detalles/pollo'))).data().cantidad,3);
  await assertFails(updateDoc(doc(db('w1'),'pedidos/a'),{cantidadDetalles:2,revision:3,actualizadoEn:serverTimestamp()}));
  await assertFails(updateDoc(doc(db('w1'),'pedidos/a/detalles/pollo'),{cantidad:9}));
  await assertSucceeds(item(db('w1'),'a',{mode:'remove'}));
  assert.equal((await getDoc(doc(db('w1'),'pedidos/a'))).data().cantidadDetalles,0);
});
test('snapshot de nombre y precio persiste tras cambiar carta; no se puede falsificar',async()=>{
  await open(db('w1'),'w1','a');
  await assertFails(item(db('w1'),'a',{patch:{precio:1}}));
  await assertFails(item(db('w1'),'a',{patch:{nombre:'Falso'}}));
  await item(db('w1'),'a');
  await updateDoc(doc(db('admin'),'carta/pollo'),{nombre:'Pollo nuevo',precio:40,disponible:false});
  await updateDoc(doc(db('admin'),'categorias/aves'),{activo:false});
  await assertSucceeds(item(db('w1'),'a',{mode:'edit',quantity:4}));
  const d=(await getDoc(doc(db('w1'),'pedidos/a/detalles/pollo'))).data();assert.equal(d.precio,25.5);assert.equal(d.nombre,'Pollo');
  await assertFails(item(db('admin'),'a',{mode:'edit',patch:{precio:40}}));
});
test('no se agregan platos no disponibles ni categorías inactivas',async()=>{
  await open(db('w1'),'w1','a');await updateDoc(doc(db('admin'),'carta/pollo'),{disponible:false});
  await assertFails(item(db('w1'),'a'));await updateDoc(doc(db('admin'),'carta/pollo'),{disponible:true});
  await updateDoc(doc(db('admin'),'categorias/aves'),{activo:false});await assertFails(item(db('w1'),'a'));
});
test('mesero no lee ni modifica pedidos ajenos; no cambia responsable, mesa ni fecha',async()=>{
  await open(db('w1'),'w1','a');
  await assertFails(getDoc(doc(db('w2'),'pedidos/a')));await assertFails(item(db('w2'),'a'));
  await assertFails(getDocs(collection(db('w1'),'pedidos')));
  await assertSucceeds(getDocs(query(collection(db('w1'),'pedidos'),where('meseroId','==','w1'))));
  for(const patch of [{meseroId:'w2'},{meseroNombre:'Falso'},{mesaId:'2'},{creadoEn:serverTimestamp()}])
    await assertFails(updateDoc(doc(db('w1'),'pedidos/a'),{...patch,revision:1,actualizadoEn:serverTimestamp()}));
  const database=db('w2');const batch=writeBatch(database);batch.set(doc(database,'pedidos/forged'),orderData('w1'));batch.update(doc(database,'mesas/1'),{pedidoActivo:'forged'});await assertFails(batch.commit());
});
test('administradores gestionan pedidos abiertos ajenos sin reasignar responsable',async()=>{
  await open(db('w1'),'w1','a');await assertSucceeds(item(db('admin'),'a'));
  await assertSucceeds(item(db('super'),'a',{mode:'edit',quantity:5}));
  await assertFails(updateDoc(doc(db('super'),'pedidos/a'),{meseroId:'super',revision:3,actualizadoEn:serverTimestamp()}));
  await assertSucceeds(status(db('admin'),'a','cancelado','admin'));
});
test('cocina y caja solo consultan; almacén, anónimo, inactivo y correo no verificado sin acceso',async()=>{
  await open(db('w1'),'w1','a');await item(db('w1'),'a');
  for(const uid of ['k','cash']) {
    await assertSucceeds(getDocs(collection(db(uid),'pedidos')));
    await assertSucceeds(getDocs(collection(db(uid),'pedidos/a/detalles')));
    await assertFails(status(db(uid),'a','registrado'));
  }
  for(const database of [anon(),db('inactive'),env.authenticatedContext('w1',{email_verified:false}).firestore()]) {
    await assertFails(getDocs(collection(database,'pedidos')));
    await assertFails(getDocs(collection(database,'mesas')));
    await assertFails(setDoc(doc(database,'pedidos/b'),orderData('w1')));
  }
  await assertFails(updateDoc(doc(db('w1'),'mesas/1'),{capacidad:10}));
});
test('valida detalles, esquemas y transiciones inventadas',async()=>{
  await open(db('w1'),'w1','a');
  for(const patch of [{cantidad:0},{cantidad:100},{cantidad:1.5},{observaciones:'x'.repeat(501)},{extra:true}])
    await assertFails(item(db('w1'),'a',{patch}));
  await assertFails(updateDoc(doc(db('w1'),'pedidos/a'),{estado:'pagado',revision:1,actualizadoEn:serverTimestamp()}));
  await assertFails(deleteDoc(doc(db('admin'),'pedidos/a')));
});
test('datos persistidos se leen desde otro cliente y los cambios se notifican en vivo',async()=>{
  await open(db('w1'),'w1','a');
  const fresh=env.authenticatedContext('w1',{email_verified:true}).firestore();
  assert.equal((await getDoc(doc(fresh,'pedidos/a'))).data().mesaId,'1');
  let stop;
  const changed=new Promise((resolve,reject)=>{
    const timer=setTimeout(()=>reject(Error('No llegó actualización en tiempo real')),10000);
    stop=onSnapshot(doc(fresh,'pedidos/a'),snapshot=>{
      if(snapshot.data()?.cantidadDetalles===1){clearTimeout(timer);resolve();}
    },reject);
  });
  try{await item(db('w1'),'a');await changed;}finally{stop();}
});

test('desactivar y abrir simultáneamente nunca deja pedido en mesa inactiva',async()=>{
  await Promise.allSettled([open(db('w1'),'w1','a'),updateDoc(doc(db('admin'),'mesas/1'),{activo:false})]);
  const table=(await getDoc(doc(db('admin'),'mesas/1'))).data();
  const orders=await getDocs(collection(db('admin'),'pedidos'));
  assert.ok(table.activo || orders.empty);
  assert.equal(table.pedidoActivo!==null,orders.size===1);
});

test('cancelar exige motivo y a quien cancela; el pedido conserva ambos',async()=>{
  await open(db('w1'),'w1','a');await item(db('w1'),'a');
  for(const patch of [{motivoCancelacion:''},{motivoCancelacion:'ab'},{motivoCancelacion:'x'.repeat(201)},{canceladoPor:'w2'},{canceladoPor:'admin'}])
    await assertFails(status(db('w1'),'a','cancelado','w1',patch));
  // Sin los campos (cliente antiguo) tampoco se puede cancelar.
  const legacy=db('w1');
  await assertFails(runTransaction(legacy,async tx=>{
    const ref=doc(legacy,'pedidos/a');const d=(await tx.get(ref)).data();
    tx.update(ref,{estado:'cancelado',revision:d.revision+1,actualizadoEn:serverTimestamp()});
    tx.update(doc(legacy,'mesas/1'),{pedidoActivo:null});
  }));
  await assertSucceeds(status(db('w1'),'a','cancelado','w1'));
  const order=(await getDoc(doc(db('admin'),'pedidos/a'))).data();
  assert.equal(order.motivoCancelacion,'Cliente se fue');assert.equal(order.canceladoPor,'w1');
});
test('el motivo de cancelación no entra en pedidos abiertos ni registrados',async()=>{
  await open(db('w1'),'w1','a');await item(db('w1'),'a');
  await assertFails(updateDoc(doc(db('w1'),'pedidos/a'),{motivoCancelacion:'Cliente se fue',canceladoPor:'w1',revision:2,actualizadoEn:serverTimestamp()}));
  await assertFails(status(db('w1'),'a','registrado','w1',{motivoCancelacion:'Cliente se fue',canceladoPor:'w1'}));
  const database=db('w2');const batch=writeBatch(database);
  batch.set(doc(database,'pedidos/b'),{...orderData('w2'),motivoCancelacion:'Cliente se fue',canceladoPor:'w2'});
  batch.update(doc(database,'mesas/1'),{pedidoActivo:'b'});
  await assertFails(batch.commit());
});
test('un pedido cancelado no se puede reabrir ni cambiar su motivo',async()=>{
  await open(db('w1'),'w1','a');await assertSucceeds(status(db('w1'),'a','cancelado','w1'));
  await assertFails(updateDoc(doc(db('admin'),'pedidos/a'),{motivoCancelacion:'Otro',revision:2,actualizadoEn:serverTimestamp()}));
  await assertFails(updateDoc(doc(db('admin'),'pedidos/a'),{estado:'abierto',revision:2,actualizadoEn:serverTimestamp()}));
});

// ------------------------------------------------------------ Fase 5: cocina
async function kitchen(database,id,to,patch={}) {
  return runTransaction(database,async tx=>{
    const ref=doc(database,'pedidos',id);const d=(await tx.get(ref)).data();
    const stamp={preparando:{preparandoEn:serverTimestamp(),cocinaPor:'k'},listo:{listoEn:serverTimestamp()},entregado:{entregadoEn:serverTimestamp()}}[to]||{};
    // Fase 8B: pasar a «listo» exige el documento de descuento (aquí sin insumos).
    if(to==='listo'&&database.uid) tx.set(doc(database,'descuentosInventario',id),{insumos:0,platosSinReceta:0,insumosOmitidos:0,creadoPor:database.uid,creadoPorNombre:'Usuario '+database.uid,creadoEn:serverTimestamp()});
    tx.update(ref,{estadoCocina:to,revision:d.revision+1,actualizadoEn:serverTimestamp(),...stamp,...patch});
  });
}
async function registered(uid='w1',id='a') {
  await open(db(uid),uid,id);await item(db(uid),id);await status(db(uid),id,'registrado',uid);
}
test('registrar deja el pedido pendiente en cocina con la hora del servidor',async()=>{
  await registered();
  const o=(await getDoc(doc(db('admin'),'pedidos/a'))).data();
  assert.equal(o.estado,'registrado');assert.equal(o.estadoCocina,'pendiente');assert.ok(o.registradoEn);
});
test('no se registra sin entrar a cocina, ni con otro estado o hora falsa',async()=>{
  await open(db('w1'),'w1','a');await item(db('w1'),'a');
  const legacy=db('w1');
  await assertFails(runTransaction(legacy,async tx=>{const ref=doc(legacy,'pedidos/a');const d=(await tx.get(ref)).data();
    tx.update(ref,{estado:'registrado',revision:d.revision+1,actualizadoEn:serverTimestamp()});}));
  await assertFails(status(db('w1'),'a','registrado','w1',{estadoCocina:'listo'}));
  await assertFails(status(db('w1'),'a','registrado','w1',{registradoEn:new Date(0)}));
  await assertFails(status(db('w1'),'a','registrado','w1',{preparandoEn:serverTimestamp()}));
  await assertSucceeds(status(db('w1'),'a','registrado','w1'));
});
test('flujo completo: cocina prepara y marca listo; el mesero responsable entrega',async()=>{
  await registered();
  await assertSucceeds(kitchen(db('k'),'a','preparando'));
  await assertSucceeds(kitchen(db('k'),'a','listo'));
  await assertFails(kitchen(db('k'),'a','entregado'));
  await assertFails(kitchen(db('w2'),'a','entregado'));
  await assertFails(kitchen(db('cash'),'a','entregado'));
  await assertSucceeds(kitchen(db('w1'),'a','entregado'));
  const o=(await getDoc(doc(db('admin'),'pedidos/a'))).data();
  assert.equal(o.estadoCocina,'entregado');
  for(const f of ['preparandoEn','listoEn','entregadoEn','cocinaPor','registradoEn']) assert.ok(o[f],f);
  assert.equal(o.cocinaPor,'k');
  await assertFails(kitchen(db('k'),'a','listo')); // terminal
});
test('no se saltan ni se revierten pasos de cocina',async()=>{
  await registered();
  await assertFails(kitchen(db('k'),'a','listo'));
  await assertFails(kitchen(db('k'),'a','entregado'));
  await assertFails(kitchen(db('k'),'a','pendiente'));
  await assertSucceeds(kitchen(db('k'),'a','preparando'));
  await assertFails(kitchen(db('k'),'a','preparando'));
  await assertFails(kitchen(db('k'),'a','pendiente'));
  await assertFails(kitchen(db('k'),'a','inventado'));
});
test('solo cocina y administración mueven la cocina; el mesero ni el suyo',async()=>{
  await registered();
  for(const uid of ['w1','w2','cash','inactive']) await assertFails(kitchen(db(uid),'a','preparando'));
  await assertFails(kitchen(anon(),'a','preparando'));
  await assertFails(kitchen(env.authenticatedContext('k',{email_verified:false}).firestore(),'a','preparando'));
  await assertSucceeds(kitchen(db('admin'),'a','preparando',{cocinaPor:'admin'}));
  await assertSucceeds(kitchen(db('super'),'a','listo'));
  await assertSucceeds(kitchen(db('admin'),'a','entregado'));
});
test('cocina sin jornada abierta pierde el acceso; el admin está exento',async()=>{
  await registered();
  await env.withSecurityRulesDisabled(ctx=>updateDoc(doc(ctx.firestore(),'estadoAsistencia/k'),{abierta:false}));
  await assertFails(kitchen(db('k'),'a','preparando'));
  await assertFails(getDoc(doc(db('k'),'pedidos/a')));
  await assertSucceeds(kitchen(db('admin'),'a','preparando',{cocinaPor:'admin'}));
});
test('el mesero sin jornada abierta no entrega',async()=>{
  await registered();await kitchen(db('k'),'a','preparando');await kitchen(db('k'),'a','listo');
  await env.withSecurityRulesDisabled(ctx=>updateDoc(doc(ctx.firestore(),'estadoAsistencia/w1'),{abierta:false}));
  await assertFails(kitchen(db('w1'),'a','entregado'));
  await assertSucceeds(kitchen(db('admin'),'a','entregado'));
});
test('la actualización de cocina no cambia nada más del pedido',async()=>{
  await registered();
  for(const patch of [{meseroId:'k'},{meseroNombre:'Falso'},{mesaId:'2'},{estado:'cancelado',motivoCancelacion:'abc def',canceladoPor:'k'},
    {cantidadDetalles:0},{detalleModificado:'otro'},{preparandoEn:new Date(0)},{cocinaPor:'w2'},{extra:1},{registradoEn:serverTimestamp()},
    {revision:99}])
    await assertFails(kitchen(db('k'),'a','preparando',patch));
  await assertFails(kitchen(db('k'),'a','preparando',{listoEn:serverTimestamp()}));
  await assertSucceeds(kitchen(db('k'),'a','preparando'));
});
test('cocina no edita ni cancela pedidos, y un pedido abierto o cancelado no entra a cocina',async()=>{
  await open(db('w1'),'w1','a');await item(db('w1'),'a');
  await assertFails(kitchen(db('k'),'a','preparando')); // abierto
  await assertFails(status(db('k'),'a','registrado','k'));
  await assertFails(status(db('k'),'a','cancelado','k'));
  await assertSucceeds(status(db('w1'),'a','cancelado','w1'));
  await assertFails(kitchen(db('k'),'a','preparando')); // cancelado
  await assertFails(updateDoc(doc(db('admin'),'pedidos/a'),{estadoCocina:'pendiente',revision:3,actualizadoEn:serverTimestamp()}));
});
test('un pedido registrado antes de la Fase 5 cuenta como pendiente',async()=>{
  await env.withSecurityRulesDisabled(async ctx=>{
    const d=ctx.firestore();
    await setDoc(doc(d,'mesas/1'),{numero:'1',capacidad:4,activo:true,pedidoActivo:'old'});
    await setDoc(doc(d,'pedidos/old'),{mesaId:'1',meseroId:'w1',meseroNombre:'Usuario w1',estado:'registrado',revision:2,
      cantidadDetalles:1,detalleModificado:'pollo',creadoEn:new Date(),actualizadoEn:new Date()});
  });
  await assertSucceeds(kitchen(db('k'),'old','preparando'));
});
test('el estado de cocina es legible para quien ve el pedido y no para ajenos',async()=>{
  await registered();
  await assertSucceeds(getDoc(doc(db('k'),'pedidos/a')));
  await assertSucceeds(getDoc(doc(db('w1'),'pedidos/a')));
  await assertFails(getDoc(doc(db('w2'),'pedidos/a')));
  await assertFails(getDoc(doc(anon(),'pedidos/a')));
});
