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
    for (const [uid,rol] of Object.entries({w1:'mesero',w2:'mesero',admin:'admin',super:'superadmin',k:'cocina',cash:'cajero',stock:'almacen',inactive:'mesero'})) {
      await setDoc(doc(db,'usuarios',uid),{rol,nombre:`Usuario ${uid}`,activo:uid!=='inactive'});
    }
    await setDoc(doc(db,'categorias/aves'),{nombre:'Aves',activo:true});
    await setDoc(doc(db,'carta/pollo'),{nombre:'Pollo',descripcion:'Brasa',categoriaId:'aves',precio:25.5,imagenUrl:'https://example.com/a.jpg',disponible:true});
    await setDoc(doc(db,'mesas/1'),{numero:'1',capacidad:4,activo:true,pedidoActivo:null});
  });
});
const db = uid => env.authenticatedContext(uid,{email_verified:true}).firestore();
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
async function status(database,id,state) {
  return runTransaction(database,async tx=>{
    const ref=doc(database,'pedidos',id);const d=(await tx.get(ref)).data();
    tx.update(ref,{estado:state,revision:d.revision+1,actualizadoEn:serverTimestamp()});
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
  await assertSucceeds(status(db('w1'),'a','cancelado'));
  await assertSucceeds(open(db('w2'),'w2','b'));
  await assertFails(item(db('w1'),'a',{mode:'edit'}));
});
test('pedido vacío no se registra, y registrado es inmutable y mantiene mesa ocupada',async()=>{
  await open(db('w1'),'w1','a');await assertFails(status(db('w1'),'a','registrado'));
  await item(db('w1'),'a');await assertSucceeds(status(db('w1'),'a','registrado'));
  await assertFails(item(db('w1'),'a',{mode:'edit'}));await assertFails(status(db('admin'),'a','cancelado'));
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
  await assertSucceeds(status(db('admin'),'a','cancelado'));
});
test('cocina y caja solo consultan; almacén, anónimo, inactivo y correo no verificado sin acceso',async()=>{
  await open(db('w1'),'w1','a');await item(db('w1'),'a');
  for(const uid of ['k','cash']) {
    await assertSucceeds(getDocs(collection(db(uid),'pedidos')));
    await assertSucceeds(getDocs(collection(db(uid),'pedidos/a/detalles')));
    await assertFails(status(db(uid),'a','registrado'));
  }
  for(const database of [anon(),db('stock'),db('inactive'),env.authenticatedContext('w1',{email_verified:false}).firestore()]) {
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
